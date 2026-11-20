import express from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";
import {
  createMemoryVigilSink,
  VigilFailureSimulation,
  vigilErrorHandler,
  vigilInspectorRouter,
  vigilMiddleware,
} from "../src/index.js";

function setup(enabled = true) {
  const simulation = new VigilFailureSimulation({
    enabled,
    debugKey: "dev",
    controlKey: "control",
    allowedPaths: ["/orders"],
  });
  const app = express();
  app.use("/inspect", vigilInspectorRouter({
    enabled: true, readKey: "read", sink: createMemoryVigilSink(), simulation,
  }));
  app.use(vigilMiddleware({ enabled: true, debugKey: "dev" }));
  app.use(simulation.middleware());
  app.get("/orders", (_req, res) => res.json({ orders: [] }));
  app.use(vigilErrorHandler({ enabled: true, debugKey: "dev", passThroughErrors: true }));
  app.use((error: Error & { status?: number }, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    res.status(error.status ?? 500).json({ message: error.message });
  });
  return { app, simulation };
}

describe("Express failure simulation", () => {
  it("returns real keyed HTTP errors with trace, timing and request logs", async () => {
    const { app, simulation } = setup();
    simulation.put({
      method: "GET", path: "/orders", effect: "httpError",
      statusCode: 429, body: { error: "Rate limited" }, times: 1,
    });
    const normal = await request(app).get("/orders");
    expect(normal.status).toBe(200);
    expect(simulation.list()[0].remaining).toBe(1);

    const failed = await request(app).get("/orders").set("Vigil-Key", "dev");
    expect(failed.status).toBe(429);
    expect(failed.body).toEqual({ error: "Rate limited" });
    expect(failed.headers["vigil-simulation"]).toBe("httpError");
    expect(failed.headers.traceparent).toBeTruthy();
    expect(failed.headers["server-timing"]).toContain("total");
    const debug = JSON.parse(Buffer.from(failed.headers["vigil-debug"], "base64url").toString());
    expect(debug.context.logs[0].fields.effect).toBe("httpError");
    expect(simulation.list()).toEqual([]);
    expect((await request(app).get("/orders").set("Vigil-Key", "dev")).status).toBe(200);
  });

  it("uses the application's real error handler for backend exceptions", async () => {
    const { app, simulation } = setup();
    simulation.put({ method: "GET", path: "/orders", effect: "exception", statusCode: 503 });
    const response = await request(app).get("/orders").set("Vigil-Key", "dev");
    expect(response.status).toBe(503);
    expect(response.body.message).toBe("Vigil simulated backend exception");
    const debug = JSON.parse(Buffer.from(response.headers["vigil-debug"], "base64url").toString());
    expect(debug.stack).toContain("Vigil simulated backend exception");
  });

  it("consumes one-shot rules before concurrent delayed requests", async () => {
    const { app, simulation } = setup();
    simulation.put({ method: "GET", path: "/orders", effect: "httpError", delayMs: 30, times: 1 });
    const responses = await Promise.all([
      request(app).get("/orders").set("Vigil-Key", "dev"),
      request(app).get("/orders").set("Vigil-Key", "dev"),
    ]);
    expect(responses.map(response => response.status).sort()).toEqual([200, 500]);
    expect(simulation.list()).toHaveLength(0);
  });

  it("delays before forwarding to the real application route", async () => {
    const { app, simulation } = setup();
    simulation.put({ method: "GET", path: "/orders", effect: "delay", delayMs: 40 });
    const started = performance.now();
    const response = await request(app).get("/orders").set("Vigil-Key", "dev");
    expect(response.body).toEqual({ orders: [] });
    expect(performance.now() - started).toBeGreaterThanOrEqual(35);
    expect(response.headers["vigil-simulation"]).toBe("delay");
  });

  it("drops a real connection and induces a client receive timeout", async () => {
    const { app, simulation } = setup();
    simulation.put({ method: "GET", path: "/orders", effect: "disconnect" });
    await expect(request(app).get("/orders").set("Vigil-Key", "dev"))
      .rejects.toThrow(/socket hang up|aborted|reset/i);

    simulation.put({ method: "GET", path: "/orders", effect: "timeout", delayMs: 5000 });
    await expect(request(app).get("/orders").set("Vigil-Key", "dev").timeout({ response: 50 }))
      .rejects.toMatchObject({ timeout: 50 });
    simulation.clear();
  });

  it("requires a separate control key and validates before replacing rules", async () => {
    const { app, simulation } = setup();
    const rule = { method: "GET", path: "/orders", effect: "httpError", statusCode: 503, sessionId: "phone-a" };
    for (const key of ["", "read", "dev"]) {
      expect((await request(app).post("/inspect/simulation")
        .set("Vigil-Control-Key", key).send(rule)).status).toBe(403);
    }
    const enabled = await request(app).post("/inspect/simulation")
      .set("Vigil-Control-Key", "control").send(rule);
    expect(enabled.status).toBe(201);
    for (const invalid of [
      { ...rule, path: "/vigil/ingest" },
      { ...rule, statusCode: 999 },
      { ...rule, delayMs: -1 },
      { ...rule, times: 0 },
      { ...rule, effect: "unknown" },
    ]) {
      expect((await request(app).post("/inspect/simulation")
        .set("Vigil-Control-Key", "control").send(invalid)).status).toBe(400);
      expect(simulation.list()[0].id).toBe(enabled.body.id);
    }
    expect((await request(app).get("/inspect/simulation")).status).toBe(403);
    const state = await request(app).get("/inspect/simulation?sessionId=phone-a").set("Vigil-Read-Key", "read");
    expect(state.body.rules).toHaveLength(1);
    expect(state.body.allowedPaths).toEqual(["/orders"]);

    expect((await request(app).delete("/inspect/simulation/" + enabled.body.id + "?sessionId=phone-a")
      .set("Vigil-Control-Key", "read")).status).toBe(403);
    expect((await request(app).delete("/inspect/simulation/" + enabled.body.id + "?sessionId=phone-a")
      .set("Vigil-Control-Key", "control")).status).toBe(204);
    expect((await request(app).get("/orders").set("Vigil-Key", "dev")).status).toBe(200);
  });

  it("keeps disabled simulation inactive and its controls inaccessible", async () => {
    const { app, simulation } = setup(false);
    expect(() => simulation.put({ method: "GET", path: "/orders", effect: "disconnect" })).toThrow();
    expect((await request(app).get("/orders").set("Vigil-Key", "dev")).status).toBe(200);
    expect((await request(app).post("/inspect/simulation").set("Vigil-Control-Key", "control")
      .send({ method: "GET", path: "/orders", effect: "disconnect" })).status).toBe(404);
  });
});

