import { createHash, timingSafeEqual } from "node:crypto";
import { Router, json } from "express";
import type { RequestHandler } from "express";
import type { VigilFailureSimulation } from "./simulation.js";
import type { VigilMemorySink } from "./index.js";

export interface VigilInspectorConfig {
  /** The same sink used by the ingest handler. */
  sink: VigilMemorySink;
  /** Separate, server-only key that grants read access to captures. */
  readKey: string;
  /** Defaults to enabled outside production. */
  enabled?: boolean;
  /** Optional server failure controller. */
  simulation?: VigilFailureSimulation;
}

/** Mounts a desktop inspector and its same-origin capture API. */
export function vigilInspectorRouter(config: VigilInspectorConfig): Router {
  if (!config.readKey.trim()) throw new Error("Vigil inspector requires a read key");
  const expected = createHash("sha256").update(config.readKey).digest();
  const router = Router();

  router.use((_req, res, next) => {
    res.set({
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    });
    if (!(config.enabled ?? process.env.NODE_ENV !== "production")) {
      res.sendStatus(404);
      return;
    }
    next();
  });
  router.get("/", (_req, res) => {
    res.set("Content-Security-Policy",
      `default-src 'none'; script-src 'sha256-${scriptHash}'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`);
    res.type("html").send(page);
  });
  const authorizeRead: RequestHandler = (req, res, next) => {
    const supplied = createHash("sha256").update(req.header("Vigil-Read-Key") ?? "").digest();
    if (!timingSafeEqual(supplied, expected)) {
      res.status(403).json({ error: "Vigil inspector access denied" });
      return;
    }
    next();
  };
  router.get("/simulation", authorizeRead, (_req, res) => {
    const simulation = config.simulation;
    res.json({
      enabled: simulation?.enabled ?? false,
      allowedPaths: simulation?.allowedPaths ?? [],
      failurePoints: simulation?.failurePoints ?? [],
      rules: simulation?.list() ?? [],
    });
  });
  router.use("/simulation", (req, res, next) => {
    if (!config.simulation?.enabled) {
      res.sendStatus(404);
      return;
    }
    if (!config.simulation.authorizeControl(req.header("Vigil-Control-Key"))) {
      res.status(403).json({ error: "Vigil simulation control denied" });
      return;
    }
    next();
  });
  router.post("/simulation", json({ limit: "80kb" }), (req, res) => {
    try {
      res.status(201).json(config.simulation!.put(req.body));
    } catch (error) {
      res.status(400).json({ error: error instanceof Error ? error.message : "Invalid rule" });
    }
  });
  router.delete("/simulation/:id", (req, res) => {
    res.sendStatus(config.simulation!.remove(req.params.id as string) ? 204 : 404);
  });
  router.delete("/simulation", (_req, res) => {
    config.simulation!.clear();
    res.sendStatus(204);
  });
  router.get("/captures", authorizeRead, (_req, res) => {
    const captures: string[] = [];
    const retained = new Set(config.sink.calls);
    let bytes = 0;
    for (const batch of config.sink.batches.slice().reverse()) {
      for (const call of batch.calls.slice().reverse()) {
        if (!retained.has(call)) continue;
        const encoded = JSON.stringify({ client: batch.client, sentAt: batch.sentAt, call });
        const size = Buffer.byteLength(encoded);
        if (bytes + size > 2 * 1024 * 1024) continue;
        captures.push(encoded);
        bytes += size;
        if (captures.length >= 200) break;
      }
      if (captures.length >= 200) break;
    }
    res.type("json").send(`{"captures":[${captures.join(",")}]}`);
  });
  return router;
}

