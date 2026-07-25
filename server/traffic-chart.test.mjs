import test from "node:test";
import assert from "node:assert/strict";
import {
  scaledTrafficY,
  smoothTrafficPath,
  smoothTrafficValues,
  trafficScale,
} from "../src/traffic-chart.mjs";

test("smooths short-interval traffic without flattening a real peak", () => {
  const values = smoothTrafficValues([1, 1, 1, 25, 1, 1, 1]);
  assert.ok(values[3] > values[2]);
  assert.ok(values[3] < 25);
  assert.ok(values[2] > 1);
});

test("chooses a readable dynamic scale without a fixed 100 Mbps floor", () => {
  assert.equal(trafficScale([[0.7, 1.2, 3.8], [0.2, 0.3]]), 5);
  assert.equal(trafficScale([[68], [12]]), 100);
  assert.equal(trafficScale([[0], [0]]), 1);
});

test("an isolated spike does not compress the rest of a live window", () => {
  const values = Array.from({ length: 300 }, () => 4);
  values[150] = 500;
  assert.equal(trafficScale([smoothTrafficValues(values)]), 5);
});

test("builds a bounded quadratic path and maps the scale peak to the chart top", () => {
  const path = smoothTrafficPath([0, 5, 10], 10, 100, 50);
  assert.match(path, /^M 0\.0 50\.0 Q /);
  assert.doesNotMatch(path, / C /);
  assert.equal(scaledTrafficY(10, 10, 50), 0);
  assert.equal(scaledTrafficY(0, 10, 50), 50);
});
