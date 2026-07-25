import snmp from "net-snmp";

const IF_X_TABLE = "1.3.6.1.2.1.31.1.1";
const IF_X_COLUMNS = [1, 6, 10, 15, 18];

export function createUnifiSnmpPoller(config, initialClient) {
  let client = initialClient || new NetSnmpClient(config);
  let samples = [];
  const rateWindowMs = Math.max(1000, config.rateWindowMs || config.pollMs * 8);

  async function readInterfaces() {
    try {
      return await client.readInterfaces();
    } catch (error) {
      samples = [];
      client.close?.();
      if (!initialClient) client = new NetSnmpClient(config);
      throw error;
    }
  }

  return async function poll() {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const current = await readInterfaces();
      const selected = selectInterfaces(current, config.interfaces);
      if (!selected.length) {
        throw new Error(`SNMP found no matching WAN interfaces: ${config.interfaces.join(", ")}`);
      }

      if (!samples.length) {
        samples.push(current);
        await delay(Math.min(config.pollMs, 1000));
      }

      const next = samples.at(-1) === current ? await readInterfaces() : current;
      samples.push(next);
      trimRateWindow(samples, next.sampledAt.valueOf() - rateWindowMs);

      try {
        const measurement = calculateThroughput(
          samples[0],
          next,
          selected.map((entry) => entry.index),
        );
        return {
          status: "live",
          source: "unifi-snmp-v3",
          downloadMbps: measurement.downloadMbps,
          uploadMbps: measurement.uploadMbps,
          clients: null,
          latencyMs: null,
          interfaces: measurement.interfaces,
          updatedAt: next.sampledAt.toISOString(),
          error: null,
        };
      } catch (error) {
        samples = [];
        if (error.code !== "SNMP_COUNTER_RESET" || attempt > 0) throw error;
      }
    }
    throw new Error("SNMP failed to establish a stable counter baseline");
  };
}

function trimRateWindow(samples, cutoffMs) {
  while (
    samples.length > 2
    && samples[1].sampledAt.valueOf() <= cutoffMs
  ) {
    samples.shift();
  }
}

export function selectInterfaces(sample, selectors) {
  const normalized = selectors.map((selector) => String(selector).trim().toLowerCase()).filter(Boolean);
  return sample.interfaces.filter((entry) => {
    const candidates = [entry.index, entry.name, entry.alias].map((value) => String(value ?? "").toLowerCase());
    return normalized.some((selector) => candidates.includes(selector));
  });
}

export function calculateThroughput(previous, current, indexes) {
  const elapsedSeconds = (current.sampledAt.valueOf() - previous.sampledAt.valueOf()) / 1000;
  if (!(elapsedSeconds > 0)) throw new Error("SNMP samples have no elapsed time");

  let inboundBytes = 0n;
  let outboundBytes = 0n;
  const interfaces = [];
  for (const index of indexes) {
    const before = previous.interfaces.find((entry) => entry.index === index);
    const after = current.interfaces.find((entry) => entry.index === index);
    if (!before || !after) throw new Error(`SNMP interface ${index} disappeared between samples`);

    const inboundDelta = counterDelta(before.inOctets, after.inOctets);
    const outboundDelta = counterDelta(before.outOctets, after.outOctets);
    inboundBytes += inboundDelta;
    outboundBytes += outboundDelta;
    interfaces.push({
      index,
      name: after.name,
      alias: after.alias,
      downloadMbps: bitsPerSecond(inboundDelta, elapsedSeconds),
      uploadMbps: bitsPerSecond(outboundDelta, elapsedSeconds),
    });
  }

  return {
    downloadMbps: bitsPerSecond(inboundBytes, elapsedSeconds),
    uploadMbps: bitsPerSecond(outboundBytes, elapsedSeconds),
    interfaces,
  };
}

export function counter64(value) {
  if (typeof value === "bigint") return value;
  if (typeof value === "number" || typeof value === "string") return BigInt(value);
  if (!Buffer.isBuffer(value)) throw new TypeError("SNMP Counter64 must be a buffer or integer");
  let result = 0n;
  for (const byte of value) result = (result << 8n) | BigInt(byte);
  return result;
}

function counterDelta(before, after) {
  const start = counter64(before);
  const end = counter64(after);
  if (end < start) {
    const error = new Error("SNMP Counter64 decreased; interface likely restarted");
    error.code = "SNMP_COUNTER_RESET";
    throw error;
  }
  return end - start;
}

function bitsPerSecond(bytes, elapsedSeconds) {
  return Number(bytes) * 8 / elapsedSeconds / 1_000_000;
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

class NetSnmpClient {
  constructor(config) {
    const authProtocol = protocol(snmp.AuthProtocols, config.authProtocol, "authentication");
    const privProtocol = protocol(snmp.PrivProtocols, config.privProtocol, "privacy");
    this.session = snmp.createV3Session(config.host, {
      name: config.user,
      level: snmp.SecurityLevel.authPriv,
      authProtocol,
      authKey: config.authPassword,
      privProtocol,
      privKey: config.privPassword || config.authPassword,
    }, {
      port: config.port,
      retries: 1,
      timeout: config.timeoutMs,
      transport: "udp4",
    });
  }

  readInterfaces() {
    return new Promise((resolve, reject) => {
      this.session.tableColumns(IF_X_TABLE, IF_X_COLUMNS, 20, (error, table) => {
        if (error) return reject(error);
        try {
          const interfaces = Object.entries(table).map(([index, row]) => ({
            index: Number(index),
            name: text(row[1]),
            inOctets: counter64(row[6]),
            outOctets: counter64(row[10]),
            speedMbps: Number(row[15] ?? 0),
            alias: text(row[18]),
          }));
          resolve({ sampledAt: new Date(), interfaces });
        } catch (parseError) {
          reject(parseError);
        }
      });
    });
  }

  close() {
    this.session.close();
  }
}

function text(value) {
  return Buffer.isBuffer(value) ? value.toString("utf8").replace(/\0+$/, "") : String(value ?? "");
}

function protocol(protocols, requested, kind) {
  const value = protocols[String(requested).toLowerCase()];
  if (value == null) throw new Error(`Unsupported SNMPv3 ${kind} protocol: ${requested}`);
  return value;
}
