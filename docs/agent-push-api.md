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
persisted. Payloads are limited to 64 KiB.

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

Agents must not send prompts, responses, file contents, session identifiers,
repository paths, or other conversation content. The server stores only its
explicit normalized allowlist even if extra JSON fields are submitted.
