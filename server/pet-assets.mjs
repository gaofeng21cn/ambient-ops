import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import { link, mkdir, readFile, readdir, rm, stat, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";

export const PET_ASSET_MAX_BYTES = 8 * 1024 * 1024;
export const PET_SPRITESHEET_WIDTH = 1536;
export const PET_V1_SPRITESHEET_HEIGHT = 1872;
export const PET_V2_SPRITESHEET_HEIGHT = 2288;
export const LEGACY_PET_ID = "ledger-owl";
export const LEGACY_PET_HASH = "783854af87d6ee8639843ca7812917e062345b0095d43f9be5ea2374a41ada6c";
export const LEGACY_PET_URL = "/pets/ledger-owl/spritesheet.webp";

const HASH_PATTERN = /^[a-f0-9]{64}$/;

export class PetAssetStore {
  constructor(dataDir, { maxBytes = PET_ASSET_MAX_BYTES } = {}) {
    this.directory = join(dataDir, "pets");
    this.maxBytes = maxBytes;
    this.assets = new Set();
  }

  async load() {
    await mkdir(this.directory, { recursive: true });
    const entries = await readdir(this.directory, { withFileTypes: true });
    for (const entry of entries) {
      const match = entry.isFile() && entry.name.match(/^([a-f0-9]{64})\.webp$/);
      if (!match) continue;
      try {
        await this.read(match[1]);
      } catch (error) {
        this.assets.delete(match[1]);
        if ([404, 413, 422].includes(error.statusCode)) {
          try {
            await unlink(join(this.directory, entry.name));
          } catch (unlinkError) {
            if (unlinkError.code !== "ENOENT") throw unlinkError;
          }
        }
      }
    }
  }

  has(hash) {
    return HASH_PATTERN.test(hash || "") && this.assets.has(hash);
  }

  async put(expectedHash, body, { spriteVersionNumber } = {}) {
    assertHash(expectedHash);
    const metadata = inspectPetWebp(body, this.maxBytes);
    if (spriteVersionNumber != null) {
      assertVersionDimensions(spriteVersionNumber, metadata);
    }
    const actualHash = sha256(body);
    if (actualHash !== expectedHash) {
      throw httpError(422, "Pet asset SHA-256 does not match the URL");
    }
    if (this.has(expectedHash)) {
      await this.read(expectedHash);
      return { created: false, ...metadata };
    }

    const destination = this.pathFor(expectedHash);
    const temporary = join(this.directory, `.${expectedHash}.${process.pid}.${randomUUID()}.tmp`);
    await writeFile(temporary, body, { flag: "wx", mode: 0o600 });
    let created = false;
    try {
      try {
        await link(temporary, destination);
        created = true;
      } catch (error) {
        if (error.code !== "EEXIST") throw error;
        await this.verifyFile(expectedHash, destination);
      }
    } finally {
      await rm(temporary, { force: true });
    }
    this.assets.add(expectedHash);
    return { created, ...metadata };
  }

  async read(hash) {
    assertHash(hash, 404);
    const path = this.pathFor(hash);
    const body = await readBounded(path, this.maxBytes);
    inspectPetWebp(body, this.maxBytes);
    if (sha256(body) !== hash) throw httpError(404, "Pet asset not found");
    this.assets.add(hash);
    return body;
  }

  async verifyFile(hash, path) {
    const body = await readBounded(path, this.maxBytes);
    inspectPetWebp(body, this.maxBytes);
    if (sha256(body) !== hash) {
      throw httpError(409, "Stored pet asset conflicts with its content hash");
    }
  }

  pathFor(hash) {
    return join(this.directory, `${hash}.webp`);
  }
}

export function petAssetUrl(pet, assets) {
  if (!pet) return null;
  if (pet.assetHash && assets.has(pet.assetHash)) {
    return `/api/v1/pets/${pet.assetHash}.webp`;
  }
  if (
    pet.id === LEGACY_PET_ID
    && (!pet.assetHash || pet.assetHash === LEGACY_PET_HASH)
  ) {
    return LEGACY_PET_URL;
  }
  return null;
}

export function missingPetAssets(snapshot, assets) {
  if (!snapshot.pet?.assetHash) return [];
  return petAssetUrl(snapshot.pet, assets) ? [] : [snapshot.pet.assetHash];
}

export function validatePetUpload({ machine, machineId, hash, contentType, contentEncoding }) {
  assertHash(hash);
  if (contentEncoding && contentEncoding.toLowerCase() !== "identity") {
    throw httpError(415, "Compressed pet asset uploads are not supported");
  }
  const mediaType = String(contentType || "").split(";", 1)[0].trim().toLowerCase();
  if (mediaType !== "image/webp") throw httpError(415, "Pet asset must use Content-Type: image/webp");
  if (!machine?.pet?.assetHash || machine.machineId !== machineId || machine.pet.assetHash !== hash) {
    throw httpError(409, "Pet asset does not match the machine's current pet manifest");
  }
}

export async function readPetAssetBody(request, maxBytes = PET_ASSET_MAX_BYTES) {
  const declaredLength = request.headers["content-length"];
  if (declaredLength != null) {
    const length = Number(declaredLength);
    if (!Number.isInteger(length) || length < 0) throw httpError(400, "Invalid Content-Length");
    if (length > maxBytes) throw httpError(413, "Pet asset is too large");
  }
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    length += buffer.length;
    if (length > maxBytes) throw httpError(413, "Pet asset is too large");
    chunks.push(buffer);
  }
  return Buffer.concat(chunks, length);
}

