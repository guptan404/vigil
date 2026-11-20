import type { VigilIngestCall, VigilMemorySink } from "./index.js";

export function isVigilSessionId(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value);
}

export interface VigilDesktopCapture {
  client?: Record<string, unknown>;
  sentAt?: string;
  call: VigilIngestCall;
}

export interface VigilDesktopSession {
  sessionId: string;
  deviceType: string;
  deviceName?: string;
  app?: string;
  startedAt?: string;
  lastSeenAt?: string;
  requestCount: number;
  failedCount: number;
}

/** Latest retained lifecycle for each request, newest uploads first. */
export function desktopCaptures(sink: VigilMemorySink): VigilDesktopCapture[] {
  const retained = new Set(sink.calls);
  const seen = new Set<string>();
  const result: VigilDesktopCapture[] = [];
  for (const batch of sink.batches.slice().reverse()) {
    for (const call of batch.calls.slice().reverse()) {
      if (!retained.has(call)) continue;
      const id = JSON.stringify([batch.client?.sessionId ?? null, call.id, call.startedAt]);
      if (typeof call.id === "string" && seen.has(id)) continue;
      seen.add(id);
      result.push({ client: batch.client, sentAt: batch.sentAt, call });
    }
  }
  return result;
}

export function desktopSessions(captures: readonly VigilDesktopCapture[]): VigilDesktopSession[] {
  const sessions = new Map<string, VigilDesktopSession>();
  for (const { client, sentAt, call } of captures) {
    const sessionId = client?.sessionId;
    if (!isVigilSessionId(sessionId)) continue;
    let session = sessions.get(sessionId);
    const startedAt = dateText(client?.sessionStartedAt) ?? dateText(call.startedAt);
    const lastSeenAt = dateText(sentAt) ?? dateText(call.completedAt) ?? dateText(call.startedAt);
    if (!session) {
      session = {
        sessionId,
        deviceType: shortText(client?.deviceType, 64) ?? "unknown",
        deviceName: shortText(client?.deviceName, 128),
        app: shortText(client?.app, 128),
        startedAt, lastSeenAt, requestCount: 0, failedCount: 0,
      };
      sessions.set(sessionId, session);
    }
    session.requestCount++;
    const response = call.response as { statusCode?: number } | undefined;
    if (call.state === "failed" || (response?.statusCode ?? 0) >= 400) session.failedCount++;
    if (startedAt && (!session.startedAt || startedAt < session.startedAt)) session.startedAt = startedAt;
    if (lastSeenAt && (!session.lastSeenAt || lastSeenAt > session.lastSeenAt)) session.lastSeenAt = lastSeenAt;
  }
  return [...sessions.values()].sort((a, b) => (b.lastSeenAt ?? "").localeCompare(a.lastSeenAt ?? ""));
}

function shortText(value: unknown, max: number): string | undefined {
  return typeof value === "string" && value.length > 0 ? value.slice(0, max) : undefined;
}

function dateText(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
}
