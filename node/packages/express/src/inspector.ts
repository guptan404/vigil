import { desktopCaptures, desktopSessions, isVigilSessionId } from "./sessions.js";
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
  /** App identity shown in the inspector header. SVG is embedded as an image. */
  branding?: { name: string; logoSvg?: string };
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
      `default-src 'none'; script-src 'sha256-${scriptHash}'; style-src 'unsafe-inline'; img-src data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`);
    res.type("html").send(brandedPage(config.branding));
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
    const sessionId = reqSessionId(_req.query.sessionId);
    res.json({
      enabled: simulation?.enabled ?? false,
      requestDebugKeyRequired: simulation?.requiresDebugKey ?? true,
      allowedPaths: [...new Set([...(simulation?.allowedPaths ?? []),
        ...(simulation?.allowCapturedPaths ? capturedPaths(config.sink, sessionId) : [])])],
      failurePoints: simulation?.failurePoints ?? [],
      rules: sessionId ? simulation?.list().filter(rule => rule.sessionId === sessionId) ?? [] : [],
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
      if (!isVigilSessionId(req.body?.sessionId)) {
        res.status(400).json({ error: "Select a frontend session before enabling a rule." });
        return;
      }
      res.status(201).json(config.simulation!.put(req.body,
        capturedPaths(config.sink, req.body.sessionId, req.body.method)));
    } catch (error) {
      res.status(400).json({ error: error instanceof Error ? error.message : "Invalid rule" });
    }
  });
  router.delete("/simulation/:id", (req, res) => {
    const sessionId = reqSessionId(req.query.sessionId);
    const rule = config.simulation!.list().find(item => item.id === req.params.id && item.sessionId === sessionId);
    res.sendStatus(rule && sessionId && config.simulation!.remove(rule.id) ? 204 : 404);
  });
  router.delete("/simulation", (req, res) => {
    const sessionId = reqSessionId(req.query.sessionId);
    if (!sessionId) {
      res.status(400).json({ error: "Select a frontend session before removing rules." });
      return;
    }
    config.simulation!.clear(sessionId);
    res.sendStatus(204);
  });
  router.get("/sessions", authorizeRead, (_req, res) => {
    res.json({ sessions: desktopSessions(desktopCaptures(config.sink)) });
  });
  router.get("/captures", authorizeRead, (_req, res) => {
    const sessionId = reqSessionId(_req.query.sessionId);
    if (!sessionId) {
      res.json({ captures: [] });
      return;
    }
    const captures: string[] = [];
    let bytes = 0;
    for (const capture of desktopCaptures(config.sink)) {
      if (capture.client?.sessionId !== sessionId) continue;
      const encoded = JSON.stringify(capture);
      const size = Buffer.byteLength(encoded);
      if (bytes + size > 2 * 1024 * 1024) continue;
      captures.push(encoded);
      bytes += size;
      if (captures.length >= 200) break;
    }
    res.type("json").send(`{"captures":[${captures.join(",")}]}`);
  });
  return router;
}

function reqSessionId(value: unknown): string | undefined {
  return isVigilSessionId(value) ? value : undefined;
}

function capturedPaths(sink: VigilMemorySink, sessionId?: string, method?: string): string[] {
  if (!sessionId) return [];
  return [...new Set(desktopCaptures(sink).flatMap(({ client, call }) => {
    if (client?.sessionId !== sessionId) return [];
    const request = call.request as { url?: string; method?: string } | undefined;
    if (method && request?.method !== method) return [];
    try {
      const url = new URL(request?.url ?? "");
      return [url.pathname];
    } catch { return []; }
  }))].filter(path => path.startsWith("/") && path !== "/vigil" && !path.startsWith("/vigil/"));
}

