import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  readUiRevision,
  UI_REVISION_PATH,
  uiRevisionForIndex,
} from "./ui-revision.mjs";

test("uses the stable kiosk UI revision endpoint", () => {
  assert.equal(UI_REVISION_PATH, "/api/v1/ui/revision");
});

test("hashes the exact built index bytes", () => {
  assert.equal(
    uiRevisionForIndex(Buffer.from("ambient-ops-ui")),
    "d4cd2587bf5c6d47af2983f9668072a7ac5928fe33c93a6ef6baca149f97e15a",
  );
});

test("reads the built index from the dist directory", async () => {
  const directory = await mkdtemp(join(tmpdir(), "ambient-ops-ui-revision-"));
  try {
    await mkdir(join(directory, "dist"));
    await writeFile(join(directory, "dist", "index.html"), "<main>v1</main>");
    assert.equal(
      await readUiRevision(join(directory, "dist")),
      uiRevisionForIndex(Buffer.from("<main>v1</main>")),
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
