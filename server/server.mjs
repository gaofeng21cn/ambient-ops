import { createServer } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";
import { StatusStore } from "./store.mjs";
import { buildDashboard, normalizeSnapshot } from "./status-model.mjs";
import { pollUnifi } from "./unifi.mjs";
import { updateDemo } from "./demo.mjs";
import { HomeAssistantBridge } from "./home-assistant.mjs";
import { renderPrometheus } from "./prometheus.mjs";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const dist = join(root, "dist");
const config = {
  port: numberEnv("PORT", 8787),
  dataDir: process.env.DATA_DIR || join(root, "data"),
  demo: booleanEnv("DEMO_MODE", !process.env.UNIFI_API_KEY),
  siteName: String(process.env.SITE_NAME || "Ambient Ops").slice(0, 80),
  displayTimeZone: String(process.env.DISPLAY_TIME_ZONE || "Asia/Shanghai").slice(0, 80),
  pushToken: process.env.AGENT_PUSH_TOKEN || "",
  unifiBaseUrl: process.env.UNIFI_BASE_URL || "",
  unifiSite: process.env.UNIFI_SITE || "default",
  unifiApiKey: process.env.UNIFI_API_KEY || "",
  allowSelfSigned: booleanEnv("UNIFI_ALLOW_SELF_SIGNED", false),
  unifiCaFile: process.env.UNIFI_CA_FILE || "",
  unifiPollMs: numberEnv("UNIFI_POLL_MS", 3000),
  liveAfterSeconds: numberEnv("LIVE_AFTER_SECONDS", 30),
  staleAfterSeconds: numberEnv("STALE_AFTER_SECONDS", 300),
  haEnabled: booleanEnv("HA_ENABLED", false),
  haBaseUrl: process.env.HA_BASE_URL || "",
  haToken: process.env.HA_TOKEN || "",
  haEntityPrefix: process.env.HA_ENTITY_PREFIX || "ambient_ops",
  haSyncMs: numberEnv("HA_SYNC_MS", 30_000),
  haTimeoutMs: numberEnv("HA_TIMEOUT_MS", 5000),
};

const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"],
  [".png", "image/png"],
]);
const store = new StatusStore(config.dataDir);
await store.load();
if (config.demo) updateDemo(store);
const unifiCa = config.unifiCaFile ? await readFile(config.unifiCaFile) : undefined;
const haBridge = new HomeAssistantBridge({
  enabled: config.haEnabled,
  baseUrl: config.haBaseUrl,
  token: config.haToken,
  entityPrefix: config.haEntityPrefix,
  timeoutMs: config.haTimeoutMs,
});

function dashboard() {
  return {
    site: { name: config.siteName, timeZone: config.displayTimeZone },
    ...buildDashboard({
      machines: store.machines,
      network: store.network,
      history: store.networkHistory,
      demo: config.demo,
    }, config),
  };
}

let polling = false;
async function updateSources() {
  if (config.demo) {
    updateDemo(store);
    return;
  }
  if (!config.unifiApiKey || polling) return;
  polling = true;
  try {
    const network = await pollUnifi({
      baseUrl: config.unifiBaseUrl,
      site: config.unifiSite,
      apiKey: config.unifiApiKey,
      allowSelfSigned: config.allowSelfSigned,
      ca: unifiCa,
    });
    await store.setNetwork(network);
  } catch (error) {
    await store.setNetwork({
      ...store.network,
      status: store.network.updatedAt ? "stale" : "error",
      source: "unifi",
      error: error.message,
    }, { recordHistory: false });
  } finally {
    polling = false;
  }
}
const sourceTimer = setInterval(updateSources, Math.max(1000, config.unifiPollMs));
sourceTimer.unref();
updateSources();

async function syncHomeAssistant() {
  await haBridge.sync(dashboard());
}
const haTimer = setInterval(syncHomeAssistant, Math.max(5000, config.haSyncMs));
haTimer.unref();
syncHomeAssistant();

