# Prior Art and Build Decision

The following active projects were reviewed before choosing an independent
implementation:

- [Glance](https://github.com/glanceapp/glance): lightweight, attractive,
  single-container dashboard with custom widgets. Its general feed/widget model
  does not provide the required metric ingestion and dedicated kiosk/e-ink
  views; modifying it would also adopt AGPL-3.0 obligations.
- [Homepage](https://github.com/gethomepage/homepage): mature service dashboard
  with strong backend credential proxying. It is optimized for application
  launchers and integrations rather than a high-frequency fixed status screen,
  and carries a much larger Next.js configuration surface.
- [Homarr](https://github.com/homarr-labs/homarr): active and flexible, but its
  broad dashboard and user-management scope is substantially larger than this
  display appliance.
- [MagicMirror](https://github.com/MagicMirrorOrg/MagicMirror): mature modular
  display platform, but centered on Electron and display-host plugins rather
  than a NAS-hosted aggregation service consumed by interchangeable browsers.
- [Unpoller](https://github.com/unpoller/unpoller): deep UniFi telemetry via
  InfluxDB/Prometheus and Grafana. This is the strongest reusable route for
  long-term network observability. A full display stack still requires at
  least a poller, a time-series database, Grafana, and a Codex push adapter.
  UniFi itself normally refreshes traffic statistics at a lower cadence than
  the display animation, so the larger stack does not create genuinely
  higher-frequency source data.
- [Prometheus Pushgateway](https://github.com/prometheus/pushgateway): accepts
  pushed metrics but explicitly targets ephemeral batch jobs, provides no TTL,
  and is not an aggregator. Its semantics do not directly implement the
  required per-machine `LIVE`/`STALE`/`ERROR` model.
- [Home Assistant](https://github.com/home-assistant/core): already has a good
  UniFi integration, REST/MQTT extensibility, dashboards, and a strong e-ink
  ecosystem. It is a viable integration target when a home already runs Home
  Assistant. Introducing the entire platform only for this screen would be a
  larger operational dependency than the focused service.
- [Smashing](https://github.com/Smashing/smashing): an established TV dashboard
  framework with server-pushed widgets. It still requires custom collectors,
  persistence, freshness semantics, and screen templates, while adding a Ruby
  runtime not otherwise needed here.
- [hass-eink-dashboard](https://github.com/cryptomilk/hass-eink-dashboard) and
  similar e-ink projects: useful reference for low-refresh rendering, but tied
  to Home Assistant or a specific device pipeline.

The target combination remains unusual: UniFi WAN throughput, authenticated
multi-machine metric pushes, last-value freshness semantics, and multiple
screen-specific templates from one small container. A focused independent
service keeps those contracts explicit and avoids maintaining a fork of a much
larger dashboard product. A Prometheus-compatible export remains a natural
future extension for users who already run Grafana.

No source code from the reviewed projects is copied into this repository.
