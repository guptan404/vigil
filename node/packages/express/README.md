# @vigiljs/express

Express middleware for correlating Vigil client calls, emitting total and
custom `Server-Timing` metrics, returning gated error diagnostics, and receiving
optional client capture batches.

## Installation

```sh
npm install @vigiljs/express
```

This package is ESM-only, requires Node.js 18 or newer, and supports Express
4.18 through 5.x.

## Request timing

Mount `vigilMiddleware` before application routes:

```ts
import express from "express";
import { vigilMiddleware } from "@vigiljs/express";

const app = express();

app.use(vigilMiddleware({
  enabled: process.env.NODE_ENV !== "production",
  debugKey: process.env.VIGIL_DEBUG_KEY,
}));

app.get("/report", async (req, res) => {
  const report = await req.vigil.time("db", "Load report", loadReport);
  res.json(report);
});
```

When enabled, every response receives a correlated `traceparent` and a total
server duration. `req.vigil.time()` adds named measurements. Set
`includeTotalTiming: false` if only explicit measurements should be emitted.

## Gated error diagnostics

Mount `vigilErrorHandler` after routes. Use `passThroughErrors` if your existing
handler must retain control of status codes and response bodies:

```ts
import { vigilErrorHandler } from "@vigiljs/express";

app.use(vigilErrorHandler({
  enabled: process.env.NODE_ENV !== "production",
  debugKey: process.env.VIGIL_DEBUG_KEY,
  passThroughErrors: true,
  maskBodyFields: ["password", "token", "secret"],
}));

app.use(existingErrorHandler);
```

With a matching `Vigil-Key`, direct 4xx/5xx responses include a status and
trace diagnostic. Errors reaching `vigilErrorHandler` also include the error
message and stack. No debug header is emitted when the incoming key does not
exactly match `debugKey`. Do not enable stack-trace diagnostics on public
production APIs.

## Client-call ingest

The ingest handler accepts JSON batches over HTTP `POST`; it is not a WebSocket
endpoint.

```ts
import { createMemoryVigilSink, vigilIngestHandler } from "@vigiljs/express";

const sink = createMemoryVigilSink();

app.use(express.json());
app.post("/vigil/ingest", vigilIngestHandler({
  enabled: process.env.NODE_ENV !== "production",
  ingestKey: process.env.VIGIL_INGEST_KEY,
  maxBatchCalls: 100,
  onBatch: sink.onBatch,
}));
```

The supplied memory sink is bounded and intended for local development and
tests. Use an access-controlled, retention-aware destination for persistent
storage.

## Browser clients

Flutter Web and browser clients need these response headers exposed by CORS:

```ts
res.setHeader(
  "Access-Control-Expose-Headers",
  "Server-Timing, traceparent, Vigil-Debug",
);
```

If Vigil request headers are sent cross-origin, also allow `traceparent`,
`Vigil-Key`, and `Vigil-Ingest-Key` as appropriate.

## Security

- Disable the integration in production by default.
- Use TLS, restrict CORS, and rate-limit remotely reachable ingest endpoints.
- Treat client-embedded keys as development gates rather than durable secrets.
- Mask fields specific to your application before collecting or storing calls.
