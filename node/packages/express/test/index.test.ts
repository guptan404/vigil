import express from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";
import {
  createMemoryVigilSink,
  vigilErrorHandler,
  vigilIngestHandler,
  vigilMiddleware,
} from "../src/index.js";

describe("@vigil/express", () => {
  it("emits Server-Timing and traceparent", async () => {
    const app = express();
    app.use(vigilMiddleware({ enabled: true }));
    app.get("/ok", async (req, res) => {
      await req.vigil.time("db", "Fetch", async () => "ok");
      res.json({ ok: true });
    });

    const response = await request(app).get("/ok");

    expect(response.header.traceparent).toBeTruthy();
    expect(response.header["server-timing"]).toContain("db");
  });

  it("emits total server timing without manual route instrumentation", async () => {
    const app = express();
    app.use(vigilMiddleware({ enabled: true }));
    app.get("/ok", (_req, res) => {
      res.json({ ok: true });
    });

    const response = await request(app).get("/ok");

    expect(response.header["server-timing"]).toMatch(
      /total;dur=\d+(?:\.\d+)?;desc="Total server time"/,
    );
  });

  it("gates debug payloads by key", async () => {
    const app = express();
    app.use(vigilMiddleware({ enabled: true }));
    app.get("/error", () => {
      throw new Error("boom");
    });
    app.use(vigilErrorHandler({ enabled: true, debugKey: "dev" }));

    const denied = await request(app).get("/error");
    const allowed = await request(app).get("/error").set("Vigil-Key", "dev");

    expect(denied.header["vigil-debug"]).toBeUndefined();
    expect(allowed.header["vigil-debug"]).toBeTruthy();
  });

  it("can add gated debug data without replacing the app error response", async () => {
    const app = express();
    app.use(vigilMiddleware({ enabled: true }));
    app.get("/error", () => {
      const error = new Error("boom") as Error & { status: number };
      error.status = 422;
      throw error;
    });
    app.use(vigilErrorHandler({
      enabled: true,
      debugKey: "dev",
      passThroughErrors: true,
    }));
    app.use((error: Error & { status?: number }, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
      res.status(error.status ?? 500).json({ message: error.message });
    });

    const response = await request(app).get("/error").set("Vigil-Key", "dev");

    expect(response.status).toBe(422);
    expect(response.body).toEqual({ message: "boom" });
    expect(response.header["vigil-debug"]).toBeTruthy();
  });

  it("keeps instrumented routes working in production no-op mode", async () => {
    const previous = process.env.NODE_ENV;
    process.env.NODE_ENV = "production";
    const app = express();
    app.use(vigilMiddleware());
    app.get("/ok", async (req, res) => {
      const value = await req.vigil.time("db", "No-op timing", () => "ok");
      res.json({ value });
    });

    const response = await request(app).get("/ok");

    expect(response.header.traceparent).toBeUndefined();
    expect(response.header["server-timing"]).toBeUndefined();
    expect(response.body.value).toBe("ok");
    process.env.NODE_ENV = previous;
  });

  it("accepts keyed backend ingest batches", async () => {
    const app = express();
    const sink = createMemoryVigilSink();
    app.use(express.json());
    app.post("/vigil/ingest", vigilIngestHandler({
      enabled: true,
      ingestKey: "collector-key",
      onBatch: sink.onBatch,
    }));

    const denied = await request(app)
      .post("/vigil/ingest")
      .send({ version: 1, calls: [] });
    const allowed = await request(app)
      .post("/vigil/ingest")
      .set("Vigil-Ingest-Key", "collector-key")
      .send({
        version: 1,
        sentAt: new Date().toISOString(),
        client: { app: "demo" },
        calls: [{ id: "call-1", state: "completed" }],
      });

    expect(denied.status).toBe(403);
    expect(allowed.status).toBe(202);
    expect(allowed.body.accepted).toBe(1);
    expect(sink.calls).toHaveLength(1);
    expect(sink.calls[0].id).toBe("call-1");
  });

  it("rejects invalid memory sink limits", () => {
    expect(() => createMemoryVigilSink(0, 100)).toThrow(RangeError);
    expect(() => createMemoryVigilSink(100, -1)).toThrow(RangeError);
  });

  it("rejects invalid and oversized ingest batches", async () => {
    const app = express();
    app.use(express.json());
    app.post("/vigil/ingest", vigilIngestHandler({
      enabled: true,
      maxBatchCalls: 1,
    }));

    const invalid = await request(app).post("/vigil/ingest").send({ calls: [] });
    const oversized = await request(app)
      .post("/vigil/ingest")
      .send({ version: 1, calls: [{ id: "a" }, { id: "b" }] });

    expect(invalid.status).toBe(400);
    expect(oversized.status).toBe(413);
  });

  it("does not expose ingest in disabled mode", async () => {
    const app = express();
    app.use(express.json());
    app.post("/vigil/ingest", vigilIngestHandler({ enabled: false }));

    const response = await request(app)
      .post("/vigil/ingest")
      .send({ version: 1, calls: [] });

    expect(response.status).toBe(404);
  });
});