const script = `
const byId = (id) => document.getElementById(id);
const access = byId("access");
const key = byId("key");
const status = byId("status");
const query = byId("query");
const device = byId("device");
const list = byId("calls");
const detail = byId("detail");
const views = byId("views");
const detailTitle = byId("detail-title");
const disconnect = byId("disconnect");
const detailMeta = byId("detail-meta");
const copyDetail = byId("copy-detail");
const viewTabs = [...document.querySelectorAll("[data-view]")];
for (const [index, button] of viewTabs.entries()) {
  button.id = "view-" + button.dataset.view;
  button.setAttribute("aria-controls", "detail");
  button.onclick = () => { views.value = button.dataset.view; render(); };
  button.onkeydown = event => {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const target = event.key === "Home" ? 0 : event.key === "End" ? viewTabs.length - 1
      : (index + (event.key === "ArrowRight" ? 1 : -1) + viewTabs.length) % viewTabs.length;
    if (!viewTabs[target].disabled) { viewTabs[target].click(); viewTabs[target].focus(); }
  };
}
copyDetail.onclick = async () => {
  try {
    await navigator.clipboard.writeText(detail.textContent);
    copyDetail.textContent = "Copied";
    setTimeout(() => { copyDetail.textContent = "Copy"; }, 1500);
  } catch {
    status.textContent = "Select the request details to copy them.";
  }
};
let captures = [];
let selected = "";
let generation = 0;
let timer;
let readKey = "";
let lastPayload = "";
let simulationPayload = "";
let failurePointsInitialized = false;
const failurePanel = byId("failures");
const failureRules = byId("failure-rules");
const failureStatus = byId("failure-status");
const failureForm = byId("failure-form");
const controlKey = byId("control-key");

function apiPath(suffix) {
  return location.pathname.replace(/\\/$/, "") + suffix;
}

function failureDescription(rule) {
  const effects = {
    httpError: "HTTP error", exception: "Backend exception", delay: "Delay and forward",
    timeout: "Timeout", disconnect: "Disconnect",
  };
  return rule.method + " " + rule.path + (rule.failurePoint ? " · " + rule.failurePoint : "") + " · " + effects[rule.effect] +
    (!rule.failurePoint && ["httpError", "exception"].includes(rule.effect) ? " " + rule.statusCode : "") +
    (rule.delayMs ? " · " + rule.delayMs + " ms" : "") +
    " · " + (rule.remaining === null ? "until removed" : rule.remaining + " request(s)");
}

function renderFailures(state) {
  failurePanel.hidden = !state.enabled;
  byId("rule-count").textContent = state.rules.length ? String(state.rules.length) : "";
  byId("clear-failures").disabled = state.rules.length === 0;
  const path = byId("failure-path");
  const selectedPath = path.value;
  path.replaceChildren(...state.allowedPaths.map(value => new Option(value, value)));
  if (state.allowedPaths.includes(selectedPath)) path.value = selectedPath;
  const point = byId("failure-point");
  const selectedPoint = point.value;
  const points = state.failurePoints ?? [];
  point.replaceChildren(new Option("Before route", ""),
    ...points.map(name => new Option(name, name)));
  if (points.includes(selectedPoint)) point.value = selectedPoint;
  else if (!failurePointsInitialized && points.length) {
    point.value = points[0];
  }
  failurePointsInitialized = true;
  updateFailureFields();
  failureRules.replaceChildren(...state.rules.map(rule => {
    const row = document.createElement("li");
    const label = document.createElement("span");
    label.textContent = failureDescription(rule);
    label.className = "rule-description";
    const remove = document.createElement("button");
    remove.type = "button";
    remove.textContent = "Remove";
    remove.onclick = () => changeFailure("DELETE", "/simulation/" + encodeURIComponent(rule.id));
    row.append(label, remove);
    return row;
  }));
}

async function loadFailures(id) {
  const response = await fetch(apiPath("/simulation"), {
    headers: { "Vigil-Read-Key": readKey }, cache: "no-store",
  });
  if (!response.ok) throw new Error("Unable to load failure rules.");
  const payload = await response.text();
  if (id !== generation) return;
  if (payload !== simulationPayload) {
    simulationPayload = payload;
    renderFailures(JSON.parse(payload));
  }
}

let updatingFailure = false;
async function changeFailure(method, path, body) {
  if (updatingFailure) return;
  if (!readKey) {
    failureStatus.textContent = "Connect to the inspector first.";
    return;
  }
  if (!controlKey.value) {
    failureStatus.textContent = "Enter the server simulation control key.";
    return;
  }
  const id = generation;
  updatingFailure = true;
  byId("enable-rule").disabled = true;
  failureStatus.textContent = "Applying change…";
  try {
    const response = await fetch(apiPath(path), {
      method,
      headers: { "Content-Type": "application/json", "Vigil-Control-Key": controlKey.value },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (id !== generation) return;
    if (!response.ok) {
      const message = await response.json().catch(() => null);
      throw new Error(message?.error ?? "Unable to change the failure rule.");
    }
    failureStatus.textContent = method === "POST" ? "Rule enabled on the Express server." : "Rule removed.";
    await loadFailures(id);
  } catch (error) {
    if (id === generation) failureStatus.textContent = error.message;
  } finally {
    updatingFailure = false;
    byId("enable-rule").disabled = false;
  }
}

failureForm.onsubmit = event => {
  event.preventDefault();
  const effect = byId("failure-effect").value;
  try {
    const rule = {
      method: byId("failure-method").value.trim().toUpperCase(),
      path: byId("failure-path").value,
      effect,
      delayMs: Number(byId("failure-delay").value),
    };
    const point = byId("failure-point").value;
    if (point) {
      rule.failurePoint = point;
      rule.delayMs = 0;
    }
    if (!point && ["httpError", "exception"].includes(effect)) rule.statusCode = Number(byId("failure-code").value);
    if (effect === "httpError") rule.body = JSON.parse(byId("failure-body").value);
    if (byId("failure-times").value) rule.times = Number(byId("failure-times").value);
    changeFailure("POST", "/simulation", rule);
  } catch {
    failureStatus.textContent = "Enter a valid JSON response body.";
  }
};

function updateFailureFields() {
  const point = byId("failure-point").value;
  const selector = byId("failure-effect");
  for (const option of selector.options) {
    option.disabled = !!point && option.value !== "exception";
  }
  if (point) selector.value = "exception";
  const effect = selector.value;
  byId("response-settings").hidden = effect !== "httpError";
  byId("status-settings").hidden = !!point || !["httpError", "exception"].includes(effect);
  byId("failure-code").disabled = !!point || !["httpError", "exception"].includes(effect);
  byId("delay-settings").hidden = !!point;
  byId("failure-delay").disabled = !!point;
  byId("point-help").hidden = !point;
  byId("effect-settings").hidden = !!point;
}
byId("failure-point").onchange = updateFailureFields;
byId("failure-effect").onchange = () => {
  const effect = byId("failure-effect").value;
  byId("failure-delay").value = effect === "timeout" ? "30000" : effect === "delay" ? "1000" : "0";
  updateFailureFields();
};
byId("clear-failures").onclick = () => changeFailure("DELETE", "/simulation");
failurePanel.onkeydown = event => {
  if (event.key === "Escape") {
    failurePanel.open = false;
    failurePanel.querySelector("summary").focus();
  }
};


function clientLabel(item) {
  return [item.client?.app, item.client?.device ?? item.client?.sessionId]
    .filter(value => typeof value === "string" && value.length).join(" / ") || "Unknown";
}

function identity(item) {
  return JSON.stringify([clientLabel(item), item.call.id, item.call.startedAt]);
}

function render() {
  const currentDevice = device.value;
  const labels = [...new Set(captures.map(clientLabel))].sort();
  device.replaceChildren(new Option("All devices", ""), ...labels.map(label => new Option(label, label)));
  if (labels.includes(currentDevice)) device.value = currentDevice;
  const terms = query.value.trim().toLowerCase();
  const rows = captures.filter(item => {
    const call = item.call;
    const text = [call.request?.method, call.request?.url, call.response?.statusCode,
      call.trace?.traceId, call.state, clientLabel(item)].join(" ").toLowerCase();
    return (!device.value || clientLabel(item) === device.value) && text.includes(terms);
  });
  const active = rows.find(item => identity(item) === selected) ?? rows[0];
  selected = active ? identity(active) : "";
  list.replaceChildren(...rows.map(item => {
    const call = item.call;
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute("aria-pressed", String(identity(item) === selected));
    const label = document.createElement("strong");
    label.className = "request-line";
    const method = document.createElement("span");
    method.className = "method";
    method.textContent = call.request?.method ?? "HTTP";
    const code = document.createElement("span");
    code.className = "status-code " + (call.response?.statusCode >= 400 || call.state === "failed" ? "failed" : "success");
    code.textContent = call.response?.statusCode ?? call.state ?? "pending";
    label.append(method, code);
    const url = document.createElement("span");
    url.textContent = call.request?.url ?? "Unknown request";
    url.className = "request-url";
    const meta = document.createElement("small");
    const capturedAt = new Date(call.startedAt);
    const time = Number.isNaN(capturedAt.getTime()) ? "" : capturedAt.toLocaleTimeString(
      undefined, { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false });
    meta.title = call.startedAt ?? "";
    meta.textContent = [clientLabel(item), typeof call.durationMs === "number"
      ? call.durationMs.toFixed(1) + " ms" : "", time].filter(Boolean).join(" · ");
    button.append(label, url, meta);
    button.onclick = () => { selected = identity(item); render(); };
    return button;
  }));
  if (!rows.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    const title = document.createElement("strong");
    title.textContent = captures.length ? "No matching requests" : "Waiting for requests";
    const hint = document.createElement("p");
    hint.textContent = captures.length ? "Try a different search or device." : "Make a request in the app to see it here.";
    empty.append(title, hint);
    list.append(empty);
  }
  for (const button of viewTabs) {
    button.disabled = !active;
    button.setAttribute("aria-selected", String(button.dataset.view === views.value));
    button.tabIndex = button.dataset.view === views.value ? 0 : -1;
  }
  detail.setAttribute("aria-labelledby", "view-" + views.value);
  copyDetail.disabled = !active;
  detailMeta.textContent = active ? [
    active.call.request?.method,
    active.call.response?.statusCode ?? active.call.state,
    typeof active.call.durationMs === "number" ? active.call.durationMs.toFixed(1) + " ms" : "",
  ].filter(Boolean).join(" · ") : "";
  views.disabled = !active;
  detailTitle.textContent = active?.call.request?.url ?? "Request details";
  if (!active) {
    detail.textContent = "Select a request to inspect its response, timings, and backend diagnostics.";
    return;
  }
  const call = active.call;
  const bodySection = (side) => {
    if (!side) return null;
    const summary = side.body;
    let body = summary?.text ?? summary ?? null;
    if (summary?.kind === "json" && !summary.truncated && typeof summary.text === "string") {
      try { body = JSON.parse(summary.text); } catch { /* Keep the captured text. */ }
    }
    return {
      body,
      ...(summary?.truncated ? { truncated: true } : {}),
      headers: side.headers ?? {},
    };
  };
  const sections = {
    overview: { client: active.client, trace: call.trace, status: call.response?.statusCode,
      state: call.state, startedAt: call.startedAt, durationMs: call.durationMs },
    request: bodySection(call.request),
    response: bodySection(call.response),
    timing: { durationMs: call.durationMs, serverTimings: call.response?.serverTimings ?? [] },
    debug: { clientError: call.error, serverDebug: call.response?.serverDebug },
    raw: active,
  };
  const section = sections[views.value];
  detail.textContent = section == null ? "No data captured." : JSON.stringify(section, null, 2);
}

function stop(message) {
  generation++;
  clearTimeout(timer);
  readKey = "";
  lastPayload = "";
  simulationPayload = "";
  failurePointsInitialized = false;
  failurePanel.hidden = true;
  failureRules.replaceChildren();
  failureStatus.textContent = "";
  controlKey.value = "";
  captures = [];
  selected = "";
  disconnect.disabled = true;
  status.textContent = message;
  status.dataset.connected = "false";
  render();
}

async function refresh(id) {
  try {
    const url = location.pathname.replace(/\\/$/, "") + "/captures";
    const result = await fetch(url, { headers: { "Vigil-Read-Key": readKey }, cache: "no-store" });
    if (id !== generation) return;
    if (result.status === 403) {
      stop("Read key rejected.");
      return;
    }
    if (!result.ok) throw new Error("Capture request failed");
    const payload = await result.text();
    if (id !== generation) return;
    if (payload !== lastPayload) {
      captures = JSON.parse(payload).captures;
      lastPayload = payload;
      render();
    }
    status.textContent = captures.length + (captures.length === 1 ? " request" : " requests");
    status.dataset.connected = "true";
    await loadFailures(id);
  } catch {
    if (id !== generation) return;
    status.textContent = "Unable to load captures. Retrying.";
  }
  timer = setTimeout(() => refresh(id), 2000);
}

access.onsubmit = (event) => {
  event.preventDefault();
  stop("Connecting…");
  readKey = key.value;
  key.value = "";
  disconnect.disabled = false;
  refresh(generation);
};
disconnect.onclick = () => stop("Disconnected.");
query.oninput = render;
device.onchange = render;
views.onchange = render;
render();
`;

