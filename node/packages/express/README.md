# @vigiljs/express

Express middleware for correlating Vigil client calls, emitting total and
custom `Server-Timing` metrics, returning gated error diagnostics, and receiving
optional client capture batches.

The companion [`vigil` package on pub.dev](https://pub.dev/packages/vigil)
captures Dio traffic in Flutter and provides the in-app inspector. Developers
can search a call, **Copy cURL** to share a request with backend teammates, or
use **Copy lifecycle** and **Share lifecycle** for JSON containing the request,
response, trace, timing, and failure details. The separate
[`vigil_backend` package](https://pub.dev/packages/vigil_backend), also exported
by `vigil`, uploads captured calls to this package's ingest handler.

## How Flutter and Express communicate

1. The Flutter interceptor sends `traceparent` with the request. This
   middleware returns that trace and `Server-Timing` metrics with the response.
2. For a response with an error or request logs, a matching development
   `Vigil-Key` enables a `Vigil-Debug` header. The Flutter Debug tab can show the backend error
   message, stack trace, and request context alongside the client failure.
3. Optional ingest uses a separate `Vigil-Ingest-Key` and an HTTP JSON batch.
   It is independent of the response diagnostics path.

`Vigil-Debug` contains diagnostics for one response. To attach selected
request logs, call `req.vigil.log("info", "Loaded account", { accountId })`
before sending response headers. Logs are limited in number and size, share
the request trace ID, and appear on successful and failed responses.

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

In Flutter, configure `VigilBackendConnection` from
[`vigil_backend`](https://pub.dev/packages/vigil_backend) with this route as
its `endpoint` and the same ingest key. Upload includes completed and failed
client call summaries; it does not cause this middleware to collect server logs.

## Desktop inspector

Mount `vigilInspectorRouter({ sink, readKey })` at a development route such as
`/vigil/inspector`. Use the same memory sink as ingest and a separate read key.
Open the route in a desktop browser and enter the read key to inspect recent
uploads. Device filters use the app's ingest client metadata.

## Code-level failure points

Register the real error type for an operation, then call
`req.vigil.failPoint(name)` inside that operation. When a matching rule is
enabled, the call throws that error in the application's call stack. The
route's catch block or error middleware creates the response.

```ts
class UserStoreUnavailableError extends Error {}

const simulation = new VigilFailureSimulation({
  debugKey: process.env.VIGIL_DEBUG_KEY!,
  controlKey: process.env.VIGIL_SIMULATION_KEY!,
  allowedPaths: ["/users"],
  failurePoints: {
    "users.lookup": () => new UserStoreUnavailableError("Database unavailable"),
  },
});
app.use(vigilMiddleware({
  debugKey: process.env.VIGIL_DEBUG_KEY,
  simulation,
}));

app.get("/users", async (req, res, next) => {
  try {
    req.vigil.failPoint("users.lookup");
    const users = await loadUsers();
    res.json(users);
  } catch (error) {
    if (error instanceof UserStoreUnavailableError) {
      res.status(503).json({ code: "USERS_UNAVAILABLE", retryable: true });
      return;
    }
    next(error);
  }
});
```

Pass the same simulation to `vigilInspectorRouter`. Under **Express failure
simulation**, choose **users.lookup** as the failure location and enable the
rule. Set a request count of 1 for a one-shot failure. The form uses the
registered error factory, and the route determines the status and body.
A point is consumed only when execution reaches it. Registering several
points lets you exercise different branches within the same endpoint.
Unknown or unarmed points are no-ops, as are calls when simulation is disabled
or the request lacks the matching development key.

For direct configuration, use
`simulation.put({ method: "GET", path: "/users", failurePoint: "users.lookup", effect: "exception", times: 1 })`.
Code-point rules accept the operation name and request count. Status, JSON
body, and delay overrides are rejected. The point throws synchronously and
can be used inside an async function, a transaction, or a try/finally block.

## Server failure simulation

Create a development controller with the exact endpoints you want to exercise.
Mount its middleware after Vigil instrumentation and before application routes.

```ts
import {
  VigilFailureSimulation,
  vigilInspectorRouter,
  vigilMiddleware,
} from "@vigiljs/express";

const simulation = new VigilFailureSimulation({
  debugKey: process.env.VIGIL_DEBUG_KEY!,
  controlKey: process.env.VIGIL_SIMULATION_KEY!,
  allowedPaths: ["/orders", "/checkout"],
});
app.use("/vigil/inspector", vigilInspectorRouter({
  sink,
  readKey: process.env.VIGIL_INSPECTOR_KEY!,
  simulation,
}));
app.use(vigilMiddleware({ debugKey: process.env.VIGIL_DEBUG_KEY }));
app.use(simulation.middleware());
// Mount your routes here, then vigilErrorHandler and your app's error handler.
```

Connect to the desktop inspector with its read key, expand **Express failure
simulation**, and enter the separate simulation control key. Choose a method,
exact path, and failure location, then enable the rule. Choose **Before route**
to configure the HTTP and transport effects below. Rules apply to requests carrying
the matching development `Vigil-Key`. The example Flutter interceptor already
sends that header. Remove any matching Flutter mock rule so the request
reaches Express.

- **HTTP error response** sends a real 4xx/5xx response with a custom JSON body.
- **Backend exception** passes an Error to the application's Express error
  handlers so their normal response formatting and diagnostics run.
- **Delay and forward** waits before entering the application's route.
- **Timeout** holds the connection open for the configured delay, then closes it.
  Configure a shorter client receive timeout to observe a client timeout.
- **Disconnect** closes the actual HTTP connection.

Rules support a request count, including one-shot failures for retry tests.
Omitting the count keeps a rule active until it is removed or the server
restarts. Matching ignores query parameters and uses the exact `req.path`
seen by the middleware. A replacement rule for the same method/path takes
effect for subsequent requests. Requests already delayed keep their original
rule. Rules and delays are bounded, and simulation defaults to disabled when
`NODE_ENV=production`.

You can also configure a rule directly:

```ts
simulation.put({
  method: "POST",
  path: "/checkout",
  effect: "httpError",
  statusCode: 503,
  body: { error: "Service temporarily unavailable" },
  times: 1,
});
```

The desktop controls use `GET /simulation` with `Vigil-Read-Key` to inspect
rules, `POST /simulation` with `Vigil-Control-Key` to create or replace a rule,
and `DELETE /simulation/:id` or `DELETE /simulation` to remove rules. These
paths are relative to the inspector mount. Keep the control key on the server
and in your development browser.

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
