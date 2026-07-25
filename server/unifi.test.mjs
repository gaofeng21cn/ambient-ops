import test from "node:test";
import assert from "node:assert/strict";
import { bytesPerSecondToMbps, tlsAgentOptions } from "./unifi.mjs";

test("converts bytes per second to decimal megabits per second", () => {
  assert.equal(bytesPerSecondToMbps(125_000_000), 1000);
  assert.equal(bytesPerSecondToMbps(undefined), 0);
});

test("builds strict TLS options with an explicit UniFi CA", () => {
  const ca = Buffer.from("certificate");
  assert.deepEqual(tlsAgentOptions({ allowSelfSigned: false, ca }), {
    rejectUnauthorized: true,
    ca,
  });
  assert.deepEqual(tlsAgentOptions({ allowSelfSigned: true }), {
    rejectUnauthorized: false,
  });
});
