export const RESPONSE_CHUNK_BYTES = 16 * 1024;
export const RESPONSE_WRITE_TIMEOUT_MS = 10_000;

export async function sendBody(response, statusCode, body, {
  headers = {},
  headOnly = false,
  chunkBytes = RESPONSE_CHUNK_BYTES,
  writeTimeoutMs = RESPONSE_WRITE_TIMEOUT_MS,
} = {}) {
  if (!Number.isInteger(chunkBytes) || chunkBytes <= 0) {
    throw new RangeError("HTTP response chunk size must be a positive integer");
  }
  if (!Number.isFinite(writeTimeoutMs) || writeTimeoutMs <= 0) {
    throw new RangeError("HTTP response write timeout must be positive");
  }

  const payload = Buffer.isBuffer(body) ? body : Buffer.from(String(body ?? ""));
  response.writeHead(statusCode, {
    ...headers,
    "content-length": String(payload.length),
  });
  response.flushHeaders();

  if (!headOnly) {
    for (let offset = 0; offset < payload.length; offset += chunkBytes) {
      assertWritable(response);
      const accepted = response.write(payload.subarray(offset, offset + chunkBytes));
      if (!accepted) {
        assertWritable(response);
        await waitFor(response, "drain", writeTimeoutMs);
      }
    }
  }

  assertWritable(response);
  const finished = waitFor(response, "finish", writeTimeoutMs);
  response.end();
  await finished;
}

function waitFor(response, event, timeoutMs) {
  return new Promise((resolve, reject) => {
    let timer;
    const cleanup = () => {
      clearTimeout(timer);
      response.removeListener(event, onEvent);
      response.removeListener("close", onClose);
      response.removeListener("error", onError);
    };
    const settle = (callback, value) => {
      cleanup();
      callback(value);
    };
    const onEvent = () => settle(resolve);
    const onClose = () => settle(reject, responseError(
      "ERR_HTTP_RESPONSE_CLOSED",
      `HTTP response closed while waiting for ${event}`,
    ));
    const onError = (error) => settle(reject, error);

    response.once(event, onEvent);
    response.once("close", onClose);
    response.once("error", onError);
    timer = setTimeout(() => settle(reject, responseError(
      "ERR_HTTP_RESPONSE_STALLED",
      `HTTP response stalled waiting for ${event} after ${timeoutMs} ms`,
    )), timeoutMs);
  });
}

function assertWritable(response) {
  if (!response.destroyed && !response.writableEnded) return;
  throw responseError("ERR_HTTP_RESPONSE_CLOSED", "HTTP response is no longer writable");
}

function responseError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}
