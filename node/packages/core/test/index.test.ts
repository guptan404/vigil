import { describe, expect, it } from "vitest";
import {
  encodeDebugPayload,
  generateTraceparent,
  parseTraceparent,
  serializeServerTiming,
} from "../src/index.js";

describe("@vigiljs/core", () => {
  it("generates and parses traceparent", () => {
    const traceparent = generateTraceparent();
    expect(parseTraceparent(traceparent)?.traceId).toHaveLength(32);
  });

  it("serializes safe Server-Timing metrics", () => {
    const header = serializeServerTiming([
      { name: "db", duration: 4.2345, description: 'Fetch "user"' },
    ]);
    expect(header).toBe('db;dur=4.235;desc="Fetch _user_"');
  });

  it("masks and encodes debug payloads", () => {
    const encoded = encodeDebugPayload(
      { error: "boom", context: { password: "secret" } },
      { maskFields: ["password"] },
    );
    const decoded = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
    expect(decoded.context.password).toBe("[redacted]");
  });

  it("keeps truncated debug payloads masked and within the header limit", () => {
    const encoded = encodeDebugPayload(
      { error: "private".repeat(1000), stack: "trace".repeat(1000) },
      { maxBytes: 100, maskFields: ["error"] },
    );
    const decoded = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
    expect(Buffer.byteLength(encoded)).toBeLessThanOrEqual(100);
    expect(decoded.error).toBe("[redacted]");
    expect(decoded.truncated).toBe(true);
    expect(encodeDebugPayload({ error: "boom" }, { maxBytes: 1 })).toBe("");
  });
});