function brandedPage(branding?: VigilInspectorConfig["branding"]): string {
  const name = branding?.name ?? "Vigil";
  const escape = (text: string) => text.replace(/[&<>"']/g,
    char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!);
  // Material Icons network_check rounded, also used by Flutter (Google, Apache-2.0).
  const logo = branding?.logoSvg ?? '<svg fill="#137955" xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 0 24 24" width="24"><path d="M0 0h24v24H0V0z" fill="none"/><path d="M15.9 5c-.17 0-.32.09-.41.23l-.07.15-5.18 11.65c-.16.29-.26.61-.26.96 0 1.11.9 2.01 2.01 2.01.96 0 1.77-.68 1.96-1.59l.01-.03L16.4 5.5c0-.28-.22-.5-.5-.5zM2.06 10.06c.51.51 1.33.55 1.89.09 2.76-2.26 6.24-3.18 9.58-2.76l1.19-2.68c-4.35-.78-8.96.3-12.57 3.25-.64.53-.68 1.51-.09 2.1zm19.88 0c.59-.59.55-1.57-.1-2.1-1.36-1.11-2.86-1.95-4.44-2.53l-.53 2.82c1.13.47 2.19 1.09 3.17 1.89.58.46 1.39.43 1.9-.08zm-4.03 4.03c.6-.6.56-1.63-.14-2.12-.46-.33-.94-.61-1.44-.86l-.55 2.92c.11.07.22.14.32.22.57.4 1.33.32 1.81-.16zm-11.83-.01c.5.5 1.27.54 1.85.13.94-.66 2.01-1.06 3.1-1.22l1.28-2.88c-2.13-.06-4.28.54-6.09 1.84-.69.51-.74 1.53-.14 2.13z"/></svg>';
  return page.replace("<!--APP_BRAND-->",
    '<img class="brand-mark" src="data:image/svg+xml;base64,' + Buffer.from(logo).toString("base64") +
    '" alt="' + escape(name) + ' logo"><div><h1>' + escape(name) + '</h1><p>Network inspector</p></div>');
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
let sessions = [];
let selectedSessionId = "";
let selectedCapture;
let detailIdentity = "";
let viewGeneration = 0;
const sessionCards = byId("session-list");
const sessionHeading = byId("session-heading");
const sessionDescription = byId("session-description");
const workspace = byId("workspace");
const sessionActions = byId("session-actions");
const simulationScope = byId("simulation-scope");
const backSessions = byId("back-sessions");
const copySession = byId("copy-session");
const sessionInput = byId("session-id");
const connectSession = byId("connect-session");
let simulationAvailable = false;
let failurePaths = [];

function sessionLabel(session) {
  return session.deviceName || ({
    android: "Android device", ios: "iOS device", web: "Web browser",
    macos: "macOS desktop", windows: "Windows desktop", linux: "Linux desktop",
  })[session.deviceType] || session.deviceType || "Unknown device";
}

function renderSessions() {
  const active = sessions.find(session => session.sessionId === selectedSessionId);
  device.replaceChildren(new Option("Select a session", ""),
    ...sessions.map(session => new Option(
      sessionLabel(session) + " · " + session.sessionId.slice(0, 8), session.sessionId)));
  if (selectedSessionId && !active) {
    device.append(new Option("Waiting · " + selectedSessionId.slice(0, 8), selectedSessionId));
  }
  device.value = selectedSessionId;
  document.body.classList.toggle("session-selected", !!selectedSessionId);
  connectSession.disabled = !readKey;
  query.disabled = !selectedSessionId;
  workspace.hidden = !selectedSessionId;
  sessionCards.hidden = !!selectedSessionId;
  sessionActions.hidden = !selectedSessionId;
  failurePanel.hidden = !selectedSessionId;
  if (active) {
    sessionHeading.textContent = sessionLabel(active);
    sessionDescription.textContent = [
      active.app, active.deviceType, "Session " + active.sessionId,
    ].filter(Boolean).join(" · ");
    simulationScope.textContent = "Applies to " + sessionLabel(active) + " · " + active.sessionId;
    return;
  }
  if (selectedSessionId) {
    sessionHeading.textContent = "Waiting for device session";
    sessionDescription.textContent = "Session " + selectedSessionId;
    simulationScope.textContent = "Applies to session " + selectedSessionId;
    return;
  }
  sessionHeading.textContent = "Device sessions";
  sessionDescription.textContent = readKey
    ? "Choose a session to monitor its requests and test its failure cases."
    : "Connect to monitor your frontend device sessions.";
  sessionCards.replaceChildren(...sessions.map(session => {
    const card = document.createElement("button");
    card.type = "button";
    card.className = "session-card";
    const type = document.createElement("small");
    type.textContent = (session.app || "Frontend") + " · " + session.deviceType;
    const name = document.createElement("strong");
    name.textContent = sessionLabel(session);
    const identity = document.createElement("code");
    identity.textContent = session.sessionId;
    const metrics = document.createElement("span");
    metrics.textContent = session.requestCount + " request(s) · " + session.failedCount + " failed";
    const seen = document.createElement("small");
    seen.textContent = session.lastSeenAt
      ? "Last seen " + new Date(session.lastSeenAt).toLocaleString() : "No recent requests";
    card.append(type, name, identity, metrics, seen);
    card.onclick = () => selectSession(session.sessionId);
    return card;
  }));
  if (!sessions.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = readKey
      ? "Waiting for a frontend session. Make a request in your app to register it here."
      : "Enter the inspector read key to discover sessions.";
    sessionCards.append(empty);
  }
}

function selectSession(id) {
  viewGeneration++;
  selectedSessionId = id;
  sessionInput.value = id;
  selected = "";
  captures = [];
  lastPayload = "";
  simulationPayload = "";
  failurePaths = [];
  failurePointsInitialized = false;
  failureRules.replaceChildren();
  failureStatus.textContent = "";
  failurePanel.open = false;
  query.value = "";
  renderSessions();
  render();
  if (readKey) refresh(generation);
}

sessionInput.oninput = () => sessionInput.setCustomValidity("");
byId("session-connect").onsubmit = event => {
  event.preventDefault();
  if (!readKey) return;
  const id = sessionInput.value.trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(id)) {
    sessionInput.setCustomValidity("Enter a valid session ID copied from Flutter Vigil.");
    sessionInput.reportValidity();
    return;
  }
  sessionInput.setCustomValidity("");
  selectSession(id);
};

backSessions.onclick = () => selectSession("");
copySession.onclick = async () => {
  try {
    await navigator.clipboard.writeText(selectedSessionId);
    copySession.textContent = "Copied";
    setTimeout(() => { copySession.textContent = "Copy session ID"; }, 1500);
  } catch {
    status.textContent = "Select the session ID above to copy it.";
  }
};
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

function scopedPath(suffix, sessionId = selectedSessionId) {
  return apiPath(suffix) + "?sessionId=" + encodeURIComponent(sessionId);
}

function apiPath(suffix) {
  return location.pathname.replace(/\\/$/, "") + suffix;
}

function failureDescription(rule) {
  const effects = {
    mock: "Mock response", httpError: "HTTP error", exception: "Backend exception", delay: "Delay and forward",
    timeout: "Timeout", disconnect: "Disconnect",
  };
  return rule.method + " " + rule.path + (rule.failurePoint ? " · " + rule.failurePoint : "") + " · " + effects[rule.effect] +
    (!rule.failurePoint && ["mock", "httpError", "exception"].includes(rule.effect) ? " " + rule.statusCode : "") +
    (rule.delayMs ? " · " + rule.delayMs + " ms" : "") +
    " · " + (rule.remaining === null ? "until removed" : rule.remaining + " request(s)");
}

function renderFailures(state) {
  simulationAvailable = state.enabled;
  failurePanel.hidden = !selectedSessionId;
  byId("simulation-controls").hidden = !state.enabled;
  byId("simulation-unavailable").hidden = state.enabled;
  byId("request-key-help").hidden = !state.requestDebugKeyRequired;
  byId("rule-count").textContent = state.rules.length ? String(state.rules.length) : "";
  byId("clear-failures").disabled = state.rules.length === 0;
  failurePaths = state.allowedPaths;
  renderFailureRequests();
  const point = byId("failure-point");
  const selectedPoint = point.value;
  const points = state.failurePoints ?? [];
  point.replaceChildren(new Option("Before route", ""),
    ...points.map(name => new Option(name, name)));
  if (points.includes(selectedPoint)) point.value = selectedPoint;
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

function renderFailureRequests() {
  const selector = byId("failure-path");
  const previous = selector.value;
  const options = failurePaths.flatMap(path => {
    const methods = new Set(captures.flatMap(item => {
      if (item.client?.sessionId !== selectedSessionId) return [];
      const request = item.call.request;
      try {
        return new URL(request?.url).pathname === path && typeof request.method === "string"
          ? [request.method] : [];
      } catch { return []; }
    }));
    return [...(methods.size ? methods : [""])].map(method => {
      const option = new Option(method ? method + " " + path : path, JSON.stringify([method, path]));
      option.dataset.path = path;
      option.dataset.method = method;
      return option;
    });
  });
  selector.replaceChildren(...options);
  if (options.some(option => option.value === previous)) selector.value = previous;
  if (selector.value !== previous) syncFailureMethod();
}

function syncFailureMethod() {
  const method = byId("failure-path").selectedOptions[0]?.dataset.method;
  if (method) byId("failure-method").value = method;
}
byId("failure-path").onchange = syncFailureMethod;

async function loadFailures(id, version = viewGeneration) {
  const response = await fetch(scopedPath("/simulation"), {
    headers: { "Vigil-Read-Key": readKey }, cache: "no-store",
  });
  if (!response.ok) throw new Error("Unable to load failure rules.");
  const payload = await response.text();
  if (id !== generation || version !== viewGeneration) return;
  if (payload !== simulationPayload) {
    simulationPayload = payload;
    renderFailures(JSON.parse(payload));
  }
}

let updatingFailure = false;
async function changeFailure(method, path, body) {
  if (updatingFailure) return;
  if (!readKey || !selectedSessionId) {
    failureStatus.textContent = "Connect to the inspector first.";
    return;
  }
  if (!controlKey.value) {
    failureStatus.textContent = "Enter the server simulation control key.";
    return;
  }
  const id = generation;
  const version = viewGeneration;
  updatingFailure = true;
  byId("enable-rule").disabled = true;
  failureStatus.textContent = "Applying change…";
  try {
    const response = await fetch(scopedPath(path), {
      method,
      headers: { "Content-Type": "application/json", "Vigil-Control-Key": controlKey.value },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (id !== generation || version !== viewGeneration) return;
    if (!response.ok) {
      const message = await response.json().catch(() => null);
      throw new Error(message?.error ?? "Unable to change the failure rule.");
    }
    failureStatus.textContent = method === "POST" ? "Rule enabled on the Express server." : "Rule removed.";
    await loadFailures(id, version);
  } catch (error) {
    if (id === generation && version === viewGeneration) failureStatus.textContent = error.message;
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
      sessionId: selectedSessionId,
      method: byId("failure-method").value.trim().toUpperCase(),
      path: byId("failure-path").selectedOptions[0]?.dataset.path ?? "",
      effect,
      delayMs: Number(byId("failure-delay").value),
    };
    const point = byId("failure-point").value;
    if (point) {
      rule.failurePoint = point;
      rule.delayMs = 0;
    }
    if (!point && ["mock", "httpError", "exception"].includes(effect)) rule.statusCode = Number(byId("failure-code").value);
    if (["mock", "httpError"].includes(effect)) rule.body = JSON.parse(byId("failure-body").value);
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
  byId("response-settings").hidden = !["mock", "httpError"].includes(effect);
  byId("status-settings").hidden = !!point || !["mock", "httpError", "exception"].includes(effect);
  byId("failure-code").disabled = !!point || !["mock", "httpError", "exception"].includes(effect);
  byId("failure-code").min = effect === "mock" ? "200" : "400";
  byId("delay-settings").hidden = !!point;
  byId("failure-delay").disabled = !!point;
  byId("point-help").hidden = !point;
  byId("effect-settings").hidden = !!point;
}
byId("failure-point").onchange = updateFailureFields;
byId("failure-effect").onchange = () => {
  const effect = byId("failure-effect").value;
  byId("failure-code").value = effect === "mock" ? "200" : "500";
  byId("failure-delay").value = effect === "timeout" ? "30000" : effect === "delay" ? "1000" : "0";
  updateFailureFields();
};
function configureSelectedRequest(effect) {
  failurePanel.open = true;
  if (!simulationAvailable || !selectedCapture) return;
  const request = selectedCapture.call.request;
  let path;
  try { path = new URL(request?.url).pathname; }
  catch { failureStatus.textContent = "This capture has no valid request URL."; return; }
  const option = [...byId("failure-path").options].find(option =>
    option.dataset.path === path && (!option.dataset.method || option.dataset.method === request.method));
  if (!option) {
    failureStatus.textContent = "This endpoint is not enabled for response controls on this server.";
    return;
  }
  byId("failure-method").value = request.method;
  byId("failure-path").value = option.value;
  byId("failure-point").value = "";
  byId("failure-effect").value = effect;
  byId("failure-code").value = effect === "mock" ? "200" : "500";
  byId("failure-delay").value = "0";
  byId("failure-times").value = "1";
  const summary = selectedCapture.call.response?.body;
  try {
    byId("failure-body").value = JSON.stringify(
      summary?.kind === "json" && summary.text ? JSON.parse(summary.text) : {}, null, 2);
  } catch { byId("failure-body").value = "{}"; }
  failureStatus.textContent = "Choose the response or failure, then enable it for this session’s next request.";
  updateFailureFields();
}
byId("mock-request").onclick = () => configureSelectedRequest("mock");
byId("fail-request").onclick = () => configureSelectedRequest("exception");
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
  return JSON.stringify([item.client?.sessionId, item.call.id, item.call.startedAt]);
}

function render() {
  const terms = query.value.trim().toLowerCase();
  const rows = captures.filter(item => {
    const call = item.call;
    const text = [call.request?.method, call.request?.url, call.response?.statusCode,
      call.trace?.traceId, call.state, clientLabel(item)].join(" ").toLowerCase();
    return item.client?.sessionId === selectedSessionId && text.includes(terms);
  });
  const active = rows.find(item => identity(item) === selected) ?? rows[0];
  selectedCapture = active;
  selected = active ? identity(active) : "";
  renderFailureRequests();
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
    hint.textContent = captures.length ? "Try a different search or device."
      : "Make a request from this device using the same backend. New requests appear automatically.";
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
  byId("mock-request").disabled = !active;
  byId("fail-request").disabled = !active;
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
  const nextIdentity = identity(active) + ":" + views.value;
  const scrollTop = nextIdentity === detailIdentity ? detail.scrollTop : 0;
  const scrollLeft = nextIdentity === detailIdentity ? detail.scrollLeft : 0;
  detail.textContent = section == null ? "No data captured." : JSON.stringify(section, null, 2);
  detail.scrollTop = scrollTop;
  detail.scrollLeft = scrollLeft;
  detailIdentity = nextIdentity;
}

function stop(message) {
  generation++;
  clearTimeout(timer);
  readKey = "";
  lastPayload = "";
  simulationPayload = "";
  failurePaths = [];
  failurePointsInitialized = false;
  failurePanel.hidden = true;
  failureRules.replaceChildren();
  failureStatus.textContent = "";
  controlKey.value = "";
  captures = [];
  sessions = [];
  selectedSessionId = "";
  viewGeneration++;
  simulationAvailable = false;
  selected = "";
  disconnect.disabled = true;
  status.textContent = message;
  status.dataset.connected = "false";
  renderSessions();
  render();
}

async function refresh(id) {
  clearTimeout(timer);
  let version = viewGeneration;
  try {
    const result = await fetch(apiPath("/sessions"), {
      headers: { "Vigil-Read-Key": readKey }, cache: "no-store",
    });
    if (id !== generation || version !== viewGeneration) return;
    if (result.status === 403) {
      stop("Read key rejected.");
      return;
    }
    if (!result.ok) throw new Error("Session request failed");
    sessions = (await result.json()).sessions;
    if (id !== generation || version !== viewGeneration) return;
    renderSessions();
    version = viewGeneration;
    if (selectedSessionId) {
      const selectedVersion = viewGeneration;
      const response = await fetch(scopedPath("/captures"), {
        headers: { "Vigil-Read-Key": readKey }, cache: "no-store",
      });
      if (id !== generation || selectedVersion !== viewGeneration) return;
      if (!response.ok) throw new Error("Capture request failed");
      const payload = await response.text();
      if (id !== generation || selectedVersion !== viewGeneration) return;
      if (payload !== lastPayload) {
        captures = JSON.parse(payload).captures;
        lastPayload = payload;
        render();
      }
      await loadFailures(id, selectedVersion);
    }
    if (id !== generation) return;
    status.textContent = selectedSessionId
      ? captures.length ? captures.length + (captures.length === 1 ? " request" : " requests")
        : "Waiting for this session’s requests"
      : sessions.length + (sessions.length === 1 ? " session" : " sessions");
    status.dataset.connected = "true";
  } catch {
    if (id !== generation || version !== viewGeneration) return;
    status.textContent = "Unable to load sessions. Retrying.";
  }
  if (id === generation && version === viewGeneration) {
    timer = setTimeout(() => refresh(id), 2000);
  }
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
device.onchange = () => selectSession(device.value);
views.onchange = render;
renderSessions();
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
  color-scheme: light;
  font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  --bg: #f5f8f6; --panel: #fff; --raised: #f1f4f2; --ink: #172a23;
  --muted: #61746b; --line: #dce5df; --accent: #137955; --tint: #e4f4eb;
  --error: #bc4242; --success: #0e7630; --focus: #137955;
}
* { box-sizing: border-box; }
[hidden] { display: none !important; }
html, body { margin: 0; height: 100%; }
body { height: 100dvh; overflow: hidden; display: flex; flex-direction: column;
  background: var(--bg); color: var(--ink); font-size: 13px; line-height: 1.5; }
button, input, select, textarea { font: inherit; color: inherit; border: 1px solid var(--line);
  border-radius: 10px; padding: 9px 12px; background: var(--panel); min-height: 38px; }
input, select, textarea { min-width: 0; max-width: 100%; }
input:focus-visible, select:focus-visible, textarea:focus-visible, button:focus-visible,
summary:focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }
button { cursor: pointer; font-weight: 600; }
button:hover:not(:disabled) { background: var(--raised); }
button:disabled { opacity: .4; cursor: default; }
button.primary { background: var(--accent); color: #f9f9f9; border-color: var(--accent); }
button.primary:hover:not(:disabled) { background: #0d6345; }
header { display: flex; flex: none; flex-wrap: wrap; gap: 14px; align-items: center;
  padding: 14px 24px; background: var(--panel); border-bottom: 1px solid var(--line); }
.brand { margin-right: auto; display: flex; gap: 12px; align-items: center; }
.brand-mark { width: 36px; height: 36px; padding: 7px; object-fit: contain;
  border: 1px solid var(--line); border-radius: 10px; background: var(--tint); }
h1 { margin: 0; font-size: 19px; letter-spacing: -.5px; line-height: 1.25; }
.brand p { margin: 2px 0 0; color: var(--muted); font-size: 11px; }
#access { display: flex; flex-wrap: wrap; gap: 8px; }
#key { width: 190px; background: var(--raised); }
nav { flex: none; display: flex; flex-wrap: wrap; gap: 10px; align-items: center; padding: 14px 24px; }
#query { flex: 1; min-width: 180px; }
#device { max-width: 240px; }
#status { color: var(--muted); font-size: 11px; white-space: nowrap; }
#status::before { content: ""; display: inline-block; width: 6px; height: 6px; border-radius: 50%;
  margin-right: 6px; background: #aaa; vertical-align: 1px; }
#status[data-connected="true"]::before { background: var(--success); }
#session-context { flex: none; display: flex; gap: 12px; justify-content: space-between;
  align-items: center; margin: 0 24px 12px; }
#session-description { margin: 3px 0 0; color: var(--muted); font-size: 11px; overflow-wrap: anywhere; }
#session-actions { display: flex; flex-wrap: wrap; gap: 8px; flex-shrink: 0; }
#session-actions button { font-size: 11px; min-height: 34px; }
#session-connect { flex: none; display: flex; flex-wrap: wrap; align-items: end; gap: 8px;
  margin: 0 24px 14px; padding: 12px; background: var(--panel);
  border: 1px solid var(--line); border-radius: 12px; }
#session-connect label { display: grid; gap: 4px; flex: 1; min-width: min(200px, 100%); font-size: 11px; }
#session-id { width: 100%; background: var(--raised); font-family: ui-monospace, monospace; font-size: 12px; }
#session-help { flex-basis: 100%; margin: 0; color: var(--muted); font-size: 11px; }
.session-selected #session-help { display: none; }
.session-selected #session-connect { padding: 8px 12px; }
#session-list { flex: 1; min-height: 0; overflow: auto; overscroll-behavior: contain;
  margin: 0 24px 20px; display: grid; align-content: start;
  grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 12px; }
.session-card { display: grid; gap: 8px; text-align: left; padding: 18px; }
.session-card strong { font-size: 16px; font-weight: 600; }
.session-card code { font-size: 11px; color: var(--muted); overflow-wrap: anywhere; }
.session-card > span { font-size: 12px; }
main { flex: 1; min-height: 0; margin: 0 24px 20px; display: grid;
  grid-template-columns: minmax(250px, 30%) minmax(0, 1fr); grid-template-rows: minmax(0, 1fr);
  overflow: hidden; background: var(--panel); border: 1px solid var(--line); border-radius: 14px; }
#calls { min-height: 0; overflow: auto; overscroll-behavior: contain; scrollbar-gutter: stable;
  border-right: 1px solid var(--line); padding: 8px; }
