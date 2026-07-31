import assert from "node:assert/strict";
import test from "node:test";
import {
  connectionAfterFailure,
  displayConnectionConfiguration,
  resolveStatusAssetURLs,
} from "../src/status-connection.mjs";

test("keeps the connection live through a transient polling failure", () => {
  assert.equal(connectionAfterFailure(10_000, 14_999, 5_000), "live");
  assert.equal(connectionAfterFailure(10_000, 15_000, 5_000), "live");
});

test("marks the connection stale after the failure grace period", () => {
  assert.equal(connectionAfterFailure(10_000, 15_001, 5_000), "stale");
  assert.equal(connectionAfterFailure(0, 1_000, 5_000), "stale");
});

test("accepts only HTTP status endpoints for an embedded display", () => {
  assert.deepEqual(
    displayConnectionConfiguration({
      search: "?statusUrl=http%3A%2F%2F192.168.1.8%3A47321%2Fapi%2Fv1%2Fstatus&view=load",
    }),
    {
      embedded: true,
      statusEndpoint: "http://192.168.1.8:47321/api/v1/status",
      requestedView: "load",
    },
  );
  assert.equal(
    displayConnectionConfiguration({ search: "?statusUrl=file%3A%2F%2F%2Ftmp%2Fstatus" }).statusEndpoint,
    "/api/status",
  );
});

test("resolves Direct pet assets only on the status endpoint origin", () => {
  const hash = "a".repeat(64);
  const directStatus = {
    machines: [{
      machineId: "mac",
      pet: { assetHash: hash, assetUrl: `/api/v1/pets/${hash}.webp` },
    }],
  };
  const resolved = resolveStatusAssetURLs(
    directStatus,
    "http://192.168.1.8:47321/api/v1/status",
  );
  assert.equal(
    resolved.machines[0].pet.assetUrl,
    `http://192.168.1.8:47321/api/v1/pets/${hash}.webp`,
  );
  assert.equal(resolved.machines[0].pet.assetUrlTrustedOrigin, true);

  const rejected = resolveStatusAssetURLs({
    machines: [{
      machineId: "mac",
      pet: { assetHash: hash, assetUrl: `https://tracker.invalid/api/v1/pets/${hash}.webp` },
    }],
  }, "http://192.168.1.8:47321/api/v1/status");
  assert.equal(rejected.machines[0].pet.assetUrl, null);
  assert.equal(rejected.machines[0].pet.assetUrlTrustedOrigin, false);
});
