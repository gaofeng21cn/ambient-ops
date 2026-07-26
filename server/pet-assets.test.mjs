import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  authorizedBearer,
  LEGACY_PET_HASH,
  LEGACY_PET_URL,
  missingPetAssets,
  PetAssetStore,
  petAssetUrl,
  validatePetUpload,
} from "./pet-assets.mjs";

const fixturePath = new URL("../public/pets/ledger-owl/spritesheet.webp", import.meta.url);

test("stores a validated pet asset atomically and deduplicates by content hash", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-pets-"));
  try {
    const body = await readFile(fixturePath);
    const hash = sha256(body);
    const assets = new PetAssetStore(dataDir);
    await assets.load();

    const first = await assets.put(hash, body);
    const second = await assets.put(hash, body);

    assert.equal(first.created, true);
    assert.equal(second.created, false);
    assert.deepEqual(await assets.read(hash), body);
    assert.equal((await readFile(join(dataDir, "pets", `${hash}.webp`))).equals(body), true);
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("loads valid persisted assets and ignores corrupt content-addressed files", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-pets-"));
  try {
    const body = await readFile(fixturePath);
    const hash = sha256(body);
    const first = new PetAssetStore(dataDir);
    await first.load();
    await first.put(hash, body);

    const reloaded = new PetAssetStore(dataDir);
    await reloaded.load();

    assert.equal(reloaded.has(hash), true);
    assert.equal(reloaded.has("a".repeat(64)), false);
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("rejects hash mismatches, malformed WebP, and oversized assets", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-pets-"));
  try {
    const body = await readFile(fixturePath);
    const assets = new PetAssetStore(dataDir, { maxBytes: body.length });
    await assets.load();

    await assert.rejects(
      assets.put("a".repeat(64), body),
      (error) => error.statusCode === 422 && /SHA-256/.test(error.message),
    );
    await assert.rejects(
      assets.put(sha256(Buffer.from("not webp")), Buffer.from("not webp")),
      (error) => error.statusCode === 422 && /WebP/.test(error.message),
    );
    const wrongDimensions = Buffer.from(body);
    wrongDimensions.writeUInt32LE(0, 21);
    await assert.rejects(
      assets.put(sha256(wrongDimensions), wrongDimensions),
      (error) => error.statusCode === 422 && /1536x1872/.test(error.message),
    );
    const oversized = Buffer.alloc(body.length + 1);
    await assert.rejects(
      assets.put(sha256(oversized), oversized),
      (error) => error.statusCode === 413,
    );
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("requires bearer authentication and the current machine pet manifest", () => {
  const hash = "a".repeat(64);
  const machine = { machineId: "mac", pet: { id: "lab-owl", assetHash: hash } };

  assert.equal(authorizedBearer("Bearer secret", "secret"), true);
  assert.equal(authorizedBearer("Bearer wrong", "secret"), false);
  assert.equal(authorizedBearer("", "secret"), false);
  assert.doesNotThrow(() => validatePetUpload({
    machine,
    machineId: "mac",
    hash,
    contentType: "image/webp",
    contentEncoding: "",
  }));
  assert.throws(
    () => validatePetUpload({ machine, machineId: "other", hash, contentType: "image/webp" }),
    (error) => error.statusCode === 409,
  );
  assert.throws(
    () => validatePetUpload({ machine, machineId: "mac", hash, contentType: "image/png" }),
    (error) => error.statusCode === 415,
  );
  assert.throws(
    () => validatePetUpload({
      machine,
      machineId: "mac",
      hash,
      contentType: "image/webp",
      contentEncoding: "gzip",
    }),
    (error) => error.statusCode === 415,
  );
});

test("reports only genuinely missing assets and preserves the legacy Ledger Owl", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-pets-"));
  try {
    const assets = new PetAssetStore(dataDir);
    await assets.load();
    const customHash = "b".repeat(64);

    assert.equal(petAssetUrl({ id: "ledger-owl", assetHash: null }, assets), LEGACY_PET_URL);
    assert.equal(
      petAssetUrl({ id: "ledger-owl", assetHash: LEGACY_PET_HASH }, assets),
      LEGACY_PET_URL,
    );
    assert.deepEqual(
      missingPetAssets({ pet: { id: "lab-owl", assetHash: customHash } }, assets),
      [customHash],
    );
    assert.deepEqual(
      missingPetAssets({ pet: { id: "ledger-owl", assetHash: LEGACY_PET_HASH } }, assets),
      [],
    );
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

function sha256(body) {
  return createHash("sha256").update(body).digest("hex");
}