#calls button { display: grid; gap: 7px; width: 100%; text-align: left; padding: 13px;
  border: 1px solid transparent; border-radius: 10px; margin-bottom: 5px; font-weight: 400; }
#calls button[aria-pressed="true"] { background: var(--raised); border-color: #bad3c4; }
.request-line { display: flex; align-items: center; gap: 8px; }
.method { font: 700 11px ui-monospace, monospace; letter-spacing: .3px; }
.status-code { margin-left: auto; border-radius: 5px; padding: 2px 7px; background: var(--raised); font-size: 11px; }
.failed { color: var(--error); }
.success { color: var(--success); }
.request-url { font-weight: 600; font-size: 12px; overflow-wrap: anywhere; }
small { font-size: 11px; color: var(--muted); }
#request-details { min-width: 0; min-height: 0; display: flex; flex-direction: column; overflow: hidden; }
.detail-toolbar { flex: none; padding: 16px 18px 10px; display: flex; flex-wrap: wrap; align-items: start; gap: 10px; }
.detail-heading { flex: 1; min-width: 160px; }
h2 { margin: 0; font-size: 14px; font-weight: 600; overflow-wrap: anywhere; }
#detail-meta { color: var(--muted); font-size: 11px; margin: 4px 0 0; }
.request-actions { display: flex; flex-wrap: wrap; gap: 6px; }
.request-actions button { min-height: 32px; padding: 6px 9px; font-size: 11px; }
#fail-request { color: var(--error); }
#view-tabs { flex: none; display: flex; overflow-x: auto; border-bottom: 1px solid var(--line); padding: 0 10px; gap: 2px; }
#view-tabs button { background: transparent; border: 0; border-radius: 0; padding: 11px 10px; color: var(--muted); font-size: 12px; }
#view-tabs button[aria-selected="true"] { color: var(--accent); box-shadow: inset 0 -2px var(--accent); }
#views { display: none; }
#detail { flex: 1; min-height: 0; overflow: auto; overscroll-behavior: contain; scrollbar-gutter: stable; }
pre { padding: 18px; margin: 0; white-space: pre-wrap; overflow-wrap: anywhere;
  font: 12px/1.8 ui-monospace, "SFMono-Regular", Consolas, monospace; tab-size: 2; }