const server = createServer(async (request, response) => {
  const url = new URL(request.url || "/", `http://${request.headers.host || "localhost"}`);
  try {
    if (request.method === "GET" && url.pathname === "/healthz") {
      const current = dashboard();
      return json(response, 200, {
        ok: true,
        mode: config.demo ? "demo" : "live",
        status: current.overallStatus,
        network: current.network.status,
        codex: current.codex.status,
        machines: current.codex.machineCount,
        homeAssistant: haBridge.health(),
      });
    }
    if (request.method === "GET" && url.pathname === "/api/status") {
      return json(response, 200, dashboard());
    }
    if (request.method === "GET" && url.pathname === "/metrics") {
      return text(response, 200, renderPrometheus(dashboard()), "text/plain; version=0.0.4; charset=utf-8");
    }
    const pushMatch = request.method === "POST" && url.pathname.match(/^\/api\/v1\/agents\/([a-zA-Z0-9._-]{1,80})\/snapshot$/);
    if (pushMatch) {
      if (!config.pushToken) return json(response, 503, { error: "Agent push is not configured" });
      if (!authorized(request, config.pushToken)) return json(response, 401, { error: "Unauthorized" });
      const body = await readJson(request, 64 * 1024);
      const snapshot = normalizeSnapshot(pushMatch[1], body);
      await store.setMachine(snapshot);
      return json(response, 202, { accepted: true, machineId: snapshot.machineId, generatedAt: snapshot.generatedAt });
    }
    if (url.pathname.startsWith("/api/")) return json(response, 404, { error: "Not found" });
    if (request.method !== "GET" && request.method !== "HEAD") return json(response, 405, { error: "Method not allowed" });
    return serveApp(url.pathname, response, request.method === "HEAD");
  } catch (error) {
    const statusCode = error.statusCode || 500;
    if (statusCode >= 500) console.error(error);
    return json(response, statusCode, { error: statusCode >= 500 ? "Internal server error" : error.message });
  }
});

server.listen(config.port, "0.0.0.0", () => {
  console.log(`Ambient Ops listening on http://0.0.0.0:${config.port}`);
  console.log(`Mode: ${config.demo ? "demo" : "live"}`);
});

async function shutdown(signal) {
  console.log(`Received ${signal}, shutting down`);
  clearInterval(sourceTimer);
  clearInterval(haTimer);
  server.close();
  try { await store.flush(); } finally { process.exit(0); }
}
process.once("SIGTERM", () => shutdown("SIGTERM"));
process.once("SIGINT", () => shutdown("SIGINT"));

function authorized(request, token) {
  const header = request.headers.authorization || "";
  const expected = Buffer.from(`Bearer ${token}`);
  const actual = Buffer.from(header);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

async function readJson(request, limit) {
  let body = "";
  for await (const chunk of request) {
    body += chunk;
    if (Buffer.byteLength(body) > limit) throw httpError(413, "Payload too large");
  }
  let parsed;
  try { parsed = JSON.parse(body); } catch { throw httpError(400, "Invalid JSON"); }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw httpError(400, "JSON body must be an object");
  return parsed;
}

async function serveApp(pathname, response, headOnly) {
  const requested = pathname === "/" || pathname.startsWith("/display/") ? "index.html" : pathname.slice(1);
  const relative = normalize(requested).replace(/^(\.\.(\/|\\|$))+/, "");
  let path = join(dist, relative);
  try {
    if (!(await stat(path)).isFile()) throw new Error("not a file");
  } catch {
    path = join(dist, "index.html");
  }
  const body = await readFile(path);
  response.writeHead(200, {
    "content-type": contentTypes.get(extname(path)) || "application/octet-stream",
    "cache-control": extname(path) === ".html" ? "no-store" : "public, max-age=31536000, immutable",
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
    "x-frame-options": "SAMEORIGIN",
  });
  response.end(headOnly ? undefined : body);
}

function json(response, statusCode, payload) {
  response.writeHead(statusCode, responseHeaders("application/json; charset=utf-8"));
  response.end(JSON.stringify(payload));
}

function text(response, statusCode, body, contentType) {
  response.writeHead(statusCode, responseHeaders(contentType));
  response.end(body);
}

function responseHeaders(contentType) {
  return {
    "content-type": contentType,
    "cache-control": "no-store",
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
    "x-frame-options": "SAMEORIGIN",
  };
}

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function numberEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
}

function booleanEnv(name, fallback) {
  const value = process.env[name];
  return value == null ? fallback : ["1", "true", "yes", "on"].includes(value.toLowerCase());
}
