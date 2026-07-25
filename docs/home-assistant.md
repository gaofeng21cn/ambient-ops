# Home Assistant Bridge

Home Assistant is an optional downstream consumer. Ambient Ops remains the
display and aggregation owner if Home Assistant is stopped or upgraded.

## Create a token

In Home Assistant, open the user profile, create a **Long-Lived Access Token**
named `Ambient Ops`, and copy it into the private deployment `.env`:

```dotenv
HA_ENABLED=true
HA_BASE_URL=http://home-assistant.example.lan:8123
HA_TOKEN=<long-lived-access-token>
HA_ENTITY_PREFIX=ambient_ops
HA_SYNC_MS=30000
```

Restart Ambient Ops and inspect `/healthz`. The `homeAssistant` object records
whether sync was requested, enabled, last attempted, last successful, or failed.
An unreachable Home Assistant instance does not stop collection or displays.

## Entities created

Ambient Ops writes these REST state entities:

- `sensor.ambient_ops_network_download_mbps`
- `sensor.ambient_ops_network_upload_mbps`
- `sensor.ambient_ops_codex_tps_1m`
- `sensor.ambient_ops_codex_tps_5m`
- `sensor.ambient_ops_active_sessions`
- `sensor.ambient_ops_machine_count`
- `sensor.ambient_ops_status`

They can be used in HA history, automations, and dashboards. No HACS component,
MQTT broker, or HA restart is required for the bridge itself. REST-created
states are transient HA runtime entities; Ambient Ops remains the source of
truth and refreshes them on its configured interval.