.empty-state { padding: 36px 20px; text-align: center; color: var(--muted); }
.empty-state strong { color: var(--ink); font-weight: 600; }
.empty-state p { font-size: 12px; max-width: 250px; margin: 8px auto; }
#failures { flex: none; }
#failures summary { cursor: pointer; font-size: 12px; font-weight: 600; background: var(--panel);
  border: 1px solid var(--line); border-radius: 10px; padding: 9px 12px; }
#rule-count:not(:empty) { margin-left: 4px; background: var(--tint); padding: 1px 6px; border-radius: 5px; }
#failures[open] { position: fixed; top: 20px; right: 20px; width: min(460px, calc(100vw - 32px));
  max-height: calc(100dvh - 40px); overflow: auto; overscroll-behavior: contain; background: var(--panel);
  border: 1px solid var(--line); border-radius: 14px; box-shadow: 0 15px 70px #0002; z-index: 5; }
#failures[open] summary { position: sticky; top: 0; border: 0; border-bottom: 1px solid var(--line);
  border-radius: 0; padding: 18px; font-size: 15px; z-index: 1; }
#failures[open] summary::after { content: "×"; float: right; font-size: 20px; line-height: 20px; color: var(--muted); }
.panel-body { padding: 18px; }
.panel-body > p:first-child { margin-top: 0; }
.panel-body p { color: var(--muted); font-size: 12px; line-height: 1.65; }
#simulation-scope { overflow-wrap: anywhere; padding-bottom: 12px; border-bottom: 1px solid var(--line); }
#failures label { display: grid; gap: 6px; font-size: 12px; font-weight: 500; }
#failure-form { display: grid; grid-template-columns: 1fr 1fr; gap: 14px 12px; margin: 18px 0 14px; }
#response-settings, #enable-rule { grid-column: 1 / -1; }
#failure-body { width: 100%; font-family: ui-monospace, monospace; font-size: 12px; resize: vertical; }
#failure-rules { list-style: none; padding: 0; margin: 14px 0; }
#failure-rules li { display: flex; gap: 10px; align-items: center; padding: 12px;
  border: 1px solid var(--line); border-radius: 10px; background: var(--raised); margin-bottom: 8px; }
