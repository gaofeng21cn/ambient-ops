# Security Model

Ambient Ops is intended for a trusted local network or a private VPN.
It is not hardened as a directly internet-facing service.

## Secrets

- Store `UNIFI_API_KEY` and `AGENT_PUSH_TOKEN` only in the deployment `.env` or
  the container platform's secret store.
- Never place secrets in frontend JavaScript, URLs, screenshots, or Git.
- The display browser needs no credential because it reads normalized status
  from the local server.
- Use a dedicated read-only UniFi API key with the smallest available scope.

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
