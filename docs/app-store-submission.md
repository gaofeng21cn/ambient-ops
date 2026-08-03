# App Store Submission Draft

This is submission metadata for the native OPL Fleet Cockpit iOS and iPadOS
client. The Apple identity starts at build 1.

## Identity

- App name: `OPL Cockpit`
- App Store Connect ID: `6797375745`
- Bundle ID: `cn.gaofeng.oplfleetcockpit`
- Widget Bundle ID: `cn.gaofeng.oplfleetcockpit.widgets`
- App Group: `group.cn.gaofeng.oplfleetcockpit`
- SKU: `opl-fleet-cockpit-ios-2026`
- App Store profile: `OPL Cockpit App Store 2026`
- Widget App Store profile: `OPL Cockpit Widgets App Store 2026`
- Primary category: `Utilities`
- Secondary category: `Developer Tools`
- Age rating: `4+`
- Copyright: `2026 Feng Gao`

## Store text

Subtitle:

> Your self-hosted fleet display

Promotional text:

> See aggregate Codex activity, host pressure, network throughput, and your Codex
> Pet across iPhone, Widgets, Live Activities, Dynamic Island, and StandBy.

Description:

> OPL Fleet Cockpit is the native iPhone and iPad companion for your self-hosted
> OPL Fleet Telemetry Gateway.
>
> See the operational state that matters at a glance:
>
> • Focused-host Codex load expressed as a live pixel work field
> • Aggregate tokens per second and active sessions
> • Optional host CPU and memory pressure
> • Network download, upload, latency, clients, and recent trends
> • Machine freshness and Codex Pet state
> • Lock Screen Widgets, Live Activities, Dynamic Island, and StandBy
>
> The built-in Demo Mode is fully functional and needs no account or server.
> When you connect your own gateway, OPL Fleet Cockpit discovers it on your local
> network or uses the address you enter.
>
> Privacy is part of the architecture. Prompts, responses, session identifiers,
> tool content, repository paths, and credentials are not part of the status
> contract. The app does not use advertising or third-party analytics.
>
> OPL Fleet Cockpit is designed for trusted local networks. Remote access should
> use HTTPS with access control or a private VPN.

Keywords:

`Codex,developer,monitor,self-hosted,server,network,widget,live activity,operations`

## Public URLs

- Support URL: `https://github.com/gaofeng21cn/opl-fleet-cockpit/blob/main/docs/ios-support.md`
- Privacy policy URL: `https://github.com/gaofeng21cn/opl-fleet-cockpit/blob/main/docs/privacy-policy.md`
- Marketing URL: `https://github.com/gaofeng21cn/opl-fleet-cockpit`

These URLs become valid only after the corresponding files are on the public
canonical branch.

## App Review notes

> OPL Fleet Cockpit opens in a complete Demo Mode. No account, server,
> credentials, or local-network permission is needed for review.
>
> Review path:
>
> 1. Home shows live aggregate Codex and network status.
> 2. Machines contains quiet, active, heavy, constrained, and stale examples.
> 3. Display contains Overview, Network, Load, and Pet. Load uses a native SpriteKit
>    animation; it is not a web view.
> 4. Settings can start a local Live Activity for the focused demo host.
>
> Local-network discovery is optional and is invoked only when the reviewer chooses
> Find on Local Network. No OPL-operated cloud service is required.

## Privacy labels

Suggested App Privacy response: `Data Not Collected`.

The app has no developer-operated analytics, advertising, account, or relay in this
release. It reads operational data from a server selected and controlled by the user,
stores the latest aggregate snapshot locally, and shares it only with its bundled
Widget/Live Activity extension.

Reassess this answer before enabling any future APNs relay, analytics, crash upload,
or developer-operated service.

## Remaining submission inputs

- final iPhone and iPad screenshots captured from signed build 1;
- App Review contact phone number in international format;
- assign processed build 1 to App Store version 1.0;
- complete categories, age rating, App Privacy, pricing, and territories;
- export-compliance answers;
- territory choice, including whether mainland China distribution will be enabled;
- version release mode and review submission approval.

## Current distribution state

- App Store Connect record `6797375745` exists as `OPL Cockpit`.
- Signed archive `1.0.0 (1)` uses Apple Distribution identity `SVVC4TA784`
  and the two App Store profiles above.
- Build `1.0.0 (1)` has been uploaded and processed by App Store Connect.
- The internal `Automatic Testers` group contains build 1 and the account
  holder as its first tester.

## Legacy Apple identity

The former `cn.gaofeng.ambientops` App ID is not used by this project or by new
builds. Apple refuses to remove it because it has previously been associated
with the App Store, so it remains only as a non-reusable historical identifier
in the Developer portal. The former widget App ID has been removed.