.rule-description { flex: 1; min-width: 0; overflow-wrap: anywhere; font-size: 12px; }
#failure-rules button { font-size: 11px; min-height: 30px; padding: 5px 8px; }
#failure-status { color: var(--ink); }
#clear-failures { width: 100%; font-size: 12px; }
@media (max-width: 700px) {
  header { padding: 10px 14px; gap: 10px; }
  .brand-mark { width: 30px; height: 30px; }
  .brand p { display: none; }
  #access { gap: 5px; }
  #key { width: 150px; }
  #access button { font-size: 11px; padding: 7px; }
  nav { padding: 10px 14px; gap: 6px; }
  #query { min-width: 130px; }
  #device { max-width: 48%; }
  #status { font-size: 10px; }
  #session-context, #session-connect { margin: 0 14px 10px; }
  #session-description { font-size: 10px; }
  #session-actions { gap: 5px; }
  #session-actions button { padding: 6px; font-size: 10px; }
  #session-connect label { min-width: 140px; }
  #session-list { margin: 0 14px 14px; }
  main { margin: 0 14px 14px; grid-template-columns: minmax(0, 1fr);
    grid-template-rows: minmax(100px, 32%) minmax(0, 1fr); }
  #calls { border-right: 0; border-bottom: 1px solid var(--line); }
  .detail-toolbar { padding: 10px 12px 6px; gap: 6px; }
  #view-tabs { padding: 0 4px; }
  #view-tabs button { padding: 8px; font-size: 11px; }
  pre { padding: 12px; font-size: 11px; }
  #failures[open] { top: 16px; right: 16px; max-height: calc(100dvh - 32px); }
}
@media (max-height: 600px) and (min-width: 701px) {
  header { padding-top: 8px; padding-bottom: 8px; }
  nav { padding-top: 8px; padding-bottom: 8px; }
  .session-selected #session-connect { display: none; }
}
</style>
</head>
<body>
<header>
  <div class="brand"><!--APP_BRAND--></div>
  <form id="access">
    <input id="key" type="password" aria-label="Inspector read key" placeholder="Inspector read key" autocomplete="off" required>
    <button class="primary">Connect</button>
    <button id="disconnect" type="button" disabled>Disconnect</button>
  </form>
