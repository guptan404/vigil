# Debugging workflows

Configure [Flutter](flutter-setup.md) and, for desktop monitoring or backend
failure cases, [Express](backend-setup.md). The [feature matrix](README.md#feature-availability)
shows which tools are available on each surface.

## Inspect JSON and filter requests

Open Flutter Vigil by shaking the device, using its floating button, or your
app's debug menu. Search calls and combine host, HTTP method, minimum/maximum
status, and duration filters. Clear filters if an expected request is missing.
Open a call's Request or Response tab, expand JSON objects/arrays, search for a
field/value, and use **Copy JSON path** on the relevant field. Non-JSON body
previews remain text or summaries. The Timing and Debug tabs show capture
duration, server timing, client failures, and returned diagnostics.

Use **Copy cURL** for a command, replacing masked credentials before running
it. **Copy lifecycle** / **Share lifecycle** include request, response, timing,
trace, and failure details. Review captured data before sharing.

## Save and compare an investigation

In **Inspector tools → Debug sessions**, save the current capture under a name
with notes. Load it later, export/copy its JSON, or import a session from the
clipboard. These snapshots persist in local app preferences; they are separate
from live desktop device sessions and do not restore remote mocks.

For a before/after comparison, capture both calls, open a call's details, then
choose **Compare with** and select the other call. Inspect differences in the
request and response. Save/export a snapshot when retaining the investigation
beyond the app's bounded in-memory capture history.

## Edit and replay

With the replay callback configured, select **Edit and replay** on a completed
or failed Flutter call. Edit method, URL/query, extra headers, or JSON body,
review changes, and send it. Your app's authorized Dio client supplies API
authentication. Replay stays on the allowed development origin; side-effecting
methods require confirmation. The new call is captured for comparison.

## Connect the desktop to one device

1. Start capture and the Flutter uploader, then make an API call.
2. Open your server's `/vigil/inspector` in a desktop browser.
3. Connect using the **Inspector read key**, not the ingest or debug key.
4. Select a device card, or copy the ID from Flutter, paste it in **Session ID**,
   and choose **Connect to session**. Direct connection can wait for the first
   upload if the device has not sent any captures yet.
5. Watch that device's requests update. Search by URL, method, status, or trace.
   Open Request, Response, Timing, Debug, or Raw details. The request list and
   detail pane scroll independently. **All sessions** returns to the device list.

The read key authorizes reading sessions; the session ID selects one. Session
selection is not tenant authorization. Anyone authorized with that read key
can list the sink's device sessions. A new app initialization has a new ID.

## Mock or fail one device's requests

In the desktop, select a device and open **Response controls**. Enter the
**Simulation control key** (server control key). Select a captured request and
choose **Mock response** or **Fail request** to fill its method and path, or
choose them in the rule form. Choosing a captured request automatically updates
the Method field. Requests sharing a path appear separately by method (for
example, `GET /orders` and `POST /orders`). In the backend guide's configuration,
all captured API methods/paths in that session are eligible, excluding Vigil's own routes.

For a mock, choose the status and JSON body. For a real code failure, choose a
registered failure location such as **users.lookup**. That location must have
both an error factory and a matching `req.vigil.failPoint()` in backend code.
The existing route/catch/error handler sends the actual application response.
No manual body is required. **Fail request → Before route** instead passes an
exception to Express error handling before the business route runs.

Set request count to **1** for a one-shot check, enable the rule, then trigger
the operation again from the same app. Confirm the expected response and UI
error state; trigger it again to confirm normal recovery. Another device's ID
does not match and does not consume the count. Leaving count empty makes a
rule persistent until removed or the server restarts. Remove active rules when
finished; restarting the app alone leaves rules for its old ID on the server.

Use delay to run the real route more slowly, timeout to hold then close the
connection, or disconnect to drop it. To test a client receive timeout, set the
server timeout delay longer than the client's receive timeout. These modes
produce different client errors and may have no response body.

For a Flutter-only failure, open **Inspector tools → Mock responses**. Local
rules affect only that Dio client and do not exercise backend code. Remove
local matching rules before testing server controls. Desktop controls cannot
mock a third-party API host that is not routed through this Express server.

## Request-linked backend logs

Send the matching debug key on the business API request and call
`req.vigil.log('info', 'message', { ...fields })` in backend code before headers
are sent. Open the request's Debug tab in Flutter or desktop to view those
entries with its trace and error context. Uploading without diagnostics still
shows captured requests, but cannot reconstruct server logs. No key or session
setting automatically streams arbitrary logger output or CloudWatch logs.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Inspector says key denied | Enter `VIGIL_INSPECTOR_KEY`, wired as `readKey`. The ingest key only authorizes uploads. |
| Session ID field cannot connect | Authenticate with the read key first, then enter the ID and choose **Connect to session**. Check the deployed SDK revision includes direct connection. |
| Device absent / waiting forever | Confirm uploader enabled before the call, correct ingest URL/key, network reachability, CORS, and 202 uploads. Plain API traffic does not register a desktop device. |
| Captures missing on some refreshes/tasks | Ingest, API simulation, and inspector may be hitting different memory sinks/processes. Check routing and task count. |
| Old frontend session selected | Copy the current ID again after an app restart or reinitialization. Clearing capture alone keeps the ID. |
| “Response controls are not configured on this server” | Instantiate and enable `VigilFailureSimulation`, supply its distinct server control key, and pass that same controller to instrumentation and router. Check deployed flags/task secrets and restart after configuration changes. |
| Control mutation returns 403 | Controller is configured, but `Vigil-Control-Key` is missing/wrong. Use the control key, not the read/ingest/debug key. |
| Control mutation returns 404 | Controller/router disabled or absent, stale deployment, wrong route, or a requested rule no longer exists. Inspect authenticated simulation configuration. |
| Rule rejected for path/method | Capture that exact method/path in the selected device first, or add a static allowed path. Use no query string; Vigil's own endpoints cannot be simulated. |
| Rule enabled but call succeeds | Check session ID, method/path, remaining count, selected failure point execution, server instance, and local Flutter mocks. Default simulation mode also needs the API request's debug key; explicit session-only mode does not. |
| Named point still shows a generic error | Confirm the registered factory returns the real application error type and the fail point runs inside the intended catch boundary. **Before route** does not run the route's catch block. |
| No backend logs/stack | Match the debug key on API calls, use explicit `req.vigil.log` before headers, mount diagnostics correctly, and expose response headers for Flutter Web. Connection failures have no server response to decode. |
| Replay/mock controls absent in Flutter | Pass `replay.send` and the same mock controller to UI and interceptor; ensure all packages use the same feature revision. |
| Local HTTP fails on device/web | Use the correct emulator/LAN host, reachable bind address, allowed CORS origin, and appropriate debug HTTP policy. HTTPS pages cannot call HTTP APIs. |
| Large upload fails | Check proxy/parser byte limits and `maxBatchCalls`; reduce `maxBodyBytes` or `batchSize`. The memory queue can evict old captures during repeated failures. |
| Git dependency still has old UI | Inspect app lockfiles/resolved Git commit, deliberately upgrade branch packages, rebuild the app/backend image, and restart tasks. A branch moving does not update a locked dependency automatically. |

For configuration probes and deployment order, see
[backend verification](backend-setup.md#verification) and
[deployment and SSM](backend-setup.md#deployment-and-ssm).