const scriptHash = createHash("sha256").update(script).digest("base64");
const page = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Vigil Network Inspector</title>
<style>
:root {
  color-scheme: light dark;
  font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  --bg: #f5f8f6; --panel: #fff; --raised: #eef3f0; --ink: #172a23;
  --muted: #61746b; --line: #dce5df; --accent: #137955; --tint: #e4f4eb; --error: #b33d43;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #0e1512; --panel: #151e19; --raised: #1c2821; --ink: #e4eee8;
    --muted: #a0b4a7; --line: #2b3b31; --accent: #86d9ac; --tint: #203d2b; --error: #ffa5a9; }
}
* { box-sizing: border-box; }
[hidden] { display: none !important; }
body { margin: 0; background: var(--bg); color: var(--ink); font-size: 14px; line-height: 1.5; }
button, input, select, textarea { font: inherit; color: inherit; border: 1px solid var(--line);
  border-radius: 9px; padding: 9px 12px; background: var(--panel); min-height: 40px; }
input, select, textarea { min-width: 0; max-width: 100%; }
input:focus-visible, select:focus-visible, textarea:focus-visible, button:focus-visible, summary:focus-visible {
  outline: 2px solid var(--accent); outline-offset: 3px; }
button { cursor: pointer; font-weight: 600; transition: background .15s; }
button:hover:not(:disabled) { background: var(--raised); }
button:disabled { opacity: .45; cursor: default; }
button.primary { background: var(--accent); color: var(--panel); border-color: var(--accent); }
button.primary:hover:not(:disabled) { filter: brightness(.92); background: var(--accent); }
header { display: flex; flex-wrap: wrap; gap: 20px; align-items: center;
  padding: 18px 28px; background: var(--panel); border-bottom: 1px solid var(--line); }
