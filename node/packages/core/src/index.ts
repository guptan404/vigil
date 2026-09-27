import { randomBytes } from "node:crypto";

export interface TraceContext {
  version: string;
  traceId: string;
  parentId: string;
  flags: string;
}

export interface ServerTimingMetric {
  name: string;
  duration?: number;
  description?: string;
}

export interface VigilDebugPayload {
  error?: string;
  stack?: string;
  context?: Record<string, unknown>;
  truncated?: boolean;
}

export interface DebugEncodeOptions {
  maxBytes?: number;
  maskFields?: string[];
}

export function generateTraceparent(): string {
  return `00-${randomBytes(16).toString("hex")}-${randomBytes(8).toString("hex")}-01`;
}

export function parseTraceparent(header: string | undefined): TraceContext | null {
  if (!header) return null;
  const parts = header.trim().split("-");
  if (parts.length !== 4) return null;
  const [version, traceId, parentId, flags] = parts;
  const hex = /^[0-9a-f]+$/;
  if (
    version.length !== 2 ||
    traceId.length !== 32 ||
    parentId.length !== 16 ||
    flags.length !== 2 ||
    !hex.test(`${version}${traceId}${parentId}${flags}`) ||
    traceId === "00000000000000000000000000000000" ||
    parentId === "0000000000000000"
  ) {
    return null;
  }
  return { version, traceId, parentId, flags };
}

export function serializeServerTiming(
  metrics: ServerTimingMetric[],
  maxBytes = 4096,
): string {
  const parts: string[] = [];
  for (const metric of metrics) {
    const name = sanitizeMetricName(metric.name);
    if (!name) continue;
    let value = name;
    if (typeof metric.duration === "number" && Number.isFinite(metric.duration)) {
      value += `;dur=${Math.max(0, Math.round(metric.duration * 1000) / 1000)}`;
    }
    if (metric.description) {
      value += `;desc="${escapeDescription(metric.description).slice(0, 120)}"`;
    }
    const next = [...parts, value].join(", ");
    if (Buffer.byteLength(next, "utf8") > maxBytes) break;
    parts.push(value);
  }
  return parts.join(", ");
}

export function encodeDebugPayload(
  payload: VigilDebugPayload,
  options: DebugEncodeOptions = {},
): string {
  const maxBytes = options.maxBytes ?? 8192;
  const masked = maskObject(payload, new Set((options.maskFields ?? []).map((field) => field.toLowerCase())));
  let candidate = encode(masked);
  if (Buffer.byteLength(candidate, "utf8") <= maxBytes) return candidate;

  const trimmed: VigilDebugPayload = {
    error: payload.error?.slice(0, 500),
    stack: payload.stack?.slice(0, 1500),
    context: undefined,
    truncated: true,
  };
  candidate = encode(trimmed);
  while (Buffer.byteLength(candidate, "utf8") > maxBytes && trimmed.stack && trimmed.stack.length > 200) {
    trimmed.stack = trimmed.stack.slice(0, Math.floor(trimmed.stack.length * 0.7));
    candidate = encode(trimmed);
  }
  return candidate;
}

export function maskObject(value: unknown, fields: Set<string>): unknown {
  if (Array.isArray(value)) return value.map((item) => maskObject(item, fields));
  if (!value || typeof value !== "object") return value;
  const result: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value)) {
    result[key] = fields.has(key.toLowerCase()) ? "[redacted]" : maskObject(child, fields);
  }
  return result;
}

function encode(value: unknown): string {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}

function sanitizeMetricName(name: string): string {
  return name.trim().replace(/[^a-zA-Z0-9_.:-]/g, "_").slice(0, 64);
}

function escapeDescription(description: string): string {
  return description.replace(/["\\]/g, "_").replace(/[\r\n]/g, " ");
}