export function authorizedBearer(header, token) {
  if (!token) return false;
  const expected = Buffer.from(`Bearer ${token}`);
  const actual = Buffer.from(String(header || ""));
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

export function inspectPetWebp(body, maxBytes = PET_ASSET_MAX_BYTES) {
  if (!Buffer.isBuffer(body)) throw httpError(422, "Pet asset must be binary WebP data");
  if (body.length > maxBytes) throw httpError(413, "Pet asset is too large");
  if (
    body.length < 26
    || body.toString("ascii", 0, 4) !== "RIFF"
    || body.toString("ascii", 8, 12) !== "WEBP"
    || body.readUInt32LE(4) + 8 !== body.length
  ) {
    throw httpError(422, "Invalid WebP container");
  }

  let dimensions = null;
  let offset = 12;
  while (offset < body.length) {
    if (offset + 8 > body.length) throw httpError(422, "Invalid WebP chunk table");
    const type = body.toString("ascii", offset, offset + 4);
    const size = body.readUInt32LE(offset + 4);
    const dataOffset = offset + 8;
    const end = dataOffset + size;
    const paddedEnd = end + (size % 2);
    if (end > body.length || paddedEnd > body.length) throw httpError(422, "Invalid WebP chunk length");
    dimensions ||= dimensionsForChunk(type, body, dataOffset, size);
    offset = paddedEnd;
  }
  if (offset !== body.length || !dimensions) throw httpError(422, "WebP image data is missing");
  if (
    dimensions.width !== PET_SPRITESHEET_WIDTH
    || ![PET_V1_SPRITESHEET_HEIGHT, PET_V2_SPRITESHEET_HEIGHT].includes(dimensions.height)
  ) {
    throw httpError(
      422,
      `Pet spritesheet must be ${PET_SPRITESHEET_WIDTH}x${PET_V1_SPRITESHEET_HEIGHT} (v1) or ${PET_SPRITESHEET_WIDTH}x${PET_V2_SPRITESHEET_HEIGHT} (v2) pixels`,
    );
  }
  return dimensions;
}

function assertVersionDimensions(spriteVersionNumber, dimensions) {
  const version = Number(spriteVersionNumber);
  const expectedHeight = version === 1
    ? PET_V1_SPRITESHEET_HEIGHT
    : version === 2 ? PET_V2_SPRITESHEET_HEIGHT : null;
  if (!expectedHeight) throw httpError(422, "Unsupported pet sprite version");
  if (dimensions.height !== expectedHeight) {
    throw httpError(
      422,
      `Pet sprite version ${version} requires ${PET_SPRITESHEET_WIDTH}x${expectedHeight} pixels`,
    );
  }
}

function dimensionsForChunk(type, body, offset, size) {
  if (type === "VP8L") {
    if (size < 5 || body[offset] !== 0x2f) throw httpError(422, "Invalid lossless WebP header");
    const bits = body.readUInt32LE(offset + 1);
    return { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 };
  }
  if (type === "VP8X") {
    if (size < 10) throw httpError(422, "Invalid extended WebP header");
    return {
      width: body.readUIntLE(offset + 4, 3) + 1,
      height: body.readUIntLE(offset + 7, 3) + 1,
    };
  }
  if (type === "VP8 ") {
    if (
      size < 10
      || body[offset + 3] !== 0x9d
      || body[offset + 4] !== 0x01
      || body[offset + 5] !== 0x2a
    ) {
      throw httpError(422, "Invalid lossy WebP header");
    }
    return {
      width: body.readUInt16LE(offset + 6) & 0x3fff,
      height: body.readUInt16LE(offset + 8) & 0x3fff,
    };
  }
  return null;
}

async function readBounded(path, maxBytes) {
  let details;
  try {
    details = await stat(path);
  } catch (error) {
    if (error.code === "ENOENT") throw httpError(404, "Pet asset not found");
    throw error;
  }
  if (!details.isFile() || details.size > maxBytes) throw httpError(404, "Pet asset not found");
  return readFile(path);
}

function assertHash(hash, statusCode = 400) {
  if (!HASH_PATTERN.test(hash || "")) throw httpError(statusCode, "Invalid pet asset hash");
}

function sha256(body) {
  return createHash("sha256").update(body).digest("hex");
}

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}