.brand { margin-right: auto; display: flex; gap: 12px; align-items: center; }
.brand-mark { width: 38px; height: 38px; display: grid; place-items: center; background: var(--tint);
  border: 1px solid var(--line); color: var(--accent); border-radius: 11px; font-size: 23px; font-weight: 700; }
h1 { margin: 0; font-size: 20px; letter-spacing: -.5px; line-height: 1.25; }
.brand p { margin: 2px 0 0; color: var(--muted); font-size: 12px; }
#access { display: flex; flex-wrap: wrap; gap: 8px; }
#key { width: 210px; }
nav { display: flex; gap: 12px; align-items: center; padding: 18px 28px; padding-right: 275px; }
nav:has(+ details[hidden]) { padding-right: 28px; }
#query { flex: 1; min-width: 150px; padding-left: 14px; }
#device { max-width: 230px; }
#status { color: var(--muted); font-size: 12px; white-space: nowrap; }
#status::before { content: ""; display: inline-block; width: 6px; height: 6px; border-radius: 50%;
  margin-right: 6px; background: var(--muted); vertical-align: 2px; }
#status[data-connected="true"]::before { background: var(--accent); }
main { margin: 0 28px 28px; display: grid; grid-template-columns: minmax(280px, 32%) minmax(0, 1fr);
  height: calc(100dvh - 185px); min-height: 420px; overflow: hidden;
  background: var(--panel); border: 1px solid var(--line); border-radius: 14px; }
