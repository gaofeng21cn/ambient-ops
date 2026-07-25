# UniFi Setup

Ambient Ops polls the UniFi Network health endpoint with a dedicated API key.
It does not need an administrator password in the container.

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
