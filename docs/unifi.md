# UniFi Setup

Ambient Ops can read WAN throughput with SNMPv3 or the UniFi Network API.
SNMPv3 is preferred because it avoids a controller API credential and exposes
standard 64-bit interface counters. If both paths are configured, SNMPv3 wins.

## SNMPv3

Enable SNMPv3 `authPriv` in UniFi Network and record the existing username,
authentication password, privacy password, and exact WAN interface names or
indexes.

For Compose, keep only non-secret values in `.env`:

```dotenv
DEMO_MODE=false
UNIFI_SNMP_HOST=192.168.1.1
UNIFI_SNMP_USER=<snmp-v3-user>
UNIFI_SNMP_AUTH_PROTOCOL=sha
UNIFI_SNMP_PRIV_PROTOCOL=aes
UNIFI_SNMP_INTERFACES=<wan-interface>,<wan2-interface>
UNIFI_POLL_MS=250
UNIFI_RATE_WINDOW_MS=2000
UNIFI_SNMP_TIMEOUT_MS=3000
```

Store passwords in ignored files:

```text
secrets/unifi_snmp_auth_password
secrets/unifi_snmp_priv_password
```

Direct Node deployments may instead set `UNIFI_SNMP_AUTH_PASSWORD` and
`UNIFI_SNMP_PRIV_PASSWORD`. The macOS LaunchAgent uses a Keychain service. Do
not put passwords in tracked environment files, shell history, screenshots, or
logs.

The collector reads IF-MIB `ifHCInOctets` and `ifHCOutOctets` four times per
second. Each displayed value is calculated from the real counter delta over a
rolling two-second window. This keeps the 4 Hz visual cadence while covering
the gateway's approximately one-second counter refresh and timing jitter,
instead of showing zeros followed by a spike.

Multiple selected WAN interfaces are summed. The display keeps approximately
75 seconds of real samples. Use an authenticated `snmpwalk` against `ifName`
and `ifAlias` to discover exact selectors; do not infer an interface from its
table position. Keep UDP/161 reachable only from the trusted LAN or the
monitoring host.

Live readback must show:

```bash
curl -fsS http://<ambient-ops-host>:8787/api/status |
  jq -e '.demo == false
    and .network.status == "live"
    and .network.source == "unifi-snmp-v3"
    and (.network.interfaces | length) > 0'
```

## Network API fallback

The API path is optional and is not required for an SNMPv3 deployment. If it is
needed, create a dedicated read-only UniFi Network integration key and write it
to:

```text
secrets/unifi_api_key
```

Set:

```dotenv
DEMO_MODE=false
UNIFI_BASE_URL=https://gateway.example.lan
UNIFI_SITE=default
```

The implementation requests:

```text
/proxy/network/api/s/default/stat/health
```

It sends the key as `X-API-KEY` and reads WAN `rx_bytes-r` and `tx_bytes-r`.
Do not reuse the owner account password or place the key in a URL.

## API TLS option A: trusted-LAN self-signed certificate

```dotenv
UNIFI_BASE_URL=https://<gateway-address>
UNIFI_ALLOW_SELF_SIGNED=true
UNIFI_CA_FILE=
```

This disables certificate verification only for the dedicated UniFi HTTP
client. It does not affect Home Assistant or other Node connections. Use it
only on a trusted LAN or private VPN.

## API TLS option B: strict validation

The URL hostname must appear in the certificate Subject Alternative Name.
Export and inspect the public server certificate:

```bash
openssl s_client -connect <gateway-address>:443 -servername unifi.local -showcerts \
  </dev/null 2>/dev/null | openssl x509 -outform PEM > unifi-gateway.crt
openssl x509 -in unifi-gateway.crt -noout \
  -subject -issuer -dates -fingerprint -sha256 -ext subjectAltName
```

Keep the certificate in a private NAS folder and mount it read-only:

```yaml
services:
  ambient-ops:
    extra_hosts:
      - "unifi.local:<gateway-address>"
    volumes:
      - ./private/unifi-gateway.crt:/run/secrets/unifi-gateway.crt:ro
```

```dotenv
UNIFI_BASE_URL=https://unifi.local
UNIFI_ALLOW_SELF_SIGNED=false
UNIFI_CA_FILE=/run/secrets/unifi-gateway.crt
```

Re-check the SHA-256 fingerprint and expiry after UniFi upgrades, certificate
regeneration, or gateway replacement.