#calls { overflow-y: auto; border-right: 1px solid var(--line); padding: 8px; }
#calls button { display: grid; gap: 7px; width: 100%; text-align: left; padding: 14px;
  border: 1px solid transparent; border-radius: 9px; margin-bottom: 4px; font-weight: 400; }
#calls button[aria-pressed="true"] { background: var(--tint); border-color: color-mix(in srgb, var(--accent) 30%, var(--line)); }
.request-line { display: flex; align-items: center; gap: 8px; }
.method { font: 700 11px ui-monospace, monospace; color: var(--accent); letter-spacing: .4px; }
.status-code { margin-left: auto; border-radius: 5px; padding: 2px 7px; background: var(--raised); font-size: 11px; }
.failed { color: var(--error); }
.success { color: var(--accent); }
.request-url { font-weight: 600; font-size: 13px; overflow-wrap: anywhere; }
small { font-size: 11px; color: var(--muted); }
#request-details { min-width: 0; display: flex; flex-direction: column; }
.detail-toolbar { padding: 20px 24px 12px; display: flex; align-items: start; gap: 12px; }
.detail-heading { flex: 1; min-width: 0; }
h2 { margin: 0; font-size: 15px; font-weight: 600; overflow-wrap: anywhere; }
#detail-meta { color: var(--muted); font-size: 12px; margin: 5px 0 0; }
#view-tabs { display: flex; overflow-x: auto; border-bottom: 1px solid var(--line); padding: 0 18px; gap: 4px; flex-shrink: 0; }
#view-tabs button { background: transparent; border: 0; border-radius: 0; padding: 12px 10px; color: var(--muted); font-size: 12px; }
#view-tabs button[aria-selected="true"] { color: var(--accent); box-shadow: inset 0 -2px var(--accent); }
#views { display: none; }
pre { padding: 24px; margin: 0; overflow: auto; white-space: pre-wrap; overflow-wrap: anywhere;
  font: 12px/1.85 ui-monospace, "SFMono-Regular", Consolas, monospace; tab-size: 2; }
