export async function fetchWithTimeout(
  input,
  init = {},
  timeoutMs = 4000,
  runtime = {},
) {
  const fetchImpl = runtime.fetch ?? globalThis.fetch;
  const AbortControllerImpl = Object.prototype.hasOwnProperty.call(runtime, "AbortController")
    ? runtime.AbortController
    : globalThis.AbortController;
  const setTimeoutImpl = runtime.setTimeout ?? globalThis.setTimeout;
  const clearTimeoutImpl = runtime.clearTimeout ?? globalThis.clearTimeout;

  if (typeof fetchImpl !== "function") {
    throw new TypeError("fetch is unavailable");
  }

  const controller = typeof AbortControllerImpl === "function"
    ? new AbortControllerImpl()
    : null;
  let timeoutHandle;
  const timeout = new Promise((_, reject) => {
    timeoutHandle = setTimeoutImpl(() => {
      controller?.abort();
      const error = new Error(`Request timed out after ${timeoutMs} ms`);
      error.name = "TimeoutError";
      reject(error);
    }, timeoutMs);
  });

  try {
    const request = fetchImpl(input, {
      ...init,
      ...(controller ? { signal: controller.signal } : {}),
    });
    return await Promise.race([request, timeout]);
  } finally {
    clearTimeoutImpl(timeoutHandle);
  }
}
