import assert from "node:assert/strict";
import { EventEmitter, once } from "node:events";
import { createServer, get } from "node:http";
import test from "node:test";
import {
  RESPONSE_CHUNK_BYTES,
  sendBody,
} from "./http-response.mjs";

test("frames and delivers a large HTTP response without chunked encoding", async (t) => {
  const body = Buffer.alloc(241_241, "x");
  const server = createServer((request, response) => {
    sendBody(response, 200, body, {
      headers: { "content-type": "text/javascript; charset=utf-8" },
    }).catch((error) => response.destroy(error));
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => new Promise((resolve) => server.close(resolve)));

  const response = await request(`http://127.0.0.1:${server.address().port}/asset.js`);

  assert.equal(response.statusCode, 200);
  assert.equal(response.headers["content-length"], String(body.length));
  assert.equal(response.headers["transfer-encoding"], undefined);
  assert.deepEqual(response.body, body);
});

test("flushes headers and honors backpressure while sending bounded chunks", async () => {
  const response = new FakeResponse({ backpressureAt: 1 });
  const body = Buffer.alloc(RESPONSE_CHUNK_BYTES * 2 + 73, "a");

  await sendBody(response, 200, body, {
    headers: {
      "content-length": "1",
      "content-type": "application/octet-stream",
    },
    writeTimeoutMs: 100,
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.headers["content-length"], String(body.length));
  assert.equal(response.headers["content-type"], "application/octet-stream");
  assert.equal(response.flushed, true);
  assert.deepEqual(
    response.chunks.map((chunk) => chunk.length),
    [RESPONSE_CHUNK_BYTES, RESPONSE_CHUNK_BYTES, 73],
  );
  assert.deepEqual(Buffer.concat(response.chunks), body);
  assert.equal(response.ended, true);
});

test("keeps the representation length for HEAD without writing a body", async () => {
  const response = new FakeResponse();

  await sendBody(response, 200, "ambient", {
    headOnly: true,
    writeTimeoutMs: 100,
  });

  assert.equal(response.headers["content-length"], "7");
  assert.deepEqual(response.chunks, []);
  assert.equal(response.ended, true);
});

test("fails a stalled response after the bounded backpressure timeout", async () => {
  const response = new FakeResponse({ backpressureAt: 1, drain: false });

  await assert.rejects(
    sendBody(response, 200, Buffer.alloc(RESPONSE_CHUNK_BYTES + 1), {
      writeTimeoutMs: 10,
    }),
    {
      code: "ERR_HTTP_RESPONSE_STALLED",
      message: "HTTP response stalled waiting for drain after 10 ms",
    },
  );
  assert.equal(response.ended, false);
});

test("fails when a completed body never reaches the finish event", async () => {
  const response = new FakeResponse({ finish: false });

  await assert.rejects(
    sendBody(response, 200, "ambient", { writeTimeoutMs: 10 }),
    {
      code: "ERR_HTTP_RESPONSE_STALLED",
      message: "HTTP response stalled waiting for finish after 10 ms",
    },
  );
  assert.equal(response.ended, true);
});

class FakeResponse extends EventEmitter {
  constructor({ backpressureAt = 0, drain = true, finish = true } = {}) {
    super();
    this.backpressureAt = backpressureAt;
    this.drain = drain;
    this.finish = finish;
    this.chunks = [];
    this.destroyed = false;
    this.ended = false;
    this.flushed = false;
  }

  writeHead(statusCode, headers) {
    this.statusCode = statusCode;
    this.headers = headers;
  }

  flushHeaders() {
    this.flushed = true;
  }

  write(chunk) {
    this.chunks.push(Buffer.from(chunk));
    if (this.chunks.length !== this.backpressureAt) return true;
    if (this.drain) setImmediate(() => this.emit("drain"));
    return false;
  }

  end() {
    this.ended = true;
    if (this.finish) setImmediate(() => this.emit("finish"));
  }
}

function request(url) {
  return new Promise((resolve, reject) => {
    get(url, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
      response.on("end", () => resolve({
        body: Buffer.concat(chunks),
        headers: response.headers,
        statusCode: response.statusCode,
      }));
    }).on("error", reject);
  });
}
