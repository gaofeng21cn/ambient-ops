import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  KIOSK_RELEASE_PATH_PREFIX,
  KioskReleaseStore,
  validateManifest,
} from "./kiosk-release.mjs";

const signerSha256 = "4e5f5732645986e5a861446028846fcfb571b9dd006d87da19aa60f152639206";

test("loads an immutable kiosk release only when its artifact matches", async () => {
  const directory = await mkdtemp(join(tmpdir(), "ambient-ops-kiosk-release-"));
  try {
    const artifact = "Ambient-Ops-Kiosk-1.2.1.apk";
    const body = Buffer.from("signed apk fixture");
    const sha256 = digest(body);
    await writeFile(join(directory, artifact), body);
    await writeFile(
      join(directory, "kiosk-update.json"),
      JSON.stringify({
        versionCode: 5,
        versionName: "1.2.1",
        artifact,
        sha256,
        signerSha256,
      }),
    );

    const releases = new KioskReleaseStore(directory);
    await releases.load();

    assert.deepEqual(releases.manifest, {
      versionCode: 5,
      versionName: "1.2.1",
      apkPath: `${KIOSK_RELEASE_PATH_PREFIX}${artifact}`,
      sha256,
      signerSha256,
    });
    assert.equal(releases.matchesArtifact(releases.manifest.apkPath), true);
    assert.deepEqual(await releases.readArtifact(), body);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("treats an absent kiosk release manifest as updates disabled", async () => {
  const directory = await mkdtemp(join(tmpdir(), "ambient-ops-kiosk-release-"));
  try {
    const releases = new KioskReleaseStore(directory);
    await releases.load();
    assert.equal(releases.manifest, null);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("rejects traversal, malformed signer digests, and artifact hash drift", async () => {
  assert.throws(
    () => validateManifest({
      versionCode: 5,
      versionName: "1.2.1",
      artifact: "../update.apk",
      sha256: "a".repeat(64),
      signerSha256,
    }),
    /artifact name/,
  );
  assert.throws(
    () => validateManifest({
      versionCode: 5,
      versionName: "1.2.1",
      artifact: "update.apk",
      sha256: "a".repeat(64),
      signerSha256: "not-a-digest",
    }),
    /signer SHA-256/,
  );

  const directory = await mkdtemp(join(tmpdir(), "ambient-ops-kiosk-release-"));
  try {
    await mkdir(join(directory, "unused"));
    await writeFile(join(directory, "update.apk"), "actual");
    await writeFile(
      join(directory, "kiosk-update.json"),
      JSON.stringify({
        versionCode: 5,
        versionName: "1.2.1",
        artifact: "update.apk",
        sha256: digest(Buffer.from("different")),
        signerSha256,
      }),
    );
    const releases = new KioskReleaseStore(directory);
    await assert.rejects(releases.load(), /does not match/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

function digest(body) {
  return createHash("sha256").update(body).digest("hex");
}
