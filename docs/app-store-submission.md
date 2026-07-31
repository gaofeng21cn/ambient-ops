# App Store Submission Draft

This is submission metadata for the native Ambient Ops iOS client. Creating an
App Store Connect record, uploading an archive, choosing territories, and releasing
the app remain explicit distribution actions.

## Identity

- App name: `Ambient Ops`
- Bundle ID: `cn.gaofeng.ambientops`
- SKU suggestion: `ambient-ops-ios-1`
- Primary category: `Utilities`
- Secondary category: `Developer Tools`
- Age rating: `4+`
- Copyright: `2026 Feng Gao`

## Store text

Subtitle:

> Your self-hosted Codex load display

Promotional text:

> See aggregate Codex activity, host pressure, network throughput, and your Codex
> Pet across iPhone, Widgets, Live Activities, Dynamic Island, and StandBy.

Description:

> Ambient Ops is the native iPhone companion for your self-hosted Ambient Ops
> server.
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
> When you connect your own server, Ambient Ops discovers it on your local network
> or uses the address you enter.
>
> Privacy is part of the architecture. Prompts, responses, session identifiers,
> tool content, repository paths, and credentials are not part of the status
> contract. The app does not use advertising or third-party analytics.
>
> Ambient Ops is designed for trusted local networks. Remote access should use
> HTTPS with access control or a private VPN.

Keywords:

`Codex,developer,monitor,self-hosted,server,network,widget,live activity,operations`

## Public URLs

- Support URL: `https://github.com/gaofeng21cn/ambient-ops/blob/main/docs/ios-support.md`
- Privacy policy URL: `https://github.com/gaofeng21cn/ambient-ops/blob/main/docs/privacy-policy.md`
- Marketing URL: `https://github.com/gaofeng21cn/ambient-ops`

These URLs become valid only after the corresponding files are on the public
canonical branch.

## App Review notes

> Ambient Ops opens in a complete Demo Mode. No account, server, credentials, or
> local-network permission is needed for review.
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
> Find on Local Network. No Ambient Ops cloud service is required.

## Privacy labels

Suggested App Privacy response: `Data Not Collected`.

The app has no developer-operated analytics, advertising, account, or relay in this
release. It reads operational data from a server selected and controlled by the user,
stores the latest aggregate snapshot locally, and shares it only with its bundled
Widget/Live Activity extension.

Reassess this answer before enabling any future APNs relay, analytics, crash upload,
or developer-operated service.

## Remaining submission inputs

- final App Store screenshots captured from the signed Release candidate;
- an App Store Connect app record;
- signed archive validation and upload;
- export-compliance answers;
- territory choice, including whether mainland China distribution will be enabled;
- version release mode and review submission approval.