</header>
<nav aria-label="Capture filters">
  <input id="query" type="search" aria-label="Search captures" placeholder="Search URL, method, status, or trace ID">
  <select id="device" aria-label="Frontend session"></select>
  <span id="status" role="status">Disconnected.</span>
<details id="failures" hidden>
  <summary>Response controls <span id="rule-count"></span></summary>
  <div class="panel-body">
  <p id="simulation-scope"></p>
  <p id="simulation-unavailable" hidden>Response controls are not configured on this server. A server control key and simulation controller are required.</p>
  <div id="simulation-controls">
  <p>Mock a response or fail a request for the selected session. Other devices keep using the real API.</p>
  <p id="request-key-help">This server also requires the app’s Vigil debug key on API requests before a rule can apply.</p>
  <label>Simulation control key
    <input id="control-key" type="password" autocomplete="off" placeholder="Server control key">
  </label>
  <form id="failure-form">
    <label>Method <input id="failure-method" value="GET" required pattern="[A-Za-z]+" maxlength="20"></label>
    <label>Request <select id="failure-path" required></select></label>
    <label>Failure location <select id="failure-point">
      <option value="">Before route</option>
    </select></label>
    <label id="effect-settings">Effect <select id="failure-effect">
      <option value="mock">Mock response</option>
      <option value="httpError">HTTP error response</option>
      <option value="exception">Backend exception</option>
      <option value="delay">Delay and forward</option>
      <option value="timeout">Timeout</option>
      <option value="disconnect">Disconnect</option>
    </select></label>
    <label id="status-settings">Response status <input id="failure-code" type="number" min="200" max="599" value="200" required></label>
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
  </div>
