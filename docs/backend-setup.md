# Express backend setup

Start with the [key reference](README.md#the-four-keys). This guide uses a
standalone test server. For an existing app, keep its real authentication,
routes, and error handler, and mount the Vigil components in the same order.

## Install from Git

Use Node.js 22.12+ within 22.x, or Node.js 24+, for Git installation and workspace
builds. Published Node libraries support Node.js 18+, but their `0.1.2` release
does not contain all the features below. The package is ESM-only.

```sh
npm init -y
npm install express cors '@vigiljs/express@git+https://github.com/guptan404/vigil.git#feature/debugging-workflows'
```

The repository root exports the Express integration and builds its Node
packages during Git installation. Allow the prepare script to run; if your
package manager blocks install scripts, approve this dependency using its
script policy and reinstall. Commit
your application's lockfile, or replace the branch ref with a chosen commit.

Generate local test keys in a file excluded from Git. The following is Bash:

```bash
umask 077
{
  echo 'VIGIL_ENABLED=true'
  echo 'VIGIL_SIMULATION_ENABLED=true'
  for name in VIGIL_INGEST_KEY VIGIL_DEBUG_KEY VIGIL_INSPECTOR_KEY VIGIL_CONTROL_KEY; do
    printf '%s=%s\n' "$name" "$(openssl rand -hex 32)"
  done
} > .env.vigil.local
printf '\n.env.vigil.local\n' >> .gitignore
```

## Complete server

Save this as `server.mjs`. Both flags default off in this application recipe;
the SDK's own default for several components is `NODE_ENV !== 'production'`.
Explicit flags also allow an intentional test deployment whose Node runtime
uses `NODE_ENV=production`.

```js
import express from 'express';
import cors from 'cors';
import {
  createMemoryVigilSink,
  vigilMiddleware,
  vigilErrorHandler,
  vigilIngestHandler,
  vigilInspectorRouter,
  VigilFailureSimulation,
} from '@vigiljs/express';

const app = express();
const enabled = process.env.VIGIL_ENABLED === 'true';
const simulationEnabled = enabled && process.env.VIGIL_SIMULATION_ENABLED === 'true';
const key = name => {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};

class UserStoreUnavailableError extends Error {}

app.use(cors({
  origin: ['http://localhost:4020', 'http://127.0.0.1:4020'],
  allowedHeaders: [
    'Content-Type', 'Authorization', 'traceparent', 'Vigil-Key',
    'Vigil-Ingest-Key', 'Vigil-Session-Id', 'Vigil-Device-Type',
  ],
  exposedHeaders: ['Server-Timing', 'traceparent', 'Vigil-Debug', 'Vigil-Simulation'],
}));
app.use(express.json({ limit: '5mb' }));

if (enabled) {
  const ingestKey = key('VIGIL_INGEST_KEY');
  const debugKey = key('VIGIL_DEBUG_KEY');
  const readKey = key('VIGIL_INSPECTOR_KEY');
  const controlKey = key('VIGIL_CONTROL_KEY');
  if (new Set([ingestKey, debugKey, readKey, controlKey]).size !== 4) {
    throw new Error('Use four distinct Vigil keys');
  }
  const sink = createMemoryVigilSink(100, 1000);
  const simulation = new VigilFailureSimulation({
    enabled: simulationEnabled,
    debugKey,
    controlKey,
    allowedPaths: [],
    allowCapturedPaths: true,
    requireDebugKey: false,
    failurePoints: {
      'users.lookup': () => new UserStoreUnavailableError('User store is unavailable'),
    },
  });
  app.use(vigilMiddleware({ enabled, debugKey, simulation }));
  app.use(simulation.middleware());
  app.post('/vigil/ingest', vigilIngestHandler({
    enabled, ingestKey, maxBatchCalls: 100, onBatch: sink.onBatch,
  }));
  app.use('/vigil/inspector', vigilInspectorRouter({
    enabled, sink, readKey, simulation,
  }));
}

app.get('/health', (_req, res) => res.json({ ok: true }));
app.get('/example', async (req, res, next) => {
  try {
    const lookup = async () => {
      req.vigil?.failPoint('users.lookup');
      return { id: 'demo-user', name: 'Example user' };
    };
    const user = req.vigil
      ? await req.vigil.time('db', 'Load example user', lookup)
      : await lookup();
    req.vigil?.log('info', 'Loaded example user', { userId: user.id });
    res.json({ user });
  } catch (error) {
    if (error instanceof UserStoreUnavailableError) {
      // This is the application's real failure response, not an entered mock body.
      res.status(503).json({ error: { code: 'USER_STORE_UNAVAILABLE' } });
      return;
    }
    next(error);
  }
});

app.use(vigilErrorHandler({
  enabled,
  debugKey: enabled ? key('VIGIL_DEBUG_KEY') : undefined,
  passThroughErrors: true,
}));
app.use((error, _req, res, _next) => {
  res.status(error.status ?? 500).json({ error: { code: 'INTERNAL_ERROR' } });
});

app.listen(Number(process.env.PORT ?? 4010), process.env.HOST ?? '127.0.0.1');
```

```sh
node --env-file=.env.vigil.local server.mjs
```

Open [the local desktop inspector](http://127.0.0.1:4010/vigil/inspector).
Enter the **inspector** key to read captures and the **control** key in
**Response controls** to change responses. Configure [Flutter](flutter-setup.md)
with the same ingest key. The optional Flutter debug key must match the server
debug key to receive logs and error diagnostics.

For a physical phone, bind to a reachable test interface (for example set
`HOST=0.0.0.0` on a trusted local network) and use the machine's LAN address in
Flutter. Replace the CORS origins with your actual Flutter Web origins.

## Middleware and configuration rules

Keep JSON parsing before ingest. Keep `vigilMiddleware` and the simulation's
middleware before business routes. Mount `vigilErrorHandler` after routes and
before your existing error handler; `passThroughErrors: true` leaves response
formatting to that handler. Pass the **same sink** to ingest and inspector and
the **same simulation instance** to instrumentation and inspector.

`ingestKey` is optional in the SDK: an enabled handler without it accepts
unauthenticated uploads. The complete recipe deliberately rejects missing keys.
The 5 MiB parser limit and `maxBatchCalls` are independent. Tune body capture,
client batch size, proxy limits, and parser limits together for large traffic.

`req.vigil.log(level, message, fields)` adds explicit request-linked logs; it
does not forward `console.log`, CloudWatch, or an existing logger automatically.
Only a matching debug key enables these logs and `Vigil-Debug`. Record entries
before response headers are sent. Logs are bounded to 20 entries, messages to
300 characters, and fields to 512 bytes; the diagnostics header has a default
8 KiB budget. Configure your infrastructure to allow the required headers.

## Server response controls

This recipe enables **all captured API paths for the selected device session**.
At rule creation, the inspector checks the retained capture's exact path and
HTTP method. It excludes `/vigil` and `/vigil/*`. Query strings are not part of
rule matching. Add exact `allowedPaths` if you also need statically permitted
endpoints; wildcards are not supported.

`requireDebugKey: false` explicitly selects session-only simulation: every rule
must have a valid session ID, and affected API calls must carry that ID. They
do not need `Vigil-Key`; diagnostics still do. In the default
`requireDebugKey: true` mode, affected API calls must also carry the matching
debug key. Inspector mutations require the control key in either mode.

| Effect | What happens |
| --- | --- |
| `mock` | Return a chosen JSON response and status 200–599 before the route. |
| `httpError` | Return a chosen error JSON response and status 400–599 before the route. |
| `exception` / Before route | Pass an error to the real Express error handler. |
| `exception` / named failure point | Throw the registered application error at `req.vigil.failPoint(name)`; the application's catch/error handler chooses the response. |
| `delay` | Wait, then run the original route. |
| `timeout` | Hold the connection, then close it; use a longer delay than the client's timeout to test a receive timeout. |
| `disconnect` | Close the connection, immediately unless a delay is supplied. |

For the sample's real failure case, first capture `GET /example`, select it in
the desktop, choose **Fail request**, select **users.lookup**, set count **1**,
and enable the rule. The next call runs the route, throws the registered error
inside the lookup, and reaches its real catch block, returning 503 with
`USER_STORE_UNAVAILABLE`. No response body is entered for a named failure point.
**Before route** is a separate location and does not exercise a route's catch
block. Arbitrary operations require their own explicit fail point.

Server rules match session, method, path, and optional failure point. A new
rule for that combination replaces the previous one. Request count accepts
1–10,000; leaving it empty keeps the rule active until removal or restart.
Request shortcuts default to one request. Counts are consumed before application
execution so concurrent calls respect the limit. Removing a rule does not
cancel a delay already applied to an in-flight call. Delays are capped at
120 seconds. Named points use only their registered error factory, without
custom status, body, or delay.

Controls affect requests reaching this Express instance, including API
authentication failures if your application mounts simulation before its auth
middleware. Choose middleware placement for your test setup deliberately.
They cannot change third-party servers or requests already handled by a local
Flutter mock. Your real API authentication remains required for normal routes.

## Deployment and SSM

The SDK has no built-in SSM lookup or fixed parameter namespace. Store keys as
your deployment's secrets, for example `/<test-env>/<service>/VIGIL_CONTROL_KEY`,
and inject them into your app using your existing secret configuration. Wire
each value to the API property shown in the [key table](README.md#the-four-keys).
The `VIGIL_ENABLED` and `VIGIL_SIMULATION_ENABLED` flags in this guide are
application-owned switches, not automatically consumed SDK variables.

1. Provision four distinct keys and the intentional test-only flags.
2. Apply the service/task configuration that injects them. Confirm the running
   task definition includes the secrets and flags, without logging key values.
3. Deploy the feature code and roll/restart the service. SSM changes alone do
   not refresh values already loaded into a running process or ECS task.
4. Check health, authenticated inspector reads, upload acceptance, and controls.
   Reconnect the browser and send a fresh call from Flutter.
5. After key rotation, update both upload endpoints/clients for ingest, both
   diagnostic endpoints/clients for debug, and the developer browser for
   read/control. Rebuild an app when its Dart defines change.

An image-only deployment cannot enable controls if the simulation controller,
control key, or explicit test-environment flag is missing. Keep the same sink
and simulation instance per server. With multiple workers/tasks, the built-in
memory store is not shared; route traffic consistently to the owning instance
or implement a suitable shared-state integration before relying on it.

## Verification

Expect `/health` to return 200. A correct-key upload returns 202; a wrong
configured ingest key returns 403. Malformed upload bodies return 400, and
oversized call counts return 413. Browser reads require `Vigil-Read-Key`.

`GET /vigil/inspector/simulation?sessionId=<id>` with the read key reports
`enabled`, `requestDebugKeyRequired`, paths, failure points, and rules. A safe
configuration probe is `POST /vigil/inspector/simulation` with `{}` and no
control key: an enabled configured controller returns 403; an absent or disabled
controller returns 404. That unauthenticated probe never creates a rule.
See [troubleshooting](debugging-workflows.md#troubleshooting) for symptom checks.
