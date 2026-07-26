import assert from "node:assert/strict";
import test from "node:test";
import { fetchWithTimeout } from "../src/http.mjs";

test("fetches when AbortSignal.timeout is unavailable", async () => {
  let request;
  const response = { ok: true };

  const actual = await fetchWithTimeout("/api/status", { cache: "no-store" }, 100, {
    AbortController: undefined,
    fetch: async (input, init) => {
      request = { input, init };
      return response;
    },
  });

  assert.equal(actual, response);
  assert.deepEqual(request, {
    input: "/api/status",
    init: { cache: "no-store" },
  });
});

test("rejects a hung request after the timeout without AbortController", async () => {
  await assert.rejects(
    fetchWithTimeout("/api/status", {}, 5, {
      AbortController: undefined,
      fetch: () => new Promise(() => {}),
    }),
    { name: "TimeoutError", message: "Request timed out after 5 ms" },
  );
});

test("aborts the underlying request when AbortController is available", async () => {
  let controller;
  class TestAbortController {
    constructor() {
      this.signal = { aborted: false };
      controller = this;
    }

    abort() {
      this.signal.aborted = true;
    }
  }

  await assert.rejects(
    fetchWithTimeout("/api/status", {}, 5, {
      AbortController: TestAbortController,
      fetch: () => new Promise(() => {}),
    }),
    { name: "TimeoutError" },
  );
  assert.equal(controller.signal.aborted, true);
});