</details>
</nav>
<section id="session-context" aria-label="Session overview">
  <div><h2 id="session-heading">Device sessions</h2><p id="session-description"></p></div>
  <div id="session-actions" hidden>
    <button id="copy-session" type="button">Copy session ID</button>
    <button id="back-sessions" type="button">All sessions</button>
  </div>
</section>
<form id="session-connect" aria-label="Connect to a device session">
  <label>Session ID
    <input id="session-id" placeholder="Paste session ID from Flutter Vigil" autocomplete="off" spellcheck="false"
      aria-describedby="session-help" required maxlength="128">
  </label>
  <button id="connect-session" type="submit" class="primary" disabled>Connect to session</button>
  <p id="session-help">Connect with your inspector read key above, then paste the session ID copied from Flutter Vigil.
    You can connect before the device’s first upload, or choose a discovered session below.</p>
</form>
<section id="session-list" aria-label="Device sessions"></section>
<main id="workspace" hidden>
  <div id="calls" aria-label="Captured requests"></div>
  <section id="request-details" aria-label="Request details">
    <div class="detail-toolbar">
      <div class="detail-heading"><h2 id="detail-title">Request details</h2>
        <p id="detail-meta"></p>
      </div>
      <div class="request-actions">
        <button id="mock-request" type="button" disabled>Mock response</button>
        <button id="fail-request" type="button" disabled>Fail request</button>
        <button id="copy-detail" type="button" disabled>Copy</button>
      </div>
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
