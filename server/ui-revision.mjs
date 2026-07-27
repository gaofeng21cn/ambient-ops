import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export const UI_REVISION_PATH = "/api/v1/ui/revision";

export function uiRevisionForIndex(body) {
  return createHash("sha256").update(body).digest("hex");
}

export async function readUiRevision(distDirectory) {
  return uiRevisionForIndex(await readFile(join(distDirectory, "index.html")));
}
