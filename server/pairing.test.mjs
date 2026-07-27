import assert from "node:assert/strict";
import {
  createHash,
  generateKeyPairSync,
  randomBytes,
  sign,
} from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  DevicePairingStore,
  signingInput,
  verificationCode,
} from "./pairing.mjs";

test("requires approval, persists only public device material, and reloads it", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-pairing-"));
  try {
    const keys = keyPair();
    const now = new Date("2026-07-26T00:00:00.000Z");
    const store = new DevicePairingStore(dataDir, { now: () => now });
    await store.load();

    const pending = await store.request(pairingPayload(keys.publicKey));
    assert.equal(pending.status, "pending");
    assert.equal(pending.verificationCode, verificationCode(keys.publicKey));
    assert.match(pending.approvalPath, /^\/pair\/[a-zA-Z0-9_-]{32,80}$/);

    const approved = await store.approve(pending.requestId, pending.verificationCode);
    assert.equal(approved.status, "approved");
    assert.equal(store.pairedDeviceCount, 1);

    const savedText = await readFile(store.path, "utf8");
    const saved = JSON.parse(savedText);
    assert.equal(saved.devices[0].publicKey, keys.publicKey);
    assert.equal(savedText.includes(keys.privateKey), false);
    assert.equal(savedText.includes("agent_push_token"), false);

    const reloaded = new DevicePairingStore(dataDir, { now: () => now });
    await reloaded.load();
    assert.equal(reloaded.pairedDeviceCount, 1);
    assert.deepEqual(reloaded.pairedIdentity("windows-pc"), {
      machineId: "windows-pc",
      machineName: "Windows PC",
      platform: "Windows",
    });
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("keeps the approved machine name when the same key requests pairing again", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-pairing-"));
  try {
    const keys = keyPair();
    const store = new DevicePairingStore(dataDir);
    await store.load();
    await store.request(pairingPayload(keys.publicKey), { preauthorized: true });

    const repeated = await store.request({
      ...pairingPayload(keys.publicKey),
      machineName: "Untrusted rename",
    });
    assert.equal(repeated.status, "approved");
    assert.equal(repeated.machineName, "Windows PC");
    assert.equal(store.pairedIdentity("windows-pc").machineName, "Windows PC");
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("accepts a signed snapshot once and rejects replay or tampering", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-signature-"));
  try {
    const keys = keyPair();
    const now = new Date("2026-07-26T00:00:00.000Z");
    const store = new DevicePairingStore(dataDir, { now: () => now });
    await store.load();
    const pairing = await store.request(pairingPayload(keys.publicKey), { preauthorized: true });
    assert.equal(pairing.status, "approved");

    const body = Buffer.from('{"schemaVersion":2,"oneMinute":{"tps":17}}');
    const timestamp = String(Math.floor(now.valueOf() / 1000));
    const nonce = randomBytes(18).toString("base64url");
    const pathname = "/api/v1/agents/windows-pc/snapshot";
    const signature = sign(
      "sha256",
      signingInput({ method: "POST", pathname, timestamp, nonce, body }),
      keys.privateKeyObject,
    ).toString("base64");
    const request = {
      machineId: "windows-pc",
      method: "POST",
      pathname,
      body,
      authorization: "AmbientKey windows-pc",
      timestamp,
      nonce,
      signature,
    };

    assert.equal(store.authorizeRequest(request), true);
    assert.equal(store.authorizeRequest(request), false);
    assert.equal(store.authorizeRequest({ ...request, nonce: randomBytes(18).toString("base64url"), body: Buffer.from("{}") }), false);

    const petBody = Buffer.from("signed-pet-asset");
    const petNonce = randomBytes(18).toString("base64url");
    const petPath = "/api/v1/agents/windows-pc/pets/asset-hash";
    const petRequest = {
      ...request,
      method: "PUT",
      pathname: petPath,
      body: petBody,
      nonce: petNonce,
      signature: sign(
        "sha256",
        signingInput({
          method: "PUT",
          pathname: petPath,
          timestamp,
          nonce: petNonce,
          body: petBody,
        }),
        keys.privateKeyObject,
      ).toString("base64"),
    };
    assert.equal(store.authorizeRequest(petRequest), true);
    assert.equal(store.authorizeRequest(petRequest), false);
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("rejects expired pairing requests and wrong verification codes", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-expired-pairing-"));
  try {
    let now = new Date("2026-07-26T00:00:00.000Z");
    const keys = keyPair();
    const store = new DevicePairingStore(dataDir, {
      now: () => now,
      requestTtlMs: 1000,
    });
    await store.load();
    const pending = await store.request(pairingPayload(keys.publicKey));
    await assert.rejects(
      store.approve(pending.requestId, "000000"),
      /Verification code does not match/,
    );
    now = new Date(now.valueOf() + 1001);
    assert.equal(store.get(pending.requestId), null);
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

function keyPair() {
  const { publicKey, privateKey } = generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
  });
  return {
    publicKey: publicKey.export({ format: "der", type: "spki" }).toString("base64"),
    privateKey: privateKey.export({ format: "der", type: "pkcs8" }).toString("base64"),
    privateKeyObject: privateKey,
  };
}

function pairingPayload(publicKey) {
  return {
    schemaVersion: 1,
    machineId: "windows-pc",
    machineName: "Windows PC",
    platform: "Windows",
    publicKey,
    fingerprint: createHash("sha256").update(Buffer.from(publicKey, "base64")).digest("hex"),
  };
}
