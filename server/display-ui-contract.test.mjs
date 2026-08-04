import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = dirname(dirname(fileURLToPath(import.meta.url)));

test("Fleet Nodes renders the complete ordered directory", async () => {
  const source = await readFile(join(repoRoot, "src/App.jsx"), "utf8");
  const start = source.indexOf("function DeviceFleetMachinesView");
  const end = source.indexOf("function DeviceMachinesView", start);
  const view = source.slice(start, end);

  assert.match(view, /\{ordered\.map\(\(machine\) =>/);
  assert.doesNotMatch(view, /\.slice\(0,\s*4\)/);
  assert.doesNotMatch(view, /\+\{machines\.length -/);
});

test("Fleet Nodes keeps the kiosk single-screen while its directory scrolls", async () => {
  const styles = await readFile(join(repoRoot, "src/styles.css"), "utf8");
  const rule = styles.match(/\.fleet-machine-directory\s*\{([^}]*)\}/)?.[1] || "";

  assert.match(rule, /min-height:\s*0/);
  assert.match(rule, /grid-auto-rows:\s*minmax\(55px,\s*1fr\)/);
  assert.match(rule, /overflow-y:\s*auto/);
  assert.match(rule, /overscroll-behavior-y:\s*contain/);
  assert.match(rule, /touch-action:\s*pan-y/);
});