describe("Code failure points", () => {
  class StoreUnavailableError extends Error {}

  function codeApp(enabled = true) {
    const simulation = new VigilFailureSimulation({
      enabled, debugKey: "dev", controlKey: "control",
      allowedPaths: ["/users"],
      failurePoints: {
        "users.lookup": () => new StoreUnavailableError("Database unavailable"),
        "users.uncaught": () => new Error("Unexpected database failure"),
      },
    });
    const app = express();
    app.use(vigilMiddleware({ enabled: true, debugKey: "dev", simulation }));
    app.use(simulation.middleware());
    app.get("/users", async (req, res, next) => {
      try {
        await req.vigil.time("db", "Load user", async () => {
          req.vigil.failPoint("users.lookup");
        });
        req.vigil.failPoint("users.uncaught");
        res.json({ user: 1 });
      } catch (error) {
        if (error instanceof StoreUnavailableError) {
          res.status(503).json({ code: "USERS_UNAVAILABLE", retryable: true });
          return;
        }
        next(error);
      }
    });
    app.use(vigilErrorHandler({ enabled: true, debugKey: "dev", passThroughErrors: true }));
    app.use((error: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
      res.status(502).json({ code: "HANDLER_ERROR", detail: error.message });
    });
    return { app, simulation };
  }

  it("lets the route catch its real error type and create its own response", async () => {
    const { app, simulation } = codeApp();
    simulation.put({
      method: "GET", path: "/users", failurePoint: "users.lookup", effect: "exception", times: 1,
    });
    expect((await request(app).get("/users")).body).toEqual({ user: 1 });
    expect(simulation.list()).toHaveLength(1);
    const response = await request(app).get("/users").set("Vigil-Key", "dev");
    expect(response.status).toBe(503);
    expect(response.body).toEqual({ code: "USERS_UNAVAILABLE", retryable: true });
    expect(response.headers["server-timing"]).toContain("db");
    const debug = JSON.parse(Buffer.from(response.headers["vigil-debug"], "base64url").toString());
    expect(debug.context.logs[0].fields.failurePoint).toBe("users.lookup");
    expect((await request(app).get("/users").set("Vigil-Key", "dev")).body).toEqual({ user: 1 });
  });

  it("lets unhandled code errors reach the app's error response formatter", async () => {
    const { app, simulation } = codeApp();
    simulation.put({
      method: "GET", path: "/users", failurePoint: "users.uncaught", effect: "exception",
    });
    const response = await request(app).get("/users").set("Vigil-Key", "dev");
    expect(response.status).toBe(502);
    expect(response.body).toEqual({ code: "HANDLER_ERROR", detail: "Unexpected database failure" });
  });

  it("keeps different failure points independent and consumes them only when reached", async () => {
    const { app, simulation } = codeApp();
    for (const failurePoint of ["users.lookup", "users.uncaught"]) {
      simulation.put({ method: "GET", path: "/users", failurePoint, effect: "exception", times: 1 });
    }
    expect((await request(app).get("/users").set("Vigil-Key", "dev")).status).toBe(503);
    expect(simulation.list().map(rule => rule.failurePoint)).toEqual(["users.uncaught"]);
    expect((await request(app).get("/users").set("Vigil-Key", "dev")).status).toBe(502);
    expect(simulation.list()).toHaveLength(0);
  });

  it("rejects unknown points and response overrides, and allows disabled code to run", async () => {
    const { simulation } = codeApp();
    const rule = { method: "GET", path: "/users", failurePoint: "users.lookup", effect: "exception" as const };
    for (const invalid of [
      { ...rule, failurePoint: "unregistered" },
      { ...rule, body: {} },
      { ...rule, statusCode: 400 },
      { ...rule, effect: "httpError" as const },
    ]) {
      expect(() => simulation.put(invalid)).toThrow();
    }
    const disabled = codeApp(false);
    expect((await request(disabled.app).get("/users").set("Vigil-Key", "dev")).body).toEqual({ user: 1 });
  });
});
