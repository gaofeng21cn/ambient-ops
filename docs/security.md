# Security Model

Ambient Ops is intended for a trusted local network or a private VPN.
It is not hardened as a directly internet-facing service.

## Secrets

- Store `UNIFI_API_KEY`, SNMPv3 passwords, `HA_TOKEN`, and `AGENT_PUSH_TOKEN`
  as files under the ignored `secrets/` directory or in the container
  platform's secret store. Compose passes only `/run/secrets/*` paths through
  the environment, not the secret values.
- A direct macOS deployment may set the corresponding Keychain service names
  instead of putting secret values in environment variables.
- Never place secrets in frontend JavaScript, URLs, screenshots, or Git.
- The display browser needs no credential because it reads normalized status
  from the local server.
- Prefer SNMPv3 `authPriv` or a dedicated read-only UniFi API key with the smallest available scope.

## Network Boundary

- Expose the service only to the local network or VPN.
- If remote access is required, place it behind an authenticated TLS reverse
  proxy.
- The prototype uses one shared agent push token. A future multi-user release
  should support separately revocable per-agent tokens.
- Self-signed UniFi certificates are supported for local controllers. This
  exception applies only to the configured UniFi connection.

## Stored Data

The persistent volume contains normalized machine metrics, timestamps, status
messages, and short WAN throughput history. It must not contain conversation
text. The state file is written atomically with owner-only permissions where
the host filesystem supports POSIX modes.