.empty-state { padding: 48px 22px; text-align: center; color: var(--muted); }
.empty-state strong { color: var(--ink); font-weight: 600; }
.empty-state p { font-size: 12px; max-width: 240px; margin: 8px auto; }
#failures { position: absolute; right: 28px; top: 106px; z-index: 2; width: 222px; }
#failures summary { cursor: pointer; font-size: 12px; font-weight: 600; color: var(--accent);
  background: var(--panel); border: 1px solid var(--line); border-radius: 9px; padding: 11px 14px; }
#rule-count:not(:empty) { margin-left: 4px; background: var(--tint); padding: 1px 6px; border-radius: 5px; }
#failures[open] { position: fixed; top: 22px; right: 22px; width: min(440px, calc(100vw - 32px));
  max-height: calc(100dvh - 44px); overflow: auto; background: var(--panel);
  border: 1px solid var(--line); border-radius: 14px; box-shadow: 0 20px 90px #0005; z-index: 5; }
#failures[open] summary { position: sticky; top: 0; border: 0; border-bottom: 1px solid var(--line);
  border-radius: 0; padding: 20px; font-size: 15px; z-index: 1; }
#failures[open] summary::after { content: "×"; float: right; font-size: 20px; line-height: 20px; color: var(--muted); }
.panel-body { padding: 20px; }
.panel-body > p:first-child { margin-top: 0; }
.panel-body p { color: var(--muted); font-size: 12px; line-height: 1.7; }
#failures label { display: grid; gap: 6px; font-size: 12px; font-weight: 500; }
#failure-form { display: grid; grid-template-columns: 1fr 1fr; gap: 16px 12px; margin: 22px 0 14px; }
#response-settings, #enable-rule { grid-column: 1 / -1; }
#failure-body { width: 100%; font-family: ui-monospace, monospace; font-size: 12px; }
#failure-rules { list-style: none; padding: 0; margin: 16px 0; }
#failure-rules li { display: flex; gap: 12px; align-items: center; padding: 12px;
  border: 1px solid var(--line); border-radius: 9px; background: var(--raised); margin-bottom: 8px; }
.rule-description { flex: 1; min-width: 0; overflow-wrap: anywhere; font-size: 12px; }
#failure-rules button { font-size: 11px; min-height: 32px; padding: 6px 9px; }
#failure-status { color: var(--accent); }
#clear-failures { width: 100%; font-size: 12px; }
@media (max-width: 900px) {
  nav { flex-wrap: wrap; padding-right: 28px; }
  #status { width: 100%; min-height: 25px; }
  #failures { top: 162px; }
  main { height: calc(100dvh - 225px); grid-template-columns: minmax(230px, 36%) minmax(0, 1fr); }
}
@media (max-width: 600px) {
  header { padding: 16px; gap: 16px; }
  #access { width: 100%; }
  #key { flex: 1; width: 120px; }
  #access button { font-size: 12px; padding: 8px; }
  nav { padding: 16px; gap: 8px; }
  #query { width: 100%; flex-basis: 100%; }
  #device { max-width: 53%; }
  #status { width: auto; margin-left: auto; min-height: 0; }
  #failures { position: relative; width: auto; right: auto; top: auto; margin: 0 16px 16px; }
  #failures[open] { position: fixed; right: 16px; top: 16px; margin: 0; width: calc(100vw - 32px); max-height: calc(100dvh - 32px); }
  main { margin: 0 16px 16px; height: auto; min-height: 560px; grid-template-columns: minmax(0, 1fr); }
  #calls { max-height: 280px; border-right: 0; border-bottom: 1px solid var(--line); }
  .detail-toolbar { padding: 16px; }
  #view-tabs { padding: 0 8px; }
  #view-tabs button { padding: 12px 8px; }
  pre { padding: 16px; font-size: 11px; max-height: 500px; }
}
@media (prefers-reduced-motion: reduce) { button { transition: none; } }
</style>
</head>
<body>
<header>
  <div class="brand"><span class="brand-mark" aria-hidden="true">V</span>
    <div><h1>Vigil</h1><p>Backend inspector</p></div>
  </div>
  <form id="access">
    <input id="key" type="password" aria-label="Inspector read key" placeholder="Inspector read key" autocomplete="off" required>
    <button class="primary">Connect</button>
    <button id="disconnect" type="button" disabled>Disconnect</button>
  </form>
