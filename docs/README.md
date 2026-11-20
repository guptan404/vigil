# Vigil setup and workflows

These guides cover the debugging features on `feature/debugging-workflows`.
They are not all included in the published `0.1.2` packages. Install every
Vigil package from the same Git ref until a release includes these changes.
For reproducible app builds, pin a commit and commit the application's lockfile.

1. [Configure Express](backend-setup.md): capture ingest, desktop inspector,
   request diagnostics, and server response controls.
2. [Configure Flutter](flutter-setup.md): capture, upload, session identity,
   replay, and local mocks.
3. [Use the debugging tools](debugging-workflows.md): inspect, compare, save,
   replay, mock, and exercise actual backend failure handling.

## How the pieces connect

The Dio interceptor captures a call and sends `traceparent`,
`Vigil-Session-Id`, `Vigil-Device-Type`, and optionally `Vigil-Key` to your API.
Express returns timing and optional diagnostics on that same response.
Separately, the Flutter uploader sends masked captures to `/vigil/ingest`.
The desktop inspector reads those uploads and creates server simulation rules
for the selected device session. An ordinary API request alone does not add a
device to the desktop: the uploader must also be running.

Local Flutter mocks resolve in the client. Desktop response controls run in
Express, so requests must reach that server to exercise them.

## The four keys

The environment names below are conventions used by these guides. The SDK
does not automatically load them from environment variables or AWS SSM; your
application must pass them into the corresponding configuration properties.

| Setting | Where to configure it | Header | Purpose |
| --- | --- | --- | --- |
| `VIGIL_INGEST_KEY` | Server `vigilIngestHandler.ingestKey`; Flutter `VigilBackendConfig.ingestKey` | `Vigil-Ingest-Key` | Authorize capture uploads. Flutter and server values must match. |
| `VIGIL_DEBUG_KEY` | Server middleware/error handler `debugKey`; optional Flutter `VigilConfig.debugKey` | `Vigil-Key` | Request gated error details and explicit request logs. Also required for simulated API calls in the controller's default mode. |
| `VIGIL_INSPECTOR_KEY` | Server router `readKey`; browser **Inspector read key** | `Vigil-Read-Key` | Read device sessions, captures, and simulation configuration. |
| `VIGIL_CONTROL_KEY` | Server simulation `controlKey`; browser **Simulation control key** | `Vigil-Control-Key` | Create and delete server simulation rules. |

Generate four independent values. Keep the inspector and control keys on the
server and in the authorized developer's browser; do not ship them in Flutter.
Ingest and debug keys shipped in an app are development gates, not application
login credentials. They do not replace API authentication or authorization.
Use HTTPS outside localhost, restrict access to the test environment, and
review capture masking before sharing data.

The bundled local preview deliberately uses `dev-vigil` for both ingest and
debug, `dev-vigil-read` for inspector reads, and `dev-vigil-control` for
controls. Those are public demo values. Its `VIGIL_SIMULATION_KEY` environment
variable maps to `controlKey`; it is an example-specific alias, not a fifth key.

## Device sessions and saved debug sessions

A **device session** is the live identity created by `Vigil.instance.init()`.
It groups one app run's requests and scopes desktop simulation rules. Its ID
is a selector, not a secret or an authentication credential. A trace ID links
one request across client and server; it is not the device session ID.

A **saved debug session** is a named snapshot with notes stored in local app
preferences. It can be loaded or exported for investigation. Loading a snapshot
does not reconnect its original device, restore server rules, or resume traffic.
Preferences and exported JSON are not secure secret storage.

## Feature availability

| Feature | Flutter inspector | Desktop inspector |
| --- | --- | --- |
| Expandable JSON, field search, copy JSON path | Yes | Raw/detail views |
| Host, all HTTP methods, status range, duration filters | Yes | Text search by URL, method, status, trace |
| Named saved debug sessions, notes, import/export | Yes | Live uploaded captures |
| Compare request and response pairs | Yes | Inspect individual calls |
| Edit and replay | With `VigilDioReplay` callback | Not currently available |
| Mock responses and network failures | Local Dio rules | Session-scoped Express rules |
| Request-linked backend timing and logs | Yes, when returned by Express | Yes, when uploaded by Flutter |
| Device-session monitoring | Copy current session ID | Device list or direct ID connection |

The desktop has Vigil's network-check logo and light palette, independently
scrolling request/detail panes, and request-level **Mock response** and
**Fail request** controls. It does not currently duplicate every Flutter tool.

## Retention and limits

Flutter capture, upload queues, and the default Express sink are bounded and
in memory. Local mock rules are also in memory. Saved Flutter snapshots persist
separately in local preferences. Express restarts discard captures and simulation rules. The memory
sink is per process: several ECS tasks or Node workers do not share sessions or
rules. A fleet needs deliberate routing to the same instance or an integration
designed for shared state; this SDK does not provide distributed aggregation.

The default sink retains up to 100 batches / 1,000 calls. The desktop returns
at most 200 captures with a roughly 2 MiB response budget, so session counts
can exceed the visible retained detail list. Configure retention for your test
traffic and keep Vigil disabled in production by default.
