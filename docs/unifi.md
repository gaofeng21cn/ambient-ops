# UniFi Setup

Ambient Ops can read WAN throughput with SNMPv3 or the UniFi Network API.
SNMPv3 is preferred when it is already enabled because it avoids a controller
API credential and exposes standard 64-bit interface counters.

## SNMPv3

Enable SNMPv3 `authPriv` in UniFi Network and configure the existing username,
authentication password, privacy password, and WAN interface names or indexes:

```dotenv
DEMO_MODE=false
UNIFI_SNMP_HOST=192.168.1.1
UNIFI_SNMP_USER=<snmp-v3-user>
UNIFI_SNMP_AUTH_PASSWORD=<private-password>
UNIFI_SNMP_PRIV_PASSWORD=<private-password>
UNIFI_SNMP_AUTH_PROTOCOL=sha
UNIFI_SNMP_PRIV_PROTOCOL=aes
UNIFI_SNMP_INTERFACES=<wan-interface>,<wan2-interface>
UNIFI_POLL_MS=250
UNIFI_RATE_WINDOW_MS=2000
```

The collector reads IF-MIB `ifHCInOctets` and `ifHCOutOctets` four times per
second. Each displayed value is calculated from the real counter delta over a
rolling two-second window. This preserves the 4 Hz display cadence while
covering the roughly one-second counter refresh and its observed timing jitter,
instead of showing zero readings followed by a spike. Multiple selected WAN
interfaces are summed, and the display keeps roughly 75 seconds of real samples. Use
`snmpwalk` against `ifName` and `ifAlias` to discover the exact selectors; do
not guess an interface from its position in the table.

Keep SNMP UDP/161 reachable only from the trusted LAN or the monitoring host.
Passwords stay in private deployment configuration and never reach the display.

## Network API

## Create a dedicated API key

UniFi OS labels have changed between releases. On current consoles, sign in to
the console owner interface and look under **Settings** for **Control Plane** or
**Admins & Users**, then open **Integrations / API Keys**. Create a key named
`Ambient Ops` and give it read-only access to the Network application and the
target site. Copy the key once into the private deployment `.env`:

```dotenv
DEMO_MODE=false
UNIFI_BASE_URL=https://gateway.example.lan
UNIFI_SITE=default
UNIFI_API_KEY=<private-api-key>
```

If the console only offers administrator roles rather than scoped API keys,
update UniFi OS first or create a dedicated local read-only account and API key.
Do not reuse the owner account password, and do not place the key in a browser
URL or a tracked Compose file.

The endpoint used by the current implementation is:

```text
/proxy/network/api/s/default/stat/health
```

The request sends the key as `X-API-KEY` and reads WAN `rx_bytes-r` and
`tx_bytes-r` fields.

## TLS option A: local self-signed certificate

The simplest trusted-LAN setup is:

```dotenv
UNIFI_BASE_URL=https://<gateway-address>
UNIFI_ALLOW_SELF_SIGNED=true
UNIFI_CA_FILE=
```

This disables certificate verification only for the dedicated UniFi HTTP
agent. It does not change TLS behavior for Home Assistant or other Node
connections. Use this only on a trusted LAN or private VPN.

## TLS option B: strict certificate validation

For strict validation, the URL hostname must appear in the certificate's
Subject Alternative Name. Export the public server certificate:

```bash
openssl s_client -connect <gateway-address>:443 -servername unifi.local -showcerts \
  </dev/null 2>/dev/null | openssl x509 -outform PEM > unifi-gateway.crt
openssl x509 -in unifi-gateway.crt -noout -subject -issuer -dates -fingerprint -sha256 -ext subjectAltName
```

Keep the certificate in a private NAS folder, mount it read-only, and use the
matching hostname:

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

Do not commit the certificate or the private override. A server certificate is
not a secret, but keeping environment-specific trust material outside the
portable repository avoids silently trusting the wrong gateway after a device
replacement. Re-check the SHA-256 fingerprint and expiry after UniFi upgrades
or certificate regeneration.