</header>
<nav aria-label="Capture filters">
  <input id="query" type="search" aria-label="Search captures" placeholder="Search URL, method, status, or trace ID">
  <select id="device" aria-label="Device"></select>
  <span id="status" role="status">Disconnected.</span>
</nav>
<details id="failures" hidden>
  <summary>Express failure simulation <span id="rule-count"></span></summary>
  <div class="panel-body">
  <p>Enable a rule, then make the matching request from your development app.</p>
  <label>Simulation control key
    <input id="control-key" type="password" autocomplete="off" placeholder="Server control key">
  </label>
  <form id="failure-form">
    <label>Method <input id="failure-method" value="GET" required pattern="[A-Za-z]+" maxlength="20"></label>
    <label>Exact path <select id="failure-path" required></select></label>
    <label>Failure location <select id="failure-point">
      <option value="">Before route</option>
    </select></label>
    <label id="effect-settings">Effect <select id="failure-effect">
      <option value="httpError">HTTP error response</option>
      <option value="exception">Backend exception</option>
      <option value="delay">Delay and forward</option>
      <option value="timeout">Timeout</option>
      <option value="disconnect">Disconnect</option>
    </select></label>
    <label id="status-settings">Error status <input id="failure-code" type="number" min="400" max="599" value="500" required></label>
    <label id="delay-settings">Delay (ms) <input id="failure-delay" type="number" min="0" max="120000" value="0" required></label>
    <label>Request count <input id="failure-times" type="number" min="1" max="10000" placeholder="Until removed"></label>
    <label id="response-settings">JSON response body
      <textarea id="failure-body" rows="3">{"error":"Simulated backend failure"}</textarea>
    </label>
    <button id="enable-rule" class="primary">Enable rule</button>
  </form>
  <p id="point-help" hidden>At a code failure point, the operation throws its registered
    error. Your route’s catch block or error handler chooses the status and response body.</p>
  <p id="failure-status" role="status" aria-live="polite"></p>
  <ul id="failure-rules"></ul>
  <button id="clear-failures" type="button">Remove all rules</button>
  </div>
</details>
<main>
  <div id="calls" aria-label="Captured requests"></div>
  <section id="request-details" aria-label="Request details">
    <div class="detail-toolbar">
      <div class="detail-heading"><h2 id="detail-title">Request details</h2>
        <p id="detail-meta"></p>
      </div>
      <button id="copy-detail" type="button" disabled>Copy</button>
      <select id="views" aria-label="Detail view">
        <option value="overview">Overview</option>
        <option value="request">Request</option>
        <option value="response">Response</option>
        <option value="timing">Timing</option>
        <option value="debug">Debug</option>
        <option value="raw">Raw capture</option>
      </select>
    </div>
    <div id="view-tabs" role="tablist" aria-label="Request detail views">
      <button type="button" role="tab" data-view="overview" aria-selected="true">Overview</button>
      <button type="button" role="tab" data-view="request" aria-selected="false">Request</button>
      <button type="button" role="tab" data-view="response" aria-selected="false">Response</button>
      <button type="button" role="tab" data-view="timing" aria-selected="false">Timing</button>
      <button type="button" role="tab" data-view="debug" aria-selected="false">Debug</button>
      <button type="button" role="tab" data-view="raw" aria-selected="false">Raw</button>
    </div>
    <pre id="detail" role="tabpanel" tabindex="0"></pre>
  </section>
</main>
<script>${script}</script>
</body>
</html>`;
