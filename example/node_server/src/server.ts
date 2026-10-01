import express from "express";
import {
  createMemoryVigilSink,
  vigilErrorHandler,
  vigilIngestHandler,
  vigilMiddleware,
} from "@vigiljs/express";

const app = express();
const port = Number(process.env.PORT ?? 4010);
const ingestSink = createMemoryVigilSink();

app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "content-type,traceparent,Vigil-Key,Vigil-Ingest-Key");
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
  enabled: process.env.NODE_ENV !== "production",
  debugKey: "dev-vigil",
  maskBodyFields: ["password", "token"],
}));

app.get("/ok", async (req, res) => {
  const user = await req.vigil.time("db", "Fetch user", async () => {
    await delay(35);
    return { id: 1, email: "demo@example.com" };
  });
  res.json({ ok: true, user });
});

app.get("/slow", async (req, res) => {
  await req.vigil.time("cache", "Read cache", () => delay(20));
  await req.vigil.time("db", "Fetch report", () => delay(120));
  res.json({ ok: true, slow: true });
});

app.get("/error", async (req, _res) => {
  await req.vigil.time("db", "Load missing record", () => delay(25));
  throw new Error("Demo backend failure");
});

app.use(vigilErrorHandler({
  enabled: process.env.NODE_ENV !== "production",
  debugKey: "dev-vigil",
  maskBodyFields: ["password", "token"],
}));

app.listen(port, () => {
  console.log(`Vigil example server listening on http://localhost:${port}`);
});

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
