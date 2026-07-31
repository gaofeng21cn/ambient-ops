import { createHash, randomUUID } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { hostname as systemHostname } from "node:os";
import { Bonjour } from "bonjour-service";

export const DISCOVERY_SERVICE_TYPE = "ambient-ops";
export const DISCOVERY_PROTOCOL_VERSION = "1";

export async function resolveInstanceId(dataDir, configuredId = "") {
  const explicit = normalizeInstanceId(configuredId);
  if (explicit) return explicit;

  const path = new URL("instance-id", `file://${dataDir.replace(/\/?$/, "/")}`);
  try {
    const persisted = normalizeInstanceId(await readFile(path, "utf8"));
    if (persisted) return persisted;
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }

  const generated = `ao-${createHash("sha256")
    .update(randomUUID())
    .digest("hex")
    .slice(0, 16)}`;
  await writeFile(path, `${generated}\n`, { mode: 0o600 });
  return generated;
}

export function createDiscoveryPublisher({
  enabled = true,
  instanceId,
  name,
  host,
  port,
  displayPath = "/display/overview",
  apiPath = "/api/v1/status",
  pairingEnabled = true,
  version = "0.1.5",
  bonjour = new Bonjour(),
}) {
  let service = null;

  return {
    start() {
      if (!enabled || service) return;
      service = bonjour.publish({
        name: String(name || "Ambient Ops").slice(0, 63),
        host: normalizeDiscoveryHost(host),
        type: DISCOVERY_SERVICE_TYPE,
        protocol: "tcp",
        port,
        txt: {
          id: instanceId,
          name: String(name || "Ambient Ops").slice(0, 80),
          path: normalizePath(displayPath, "/display/overview"),
          api: normalizePath(apiPath, "/api/v1/status"),
          protocol: DISCOVERY_PROTOCOL_VERSION,
          pairing: pairingEnabled ? "1" : "0",
          version: String(version).slice(0, 32),
        },
      });
    },
    async stop() {
      service?.stop?.();
      service = null;
      await new Promise((resolve) => bonjour.unpublishAll(resolve));
      bonjour.destroy();
    },
  };
}

export function normalizeDiscoveryHost(value, fallback = systemHostname()) {
  const explicitHost = validDiscoveryHost(value);
  const fallbackHost = validDiscoveryHost(fallback);
  const safeHost = explicitHost || fallbackHost || "ambient-ops";
  return safeHost.toLowerCase().endsWith(".local") ? safeHost : `${safeHost}.local`;
}

function validDiscoveryHost(value) {
  const candidate = String(value || "").trim().replace(/\.+$/, "");
  const labels = candidate.split(".");
  return labels.every(
    (label) => label.length > 0
      && label.length <= 63
      && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/i.test(label),
  ) ? candidate : "";
}

export function normalizeInstanceId(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return /^[a-z0-9][a-z0-9._-]{0,79}$/.test(normalized) ? normalized : "";
}

function normalizePath(value, fallback) {
  const path = String(value || fallback).trim();
  return path.startsWith("/") ? path.slice(0, 160) : fallback;
}
