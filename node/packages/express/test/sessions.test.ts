import express from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";
import {
  createMemoryVigilSink, vigilIngestHandler, vigilInspectorRouter,
  vigilMiddleware, VigilFailureSimulation,
} from "../src/index.js";

function setup() {
  const app = express();
  const sink = createMemoryVigilSink();
  const simulation = new VigilFailureSimulation({
    enabled: true, debugKey: "debug", controlKey: "control", allowedPaths: ["/orders"],
  });
  app.use(express.json());
  app.post("/ingest", vigilIngestHandler({ enabled: true, ingestKey: "ingest", onBatch: sink.onBatch }));
  app.use("/inspect", vigilInspectorRouter({ enabled: true, sink, readKey: "read", simulation }));
  app.use(vigilMiddleware({ enabled: true, debugKey: "debug" }));
  app.use(simulation.middleware());
  app.get("/orders", (_req, res) => res.json({ orders: [] }));
  return { app, simulation, sink };
}

describe("Device sessions", () => {
  it("mocks a successful response only for a captured path in the selected session", async () => {
    const app = express();
    const sink = createMemoryVigilSink();
    const simulation = new VigilFailureSimulation({
      enabled: true, debugKey: "debug", controlKey: "control", allowedPaths: [], allowCapturedPaths: true,
    });
    app.use(express.json());
    app.post("/ingest", vigilIngestHandler({ enabled: true, ingestKey: "ingest", onBatch: sink.onBatch }));
    app.use("/inspect", vigilInspectorRouter({ enabled: true, sink, readKey: "read", simulation }));
    app.use(simulation.middleware());
    app.get("/profile", (_req, res) => res.json({ source: "real" }));
    await request(app).post("/ingest").set("Vigil-Ingest-Key", "ingest").send({
      version: 1, client: { sessionId: "phone-a" },
      calls: [{ id: "call", request: { method: "GET", url: "https://api.example/profile" } }],
    }).expect(202);
    const rule = { sessionId: "phone-a", method: "GET", path: "/profile", effect: "mock", times: 1, body: { source: "mock" } };
    await request(app).post("/inspect/simulation").set("Vigil-Control-Key", "control")
      .send({ ...rule, sessionId: "phone-b" }).expect(400);
    await request(app).post("/inspect/simulation").set("Vigil-Control-Key", "control")
      .send({ ...rule, path: "/not-captured" }).expect(400);
    await request(app).post("/inspect/simulation").set("Vigil-Control-Key", "control")
      .send({ ...rule, method: "POST" }).expect(400);
    await request(app).post("/inspect/simulation").set("Vigil-Control-Key", "control").send(rule).expect(201);
    expect((await request(app).get("/profile").set("Vigil-Session-Id", "phone-a")).body).toEqual({ source: "real" });
    expect((await request(app).get("/profile").set("Vigil-Key", "debug").set("Vigil-Session-Id", "phone-b")).body).toEqual({ source: "real" });
    const mocked = await request(app).get("/profile").set("Vigil-Key", "debug").set("Vigil-Session-Id", "phone-a");
    expect(mocked.status).toBe(200);
    expect(mocked.body).toEqual({ source: "mock" });
    expect(mocked.headers["vigil-simulation"]).toBe("mock");
    expect((await request(app).get("/profile").set("Vigil-Key", "debug").set("Vigil-Session-Id", "phone-a")).body).toEqual({ source: "real" });
  });

  it("escapes app branding and embeds the logo as an inert image", async () => {
    const app = express();
    const logo = '<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0h10v10z"/></svg>';
    app.use("/inspect", vigilInspectorRouter({ enabled: true, sink: createMemoryVigilSink(), readKey: "read",
      branding: { name: '<img src=x onerror="alert(1)">', logoSvg: logo } }));
    const response = await request(app).get("/inspect/");
    expect(response.text).not.toContain('<img src=x');
    expect(response.text).toContain('&lt;img src=x onerror=&quot;alert(1)&quot;&gt;');
    expect(response.text).toContain(Buffer.from(logo).toString("base64"));
    expect(response.headers["content-security-policy"]).toContain("img-src data:");
  });

  it("requires an exact device identity when session controls do not require the debug header", async () => {
    const app = express();
    const simulation = new VigilFailureSimulation({
      enabled: true, debugKey: "debug", controlKey: "control", allowedPaths: ["/profile"], requireDebugKey: false,
    });
    expect(() => simulation.put({ method: "GET", path: "/profile", effect: "mock" })).toThrow(/session ID/);
    simulation.put({ sessionId: "phone-a", method: "GET", path: "/profile", effect: "mock", body: { mocked: true } });
    app.use(simulation.middleware());
    app.get("/profile", (_req, res) => res.json({ mocked: false }));
    expect((await request(app).get("/profile")).body).toEqual({ mocked: false });
    expect((await request(app).get("/profile").set("Vigil-Session-Id", "phone-b")).body).toEqual({ mocked: false });
    expect((await request(app).get("/profile").set("Vigil-Session-Id", "phone-a")).body).toEqual({ mocked: true });
  });

  it("groups by session ID and serves only the selected session's latest requests", async () => {
    const { app } = setup();
    for (const [sessionId, deviceType, state] of [
      ["phone-a", "android", "pending"],
      ["phone-b", "ios", "completed"],
      ["phone-a", "android", "failed"],
    ]) {
      await request(app).post("/ingest").set("Vigil-Ingest-Key", "ingest").send({
        version: 1, sentAt: "2026-11-19T10:00:01Z",
        client: { sessionId, deviceType, deviceName: "Same device name", app: "demo" },
        calls: [{
          id: "shared-call-id", startedAt: "2026-11-19T10:00:00Z", state,
          response: state === "pending" ? null : { statusCode: state === "failed" ? 503 : 200 },
        }],
      }).expect(202);
    }
    await request(app).get("/inspect/sessions").expect(403);
    const overview = await request(app).get("/inspect/sessions").set("Vigil-Read-Key", "read");
    expect(overview.body.sessions).toHaveLength(2);
    expect(overview.body.sessions.find((item: {sessionId: string}) => item.sessionId === "phone-a"))
      .toMatchObject({ deviceType: "android", requestCount: 1, failedCount: 1 });
    const all = await request(app).get("/inspect/captures").set("Vigil-Read-Key", "read");
    expect(all.body.captures).toEqual([]);
    for (const sessionId of ["phone-a", "phone-b"]) {
      const captures = await request(app).get("/inspect/captures")
        .query({ sessionId }).set("Vigil-Read-Key", "read");
      expect(captures.body.captures).toHaveLength(1);
      expect(captures.body.captures[0].client.sessionId).toBe(sessionId);
      expect(captures.body.captures[0].call.state).toBe(sessionId === "phone-a" ? "failed" : "completed");
    }
  });

  it("applies and consumes a desktop failure rule only for its selected device", async () => {
    const { app, simulation } = setup();
    const rule = { method: "GET", path: "/orders", effect: "httpError", statusCode: 503, times: 1 };
    await request(app).post("/inspect/simulation").set("Vigil-Control-Key", "control")
      .send(rule).expect(400);
    await request(app).post("/inspect/simulation").set("Vigil-Control-Key", "control")
      .send({ ...rule, sessionId: "phone-a" }).expect(201);
    await request(app).get("/orders").set("Vigil-Key", "debug").set("Vigil-Session-Id", "phone-b").expect(200);
    await request(app).get("/orders").set("Vigil-Key", "debug").expect(200);
    expect(simulation.list()[0].remaining).toBe(1);
    await request(app).get("/orders").set("Vigil-Key", "debug").set("Vigil-Session-Id", "phone-a").expect(503);
    await request(app).get("/orders").set("Vigil-Key", "debug").set("Vigil-Session-Id", "phone-a").expect(200);
    expect(simulation.list()).toHaveLength(0);
  });

  it("keeps rules for the same path on different sessions independent", async () => {
    const { app, simulation } = setup();
    for (const sessionId of ["phone-a", "phone-b"]) {
      await request(app).post("/inspect/simulation").set("Vigil-Control-Key", "control")
        .send({ sessionId, method: "GET", path: "/orders", effect: "httpError" }).expect(201);
    }
    const first = simulation.list()[0];
    await request(app).delete("/inspect/simulation/" + first.id)
      .query({ sessionId: "phone-b" }).set("Vigil-Control-Key", "control").expect(404);
    await request(app).delete("/inspect/simulation").set("Vigil-Control-Key", "control").expect(400);
    await request(app).delete("/inspect/simulation").query({ sessionId: "phone-a" })
      .set("Vigil-Control-Key", "control").expect(204);
    expect(simulation.list().map(rule => rule.sessionId)).toEqual(["phone-b"]);
  });

  it("scopes named code failures to the session reaching the failure point", async () => {
    const simulation = new VigilFailureSimulation({
      enabled: true, debugKey: "debug", controlKey: "control",
      allowedPaths: ["/users"], failurePoints: { "users.lookup": () => new Error("Session failure") },
    });
    simulation.put({ method: "GET", path: "/users", failurePoint: "users.lookup",
      effect: "exception", sessionId: "phone-a", times: 1 });
    const app = express();
    app.use(vigilMiddleware({ enabled: true, debugKey: "debug", simulation }));
    app.get("/users", (req, res) => {
      try {
        req.vigil.failPoint("users.lookup");
        res.json({ ok: true });
      } catch {
        res.status(503).json({ code: "USER_LOOKUP_FAILED" });
      }
    });
    await request(app).get("/users").set("Vigil-Key", "debug").set("Vigil-Session-Id", "phone-b").expect(200);
    await request(app).get("/users").set("Vigil-Key", "debug").set("Vigil-Session-Id", "phone-a").expect(503);
    await request(app).get("/users").set("Vigil-Key", "debug").set("Vigil-Session-Id", "phone-a").expect(200);
  });
});
