import type { VigilFailureSimulation } from "./simulation.js";
import type { ErrorRequestHandler, NextFunction, Request, RequestHandler, Response } from "express";
import {
  encodeDebugPayload,
  generateTraceparent,
  maskObject,
  parseTraceparent,
  serializeServerTiming,
  type ServerTimingMetric,
  type VigilDebugPayload,
  type DebugEncodeOptions,
} from "@vigiljs/core";

/** Configuration shared by Vigil request and error middleware. */
export interface VigilExpressConfig {
  enabled?: boolean;
  includeTotalTiming?: boolean;
  passThroughErrors?: boolean;
  debugKey?: string;
  maskHeaders?: string[];
  maskBodyFields?: string[];
  headerLimitBytes?: number;
  /** Optional code-level failure points for development. */
  simulation?: VigilFailureSimulation;
}

/** Configuration for the optional client-call ingest route. */
export interface VigilIngestConfig {
  enabled?: boolean;
  ingestKey?: string;
  maxBatchCalls?: number;
  onBatch?: (batch: VigilIngestBatch, req: Request) => Promise<void> | void;
}

/** Version 1 batch accepted by the Vigil ingest handler. */
export interface VigilIngestBatch {
  version: number;
  sentAt?: string;
  client?: Record<string, unknown>;
  calls: VigilIngestCall[];
}

/** Serialized client call retained by an ingest destination. */
export type VigilIngestCall = Record<string, unknown>;

/** Bounded in-memory ingest destination for development and tests. */
export interface VigilMemorySink {
  batches: VigilIngestBatch[];
  calls: VigilIngestCall[];
  onBatch(batch: VigilIngestBatch): void;
  clear(): void;
}

export interface VigilRequestLog {
  timestamp: string;
  level: "debug" | "info" | "warn" | "error";
  message: string;
  fields?: Record<string, unknown>;
}

/** Per-request trace and timing API attached to Express requests. */
export interface VigilRequestContext {
  /** Adds an explicit request-scoped log entry for an authorized debug response. */
  log(level: "debug" | "info" | "warn" | "error", message: string, fields?: Record<string, unknown>): void;
  /** Bounded entries captured before response headers are sent. */
  readonly logs: readonly VigilRequestLog[];
  /** Throws an armed operation error inside the current application call stack. */
  failPoint(name: string): void;
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

/**
 * Adds trace correlation and `Server-Timing` response headers.
 *
 * Mount this middleware before application routes.
 */
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
    const logs: VigilRequestLog[] = [];
    const debugAllowed = !!config.debugKey && req.header("Vigil-Key") === config.debugKey;
    const maskedFields = new Set((config.maskBodyFields ?? []).map((name) => name.toLowerCase()));
    const requestStartedAt = process.hrtime.bigint();

    req.vigil = {
      traceparent,
      timings,
      logs,
      failPoint(name) { config.simulation?.failPoint(req, name); },
      log(level, message, fields) {
        if (!debugAllowed || res.headersSent || logs.length >= 20) return;
        const entry: VigilRequestLog = {
          timestamp: new Date().toISOString(), level, message: message.slice(0, 300),
        };
        if (fields) {
          try {
            const candidate = maskObject(fields, maskedFields) as Record<string, unknown>;
            if (Buffer.byteLength(JSON.stringify(candidate)) <= 512) entry.fields = candidate;
          } catch {
            // Logging must not interrupt the application request.
          }
        }
        logs.push(entry);
      },
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

    patchWriteHead(res, (statusCode) => {
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
      if (
        (statusCode >= 400 || logs.length > 0) &&
        debugAllowed &&
        !res.hasHeader("Vigil-Debug")
      ) {
        res.setHeader("Vigil-Debug", encodeRequestDebug({
          error: statusCode >= 400 ? `HTTP ${statusCode}` : undefined,
          context: {
            method: req.method,
            path: req.path,
            statusCode,
            traceparent,
            ...(logs.length > 0 ? { logs } : {}),
          },
        }, {
          maxBytes: config.headerLimitBytes ?? 8192,
          maskFields: config.maskBodyFields ?? [],
        }));
      }
    });

    res.setHeader("traceparent", traceparent);
    next();
  };
}

/**
 * Adds gated `Vigil-Debug` details to error responses.
 *
 * Mount this after routes and before an existing error handler when
 * `passThroughErrors` is enabled.
 */
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
        encodeRequestDebug(
          {
            error: error instanceof Error ? error.message : String(error),
            stack: error instanceof Error ? error.stack : undefined,
            context: {
              method: req.method,
              path: req.path,
              traceparent: req.vigil?.traceparent,
              ...(req.vigil?.logs.length ? { logs: req.vigil.logs } : {}),
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

/** Creates an Express handler for version 1 Vigil client-call batches. */
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

/** Creates a bounded in-memory ingest destination for development and tests. */
export function createMemoryVigilSink(maxBatches = 100, maxCalls = 1000): VigilMemorySink {
  if (!Number.isInteger(maxBatches) || maxBatches <= 0) {
    throw new RangeError("maxBatches must be a positive integer");
  }
  if (!Number.isInteger(maxCalls) || maxCalls <= 0) {
    throw new RangeError("maxCalls must be a positive integer");
  }

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

function encodeRequestDebug(payload: VigilDebugPayload, options: DebugEncodeOptions): string {
  const logs = payload.context?.logs;
  if (!Array.isArray(logs) || logs.length === 0) return encodeDebugPayload(payload, options);
  for (let count = logs.length; count > 0; count--) {
    const encoded = encodeDebugPayload({
      ...payload,
      context: { ...payload.context, logs: logs.slice(0, count) },
      truncated: count < logs.length,
    }, options);
    if (encoded && JSON.parse(Buffer.from(encoded, "base64url").toString()).context) {
      return encoded;
    }
  }
  const { logs: _logs, ...context } = payload.context!;
  return encodeDebugPayload({ ...payload, context, truncated: true }, options);
}

export { vigilInspectorRouter, type VigilInspectorConfig } from "./inspector.js";

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
    logs: [],
    failPoint() {},
    log() {},
    async time<T>(_name: string, _description: string, fn: () => Promise<T> | T): Promise<T> {
      return await fn();
    },
  };
}

function patchWriteHead(res: Response, beforeWrite: (statusCode: number) => void): void {
  const original = res.writeHead.bind(res);
  let patched = false;
  res.writeHead = ((...args: Parameters<Response["writeHead"]>) => {
    if (!patched) {
      patched = true;
      beforeWrite(args[0]);
    }
    return original(...args);
  }) as Response["writeHead"];
}

export { VigilFailureSimulation, type VigilFailureSimulationConfig, type VigilFailureRule, type VigilFailureRuleInput, type VigilFailureEffect } from "./simulation.js";
