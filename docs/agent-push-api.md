# Agent Push API

Machines push aggregate metrics to the server. The server never requests local
session files and ignores fields outside the allowlist below.

## Request

```http
POST /api/v1/agents/{machineId}/snapshot
Authorization: Bearer <AGENT_PUSH_TOKEN>
Content-Type: application/json
```

```json
{
  "schemaVersion": 1,
  "machineName": "Primary Laptop",
  "platform": "macOS",
  "generatedAt": "2026-07-25T12:00:00.000Z",
  "status": "live",
  "oneMinute": {
    "tps": 124.5,
    "inputTokens": 8100,
    "outputTokens": 1300,
    "cachedInputTokens": 6200,
    "reasoningOutputTokens": 400,
    "requests": 5
  },
  "fiveMinutes": {
    "tps": 98.2,
    "inputTokens": 30200,
    "outputTokens": 4700,
    "cachedInputTokens": 22100,
    "reasoningOutputTokens": 1600,
    "requests": 19
  },
  "activeSessions": 2,
  "pet": {
    "id": "ledger-owl",
    "displayName": "Ledger Owl",
    "spriteVersionNumber": 1,
    "assetHash": "783854af87d6ee8639843ca7812917e062345b0095d43f9be5ea2374a41ada6c",
    "state": "running",
    "stateSince": "2026-07-25T11:59:55.000Z"
  }
}
```

`machineId` is a stable, non-secret identifier containing only letters,
numbers, dots, underscores, and hyphens. It should not be regenerated on every
start.

The endpoint returns `202 Accepted` after the normalized snapshot has been
persisted. Payloads are limited to 64 KiB. The response contains
`missingPetAssets`, which is either empty or contains the snapshot pet's
content hash:

```json
{
  "accepted": true,
  "machineId": "primary-laptop",
  "generatedAt": "2026-07-25T12:00:00.000Z",
  "missingPetAssets": [
    "cdc205aa95ef04408b87cc93e0890b12dea538256912458a718187cf5a18a347"
  ]
}
```

`inputTokens` includes the cached-input subset and `outputTokens` includes the
reasoning-output subset. Therefore:

```text
total TPS = inputTokens / windowSeconds + outputTokens / windowSeconds
```

Do not add `cachedInputTokens` or `reasoningOutputTokens` again. They are
breakdowns, not extra usage.

`pet` is optional. Accepted states are `idle`, `running`, `waiting`, `review`,
and `failed`. The server retains only the fields shown above, validates the pet
ID and asset hash, and projects a stale/error machine to `waiting`/`failed`
without altering the agent's last stored state.

## Pet Asset Upload

After a snapshot reports a hash in `missingPetAssets`, upload that exact local
spritesheet:

```http
PUT /api/v1/agents/{machineId}/pets/{lowercaseSha256}
Authorization: Bearer <AGENT_PUSH_TOKEN>
Content-Type: image/webp

<raw spritesheet.webp bytes>
```

The server accepts the upload only when the current normalized snapshot for
`machineId` declares the same hash. It rejects compressed transfer content,
non-WebP media types, malformed RIFF/WebP containers, a mismatched SHA-256,
files larger than 8 MiB, and spritesheets whose dimensions do not match the
manifest version: v1 is 1536 by 1872 pixels and v2 is 1536 by 2288 pixels.

- `201 Created`: new bytes were atomically persisted. The JSON body contains
  `stored`, `assetHash`, and the content-addressed `assetUrl`.
- `204 No Content`: the same content hash is already present. This is the normal
  idempotent retry result.
- `401 Unauthorized`: bearer token missing or incorrect.
- `409 Conflict`: the machine's current pet manifest does not declare this hash,
  or persisted bytes conflict with their hash.
- `413 Payload Too Large`: declared or streamed content exceeds 8 MiB.
- `415 Unsupported Media Type`: media type or content encoding is unsupported.
- `422 Unprocessable Content`: hash, WebP structure, or dimensions do not match.

Uploaded bytes are stored at `/data/pets/{sha256}.webp` and served publicly at
`GET /api/v1/pets/{sha256}.webp`. The read URL is immutable and carries a
one-year cache policy; a pet update changes the SHA-256 and therefore changes
the URL. Agents should upload a hash only after the server asks for it and
should not resend bytes after `201` or `204`.

The bundled Ledger Owl remains available to old snapshots that omit
`assetHash`, and to snapshots using its original
`783854af87d6ee8639843ca7812917e062345b0095d43f9be5ea2374a41ada6c`
hash. No migration or upload is required for those snapshots.

For Compose, the shared bearer value lives in
`secrets/agent_push_token`. Codex TPS stores the same value in the user's
Keychain. Keep it stable during a server migration or explicitly update every
agent.

## Freshness

- `LIVE`: generated within `LIVE_AFTER_SECONDS`
- `STALE`: older than live but within `STALE_AFTER_SECONDS`
- `ERROR`: older than the stale window, or explicitly reported as an error

Stale machines retain their last values instead of becoming zero. Once a
machine exceeds `STALE_AFTER_SECONDS`, it is retired from the dashboard and
persistent state.

## Privacy Contract

Agents must not send prompts, responses, session identifiers, repository paths,
or other conversation content. The only accepted file content is the validated
pet `spritesheet.webp` whose hash is declared by the pet manifest. The server
stores only its explicit normalized snapshot allowlist and that content-addressed
image even if extra JSON fields are submitted.
