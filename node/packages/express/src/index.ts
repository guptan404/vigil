import type { ErrorRequestHandler, NextFunction, Request, RequestHandler, Response } from "express";
import {
  encodeDebugPayload,
  generateTraceparent,
  parseTraceparent,
  serializeServerTiming,
  type ServerTimingMetric,
} from "@vigil/core";

export interface VigilExpressConfig {
  enabled?: boolean;
  includeTotalTiming?: boolean;
  passThroughErrors?: boolean;
  debugKey?: string;
  maskHeaders?: string[];
  maskBodyFields?: string[];
  headerLimitBytes?: number;
}

export interface VigilIngestConfig {
  enabled?: boolean;
  ingestKey?: string;
  maxBatchCalls?: number;
  onBatch?: (batch: VigilIngestBatch, req: Request) => Promise<void> | void;
}

export interface VigilIngestBatch {
  version: number;
  sentAt?: string;
  client?: Record<string, unknown>;
  calls: VigilIngestCall[];
}

export type VigilIngestCall = Record<string, unknown>;

export interface VigilMemorySink {
  batches: VigilIngestBatch[];
  calls: VigilIngestCall[];
  onBatch(batch: VigilIngestBatch): void;
  clear(): void;
}

export interface VigilRequestContext {
  traceparent: string;
  timings: ServerTimingMetric[];
  time<T>(name: string, description: string, fn: () => Promise<T> | T): Promise<T>;
}

declare global {
  namespace Express {
    interface Request {
      vigil: VigilRequestContext;
    }
  }
}

export function vigilMiddleware(config: VigilExpressConfig = {}) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!isEnabled(config)) {
      req.vigil = createNoopContext(req.header("traceparent"));
      next();
      return;
    }

    const incomingTrace = req.header("traceparent");
    const traceparent = parseTraceparent(incomingTrace) ? incomingTrace! : generateTraceparent();
    const timings: ServerTimingMetric[] = [];
    const requestStartedAt = process.hrtime.bigint();

    req.vigil = {
      traceparent,
      timings,
      async time<T>(name: string, description: string, fn: () => Promise<T> | T): Promise<T> {
        const start = process.hrtime.bigint();
        try {
          return await fn();
        } finally {
          const end = process.hrtime.bigint();
          timings.push({
            name,
            description,
            duration: Number(end - start) / 1_000_000,
          });
        }
      },
    };

    patchWriteHead(res, () => {
      if (config.includeTotalTiming ?? true) {
        const responseStartedAt = process.hrtime.bigint();
        timings.unshift({
          name: "total",
          description: "Total server time",
          duration: Number(responseStartedAt - requestStartedAt) / 1_000_000,
        });
      }
      if (timings.length > 0 && !res.headersSent) {
        const header = serializeServerTiming(timings, config.headerLimitBytes ?? 4096);
        if (header) res.setHeader("Server-Timing", header);
      }
    });

    res.setHeader("traceparent", traceparent);
    next();
  };
}

export function vigilErrorHandler(config: VigilExpressConfig = {}): ErrorRequestHandler {
  return (error, req, res, next) => {
    if (res.headersSent) {
      next(error);
      return;
    }

    const enabled = isEnabled(config);
    const debugKey = config.debugKey;
    if (enabled && debugKey && req.header("Vigil-Key") === debugKey) {
      res.setHeader(
        "Vigil-Debug",
        encodeDebugPayload(
          {
            error: error instanceof Error ? error.message : String(error),
            stack: error instanceof Error ? error.stack : undefined,
            context: {
              method: req.method,
              path: req.path,
              traceparent: req.vigil?.traceparent,
            },
          },
          {
            maxBytes: config.headerLimitBytes ?? 8192,
            maskFields: config.maskBodyFields ?? [],
          },
        ),
      );
    }

    if (config.passThroughErrors) {
      next(error);
      return;
    }

    res.status((typeof error.status === "number" && error.status) || 500).json({
      error: "Internal Server Error",
      traceparent: req.vigil?.traceparent,
    });
  };
}

export function vigilIngestHandler(config: VigilIngestConfig = {}): RequestHandler {
  return async (req, res, next) => {
    try {
      if (!isEnabled(config)) {
        res.sendStatus(404);
        return;
      }

      if (config.ingestKey && req.header("Vigil-Ingest-Key") !== config.ingestKey) {
        res.status(403).json({ error: "Vigil ingest denied" });
        return;
      }

      const batch = parseIngestBatch(req.body);
      if (!batch) {
        res.status(400).json({ error: "Invalid Vigil ingest payload" });
        return;
      }

      const maxBatchCalls = config.maxBatchCalls ?? 100;
      if (batch.calls.length > maxBatchCalls) {
        res.status(413).json({
          error: "Vigil ingest batch too large",
          maxBatchCalls,
        });
        return;
      }

      await config.onBatch?.(batch, req);
      res.status(202).json({ accepted: batch.calls.length });
    } catch (error) {
      next(error);
    }
  };
}

export function createMemoryVigilSink(maxBatches = 100, maxCalls = 1000): VigilMemorySink {
  const batches: VigilIngestBatch[] = [];
  const calls: VigilIngestCall[] = [];

  return {
    batches,
    calls,
    onBatch(batch: VigilIngestBatch) {
      batches.push(batch);
      calls.push(...batch.calls);
      while (batches.length > maxBatches) batches.shift();
      while (calls.length > maxCalls) calls.shift();
    },
    clear() {
      batches.length = 0;
      calls.length = 0;
    },
  };
}

function isEnabled(config: VigilExpressConfig): boolean {
  return config.enabled ?? process.env.NODE_ENV !== "production";
}

function parseIngestBatch(value: unknown): VigilIngestBatch | null {
  if (!value || typeof value !== "object") return null;
  const body = value as Record<string, unknown>;
  if (body.version !== 1) return null;
  if (!Array.isArray(body.calls)) return null;

  const calls = body.calls.filter(
    (call): call is VigilIngestCall => !!call && typeof call === "object" && !Array.isArray(call),
  );
  if (calls.length !== body.calls.length) return null;

  return {
    version: 1,
    sentAt: typeof body.sentAt === "string" ? body.sentAt : undefined,
    client: isPlainObject(body.client) ? body.client : undefined,
    calls,
  };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function createNoopContext(traceparent = ""): VigilRequestContext {
  return {
    traceparent,
    timings: [],
    async time<T>(_name: string, _description: string, fn: () => Promise<T> | T): Promise<T> {
      return await fn();
    },
  };
}

function patchWriteHead(res: Response, beforeWrite: () => void): void {
  const original = res.writeHead.bind(res);
  let patched = false;
  res.writeHead = ((...args: Parameters<Response["writeHead"]>) => {
    if (!patched) {
      patched = true;
      beforeWrite();
    }
    return original(...args);
  }) as Response["writeHead"];
}
