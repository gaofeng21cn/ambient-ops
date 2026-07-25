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
  "activeSessions": 2
}
```

`machineId` is a stable, non-secret identifier containing only letters,
numbers, dots, underscores, and hyphens. It should not be regenerated on every
start.

The endpoint returns `202 Accepted` after the normalized snapshot has been
persisted. Payloads are limited to 64 KiB.

## Freshness

- `LIVE`: generated within `LIVE_AFTER_SECONDS`
- `STALE`: older than live but within `STALE_AFTER_SECONDS`
- `ERROR`: older than the stale window, or explicitly reported as an error

Stale and error machines retain their last values. They are never silently
converted to zero.

## Privacy Contract

Agents must not send prompts, responses, file contents, session identifiers,
repository paths, or other conversation content. The server stores only its
explicit normalized allowlist even if extra JSON fields are submitted.
