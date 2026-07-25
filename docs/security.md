# Security and Privacy

Ambient Ops is designed for a trusted LAN. It collects operational aggregates,
not conversation content, and separates collector credentials from display
clients.

## Trust boundary

- Codex TPS reads local Codex token records on each Mac and sends only the
  allowlisted aggregate snapshot documented in
  [`agent-push-api.md`](agent-push-api.md).
- The server reads UniFi through SNMPv3 `authPriv` or an optional read-only
  Network API key.
- The HTC kiosk and browsers receive normalized status only. They contain no
  agent token, SNMP credential, UniFi key, or Home Assistant token.
- Home Assistant is an optional downstream write target, never an authority for
  collection or display.

The display and status endpoints intentionally have no browser login. Bind them
only to the trusted LAN or a private VPN. Add an authenticated TLS reverse proxy
before exposing them outside that boundary.

## Secret handling

The production Compose service reads ignored files mounted read-only at
`/run/secrets`:

```text
agent_push_token
unifi_snmp_auth_password
unifi_snmp_priv_password
unifi_api_key
ha_token
```

Only the first three are required for the preferred live configuration. The
last two are optional fallbacks/integrations. Protect the local `secrets`
directory with owner-only permissions and never commit `.env`, secret files,
certificates, logs, screenshots, or data exports.

The macOS runtime stores credentials in Keychain and puts only Keychain service
names in its LaunchAgent plist. Do not replace this with raw plist environment
values.

## Agent authentication

All agents for one installation share a long random bearer token. Preserve the
same token during a host migration, or rotate it deliberately and update every
agent. A token mismatch returns HTTP 401 and eventually makes that machine
stale; it must not be worked around by disabling authentication.

Bearer requests use plain HTTP on the current trusted LAN. Use an HTTPS reverse
proxy or private VPN if traffic crosses an untrusted network.

## Persistent data

`/data/state.json` contains:

- normalized machine names, platform, rates, counts, and pet state
- last UniFi rates and selected interface metadata
- short network history

It does not contain prompts, responses, file contents, session identifiers, or
repository paths. The optional generated `instance-id` file is a public,
non-secret discovery identity.

## Single-instance rule

Exactly one canonical Ambient Ops instance should publish
`_ambient-ops._tcp.local` and accept agent snapshots for a site. Parallel Mac
and NAS owners can split clients, duplicate machine state, and make rollback
ambiguous. Stage candidates with discovery disabled, stop the old owner before
starting the new LAN owner, and reverse that order during rollback.
