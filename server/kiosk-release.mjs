import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import { join } from "node:path";

export const KIOSK_UPDATE_PATH = "/api/v1/kiosk/update";
export const KIOSK_RELEASE_PATH_PREFIX = "/api/v1/kiosk/releases/";

export class KioskReleaseStore {
  constructor(directory) {
    this.directory = directory;
    this.current = null;
  }

  async load() {
    let raw;
    try {
      raw = await readFile(join(this.directory, "kiosk-update.json"), "utf8");
    } catch (error) {
      if (error.code === "ENOENT") {
        this.current = null;
        return;
      }
      throw error;
    }

    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new Error("Kiosk update manifest is not valid JSON");
    }
    const manifest = validateManifest(parsed);
    const artifactPath = join(this.directory, manifest.artifact);
    const artifactStat = await stat(artifactPath);
    if (!artifactStat.isFile()) throw new Error("Kiosk update artifact is not a file");
    const actualSha256 = sha256(await readFile(artifactPath));
    if (actualSha256 !== manifest.sha256) {
      throw new Error("Kiosk update artifact SHA-256 does not match its manifest");
    }

    this.current = {
      manifest: Object.freeze({
        versionCode: manifest.versionCode,
        versionName: manifest.versionName,
        apkPath: `${KIOSK_RELEASE_PATH_PREFIX}${manifest.artifact}`,
        sha256: manifest.sha256,
        signerSha256: manifest.signerSha256,
      }),
      artifactPath,
      artifactSize: artifactStat.size,
    };
  }

  get manifest() {
    return this.current?.manifest || null;
  }

  matchesArtifact(pathname) {
    return this.current?.manifest.apkPath === pathname;
  }

  async readArtifact() {
    if (!this.current) return null;
    return readFile(this.current.artifactPath);
  }

  get artifactSize() {
    return this.current?.artifactSize || 0;
  }
}

export function validateManifest(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Kiosk update manifest must be an object");
  }
  const versionCode = Number(value.versionCode);
  if (!Number.isSafeInteger(versionCode) || versionCode <= 0) {
    throw new Error("Kiosk update versionCode must be a positive integer");
  }
  const versionName = String(value.versionName || "");
  if (!/^[a-zA-Z0-9._-]{1,40}$/.test(versionName)) {
    throw new Error("Kiosk update versionName is invalid");
  }
  const artifact = String(value.artifact || "");
  if (!/^[a-zA-Z0-9._-]+\.apk$/.test(artifact)) {
    throw new Error("Kiosk update artifact name is invalid");
  }
  const sha = normalizeSha256(value.sha256, "artifact");
  const signer = normalizeSha256(value.signerSha256, "signer");
  return {
    versionCode,
    versionName,
    artifact,
    sha256: sha,
    signerSha256: signer,
  };
}

function normalizeSha256(value, label) {
  const normalized = String(value || "").trim().toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(normalized)) {
    throw new Error(`Kiosk update ${label} SHA-256 is invalid`);
  }
  return normalized;
}

function sha256(body) {
  return createHash("sha256").update(body).digest("hex");
}
