import { createServer } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";
import { StatusStore } from "./store.mjs";
import { buildDashboard, normalizeSnapshot } from "./status-model.mjs";
import { pollUnifi } from "./unifi.mjs";
import { createUnifiSnmpPoller } from "./unifi-snmp.mjs";
import { updateDemo } from "./demo.mjs";
import { HomeAssistantBridge } from "./home-assistant.mjs";
import { renderPrometheus } from "./prometheus.mjs";
import { createDiscoveryPublisher, resolveInstanceId } from "./discovery.mjs";
import packageMetadata from "../package.json" with { type: "json" };

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const dist = join(root, "dist");
const config = {
  port: numberEnv("PORT", 8787),
  dataDir: process.env.DATA_DIR || join(root, "data"),
  demo: booleanEnv("DEMO_MODE", !process.env.UNIFI_API_KEY && !process.env.UNIFI_SNMP_HOST),
  siteName: String(process.env.SITE_NAME || "Ambient Ops").slice(0, 80),
  displayTimeZone: String(process.env.DISPLAY_TIME_ZONE || "Asia/Shanghai").slice(0, 80),
  discoveryEnabled: booleanEnv("DISCOVERY_ENABLED", true),
  instanceId: process.env.INSTANCE_ID || "",
  pushToken: secretEnv("AGENT_PUSH_TOKEN", "AGENT_PUSH_TOKEN_KEYCHAIN_SERVICE"),
  unifiBaseUrl: process.env.UNIFI_BASE_URL || "",
  unifiSite: process.env.UNIFI_SITE || "default",
  unifiApiKey: secretEnv("UNIFI_API_KEY"),
  allowSelfSigned: booleanEnv("UNIFI_ALLOW_SELF_SIGNED", false),
  unifiCaFile: process.env.UNIFI_CA_FILE || "",
  unifiPollMs: numberEnv("UNIFI_POLL_MS", 250),
  unifiRateWindowMs: numberEnv("UNIFI_RATE_WINDOW_MS", 2000),
  snmpHost: process.env.UNIFI_SNMP_HOST || "",
  snmpPort: numberEnv("UNIFI_SNMP_PORT", 161),
  snmpUser: process.env.UNIFI_SNMP_USER || "",
  snmpAuthPassword: secretEnv("UNIFI_SNMP_AUTH_PASSWORD", "UNIFI_SNMP_PASSWORD_KEYCHAIN_SERVICE"),
  snmpPrivPassword: secretEnv("UNIFI_SNMP_PRIV_PASSWORD", "UNIFI_SNMP_PASSWORD_KEYCHAIN_SERVICE"),
  snmpAuthProtocol: process.env.UNIFI_SNMP_AUTH_PROTOCOL || "sha",
  snmpPrivProtocol: process.env.UNIFI_SNMP_PRIV_PROTOCOL || "aes",
  snmpInterfaces: listEnv("UNIFI_SNMP_INTERFACES"),
  snmpTimeoutMs: numberEnv("UNIFI_SNMP_TIMEOUT_MS", 3000),
  liveAfterSeconds: numberEnv("LIVE_AFTER_SECONDS", 30),
  staleAfterSeconds: numberEnv("STALE_AFTER_SECONDS", 300),
  haEnabled: booleanEnv("HA_ENABLED", false),
  haBaseUrl: process.env.HA_BASE_URL || "",
  haToken: secretEnv("HA_TOKEN"),
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
await pruneStaleMachines();
const instanceId = await resolveInstanceId(config.dataDir, config.instanceId);
if (config.demo) updateDemo(store);
const unifiCa = config.unifiCaFile ? await readFile(config.unifiCaFile) : undefined;
const snmpEnabled = Boolean(
  config.snmpHost
  && config.snmpUser
  && config.snmpAuthPassword
  && config.snmpInterfaces.length
);
const pollUnifiSnmp = snmpEnabled ? createUnifiSnmpPoller({
  host: config.snmpHost,
  port: config.snmpPort,
  user: config.snmpUser,
  authPassword: config.snmpAuthPassword,
  privPassword: config.snmpPrivPassword,
  authProtocol: config.snmpAuthProtocol,
  privProtocol: config.snmpPrivProtocol,
  interfaces: config.snmpInterfaces,
  timeoutMs: config.snmpTimeoutMs,
  pollMs: config.unifiPollMs,
  rateWindowMs: config.unifiRateWindowMs,
}) : null;
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
  if ((!pollUnifiSnmp && !config.unifiApiKey) || polling) return;
  polling = true;
  try {
    const network = pollUnifiSnmp
      ? await pollUnifiSnmp()
      : await pollUnifi({
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
      source: pollUnifiSnmp ? "unifi-snmp-v3" : "unifi",
      error: error.message,
    }, { recordHistory: false });
  } finally {
    polling = false;
  }
}
const sourceIntervalMs = pollUnifiSnmp
  ? Math.max(200, config.unifiPollMs)
  : Math.max(1000, config.unifiPollMs);
const sourceTimer = setInterval(updateSources, sourceIntervalMs);
sourceTimer.unref();
updateSources();

const machinePruneTimer = setInterval(pruneStaleMachines, Math.min(30_000, config.staleAfterSeconds * 1000));
machinePruneTimer.unref();

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

const discovery = createDiscoveryPublisher({
  enabled: config.discoveryEnabled,
  instanceId,
  name: config.siteName,
  port: config.port,
  version: packageMetadata.version,
});
server.listen(config.port, "0.0.0.0", () => {
  console.log(`Ambient Ops listening on http://0.0.0.0:${config.port}`);
  console.log(`Mode: ${config.demo ? "demo" : "live"}`);
  discovery.start();
  if (config.discoveryEnabled) {
    console.log(`Discovery: ${instanceId}._ambient-ops._tcp.local`);
  }
});

async function shutdown(signal) {
  console.log(`Received ${signal}, shutting down`);
  clearInterval(sourceTimer);
  clearInterval(machinePruneTimer);
  clearInterval(haTimer);
  server.close();
  try {
    await Promise.all([store.flush(), discovery.stop()]);
  } finally {
    process.exit(0);
  }
}

async function pruneStaleMachines() {
  const cutoff = new Date(Date.now() - config.staleAfterSeconds * 1000);
  const removed = await store.pruneMachines(cutoff);
  if (removed.length) console.log(`Retired inactive machines: ${removed.join(", ")}`);
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

function listEnv(name) {
  return String(process.env[name] || "").split(",").map((value) => value.trim()).filter(Boolean);
}

function secretEnv(name, keychainServiceName) {
  const value = process.env[name];
  if (value) return value;
  const secretFile = process.env[`${name}_FILE`];
  if (secretFile) {
    try {
      return readFileSync(secretFile, "utf8").trim();
    } catch {
      return "";
    }
  }
  const service = process.env[keychainServiceName];
  if (!service || process.platform !== "darwin") return "";
  const account = process.env.KEYCHAIN_ACCOUNT || process.env.USER;
  if (!account) return "";
  try {
    return execFileSync("/usr/bin/security", [
      "find-generic-password", "-a", account, "-s", service, "-w",
    ], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    return "";
  }
}
