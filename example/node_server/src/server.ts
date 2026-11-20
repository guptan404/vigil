import { fileURLToPath } from "node:url";
import express from "express";
import {
  createMemoryVigilSink,
  vigilErrorHandler,
  vigilIngestHandler,
  vigilInspectorRouter,
  vigilMiddleware,
  VigilFailureSimulation,
} from "@vigiljs/express";

const app = express();
const port = Number(process.env.PORT ?? 4010);
const ingestSink = createMemoryVigilSink();
class UserStoreUnavailableError extends Error {}

const simulation = new VigilFailureSimulation({
  enabled: process.env.NODE_ENV !== "production",
  debugKey: "dev-vigil",
  controlKey: process.env.VIGIL_SIMULATION_KEY ?? "dev-vigil-control",
  allowedPaths: ["/ok", "/slow", "/error"],
  failurePoints: {
    "users.lookup": () => new UserStoreUnavailableError("User store unavailable"),
  },
});

app.use("/vigil/inspector", vigilInspectorRouter({
  sink: ingestSink,
  simulation,
  readKey: process.env.VIGIL_INSPECTOR_KEY ?? "dev-vigil-read",
  enabled: process.env.NODE_ENV !== "production",
}));

if (process.env.VIGIL_WEB_PREVIEW === "true") {
  app.use(express.static(fileURLToPath(new URL("../../flutter_app/build/web/", import.meta.url)), {
    setHeaders: (res) => res.setHeader("Cache-Control", "no-store"),
  }));
}

app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "content-type,traceparent,Vigil-Key,Vigil-Ingest-Key,Vigil-Session-Id,Vigil-Device-Type");
  res.setHeader("Access-Control-Expose-Headers", "Server-Timing,traceparent,Vigil-Debug");
  if (req.method === "OPTIONS") {
    res.sendStatus(204);
    return;
  }
  next();
});

app.use(express.json());
app.post("/vigil/ingest", vigilIngestHandler({
  enabled: process.env.NODE_ENV !== "production",
  ingestKey: "dev-vigil",
  onBatch: (batch) => {
    ingestSink.onBatch(batch);
    console.log(`Vigil ingest accepted ${batch.calls.length} call(s), total=${ingestSink.calls.length}`);
  },
}));

app.use(vigilMiddleware({
  simulation,  enabled: process.env.NODE_ENV !== "production",
  debugKey: "dev-vigil",
  maskBodyFields: ["password", "token"],
}));

app.use(simulation.middleware());

app.get("/ok", async (req, res, next) => {
  try {
    const user = await req.vigil.time("db", "Fetch user", async () => {
      req.vigil.failPoint("users.lookup");
      await delay(35);
      return { id: 1, email: "demo@example.com" };
    });
    req.vigil.log("info", "Loaded demo user", { userId: user.id });
    res.json({ ok: true, user });
  } catch (error) {
    if (error instanceof UserStoreUnavailableError) {
      req.vigil.log("error", "User lookup failed", { code: "USER_STORE_UNAVAILABLE" });
      res.status(503).json({
        error: { code: "USER_STORE_UNAVAILABLE", message: "Please try again later" },
      });
      return;
    }
    next(error);
  }
});

app.get("/slow", async (req, res) => {
  await req.vigil.time("cache", "Read cache", () => delay(20));
  await req.vigil.time("db", "Fetch report", () => delay(120));
  res.json({ ok: true, slow: true });
});

app.get("/error", async (req, _res) => {
  await req.vigil.time("db", "Load missing record", () => delay(25));
  req.vigil.log("warn", "Demo record missing");
  throw new Error("Demo backend failure");
});

app.use(vigilErrorHandler({
  enabled: process.env.NODE_ENV !== "production",
  debugKey: "dev-vigil",
  maskBodyFields: ["password", "token"],
}));

app.listen(port, process.env.VIGIL_WEB_PREVIEW === "true" ? "127.0.0.1" : "::", () => {
  console.log(`Vigil example server listening on http://localhost:${port}`);
});

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
