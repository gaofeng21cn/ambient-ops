import assert from "node:assert/strict";
import test from "node:test";
import { connectionAfterFailure } from "../src/status-connection.mjs";

test("keeps the connection live through a transient polling failure", () => {
  assert.equal(connectionAfterFailure(10_000, 14_999, 5_000), "live");
  assert.equal(connectionAfterFailure(10_000, 15_000, 5_000), "live");
});

test("marks the connection stale after the failure grace period", () => {
  assert.equal(connectionAfterFailure(10_000, 15_001, 5_000), "stale");
  assert.equal(connectionAfterFailure(0, 1_000, 5_000), "stale");
});
