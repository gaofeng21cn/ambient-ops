import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct AmbientOpsWidgetBundle: WidgetBundle {
    var body: some Widget {
        AmbientLoadWidget()
        AmbientLoadLiveActivity()
    }
}

private struct AmbientLoadEntry: TimelineEntry {
    let date: Date
    let status: AmbientStatus
    let machine: MachineStatus
}

private final class TimelineCompletion: @unchecked Sendable {
    private let completion: (Timeline<AmbientLoadEntry>) -> Void

    init(_ completion: @escaping (Timeline<AmbientLoadEntry>) -> Void) {
        self.completion = completion
    }

    func callAsFunction(_ timeline: Timeline<AmbientLoadEntry>) {
        completion(timeline)
    }
}

private struct AmbientLoadProvider: TimelineProvider {
    private let client = SharedStatusClient()

    func placeholder(in context: Context) -> AmbientLoadEntry {
        entry()
    }

    func getSnapshot(in context: Context, completion: @escaping (AmbientLoadEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AmbientLoadEntry>) -> Void) {
        let completion = TimelineCompletion(completion)
        Task {
            let nextEntry = await refreshedEntry()
            completion(
                Timeline(
                    entries: [nextEntry],
                    policy: .after(.now.addingTimeInterval(5 * 60))
                )
            )
        }
    }

    private func entry() -> AmbientLoadEntry {
        let stored = SharedSnapshotStore.load()
        let status = stored?.status ?? DemoFixtures.status()
        let machine = status.focusedMachine(preferredID: stored?.focusedMachineID)
            ?? DemoFixtures.status().machines[0]
        return AmbientLoadEntry(date: .now, status: status, machine: machine)
    }

    private func refreshedEntry() async -> AmbientLoadEntry {
        guard let sourceURL = SharedSnapshotStore.sourceURL(),
              let status = try? await client.fetchStatus(from: sourceURL),
              let machine = status.focusedMachine(
                preferredID: SharedSnapshotStore.load()?.focusedMachineID
              ) else {
            return entry()
        }
        SharedSnapshotStore.save(status, focusedMachineID: machine.machineId)
        return AmbientLoadEntry(date: .now, status: status, machine: machine)
    }
}

struct AmbientLoadWidget: Widget {
    let kind = "ambient-load"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AmbientLoadProvider()) { entry in
            AmbientLoadWidgetView(entry: entry)
                .containerBackground(AmbientTheme.surface, for: .widget)
        }
        .configurationDisplayName("Codex Load")
        .description("See the focused Codex host's current development load.")
        .supportedFamilies([.accessoryRectangular, .systemSmall, .systemMedium])
    }
}

private struct AmbientLoadWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AmbientLoadEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            accessory
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.machine.machineName)
                    .lineLimit(1)
                Spacer()
                Text(LoadStatePalette.label(for: entry.machine.loadVisualState.state))
                    .fontWeight(.bold)
            }
            .font(.caption)
            HStack(spacing: 6) {
                Text("\(MetricFormat.tps(entry.machine.oneMinute.tps)) TPS")
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text("·")
                Text("\(MetricFormat.integer(entry.machine.activeSessions)) active")
            }
            .font(.caption2)
            LoadGlyph(visual: entry.machine.loadVisualState)
                .frame(height: 7)
        }
        .widgetURL(URL(string: "ambientops://display/load"))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "waveform.path.ecg.rectangle")
                Spacer()
                Circle()
                    .fill(AmbientTheme.statusColor(entry.machine.status))
                    .frame(width: 7, height: 7)
            }
            Text(LoadStatePalette.label(for: entry.machine.loadVisualState.state))
                .font(.headline)
                .foregroundStyle(AmbientTheme.statusColor(entry.machine.loadVisualState.state))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(entry.machine.machineName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("\(MetricFormat.tps(entry.machine.oneMinute.tps)) TPS")
                .font(.title3.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            LoadGlyph(visual: entry.machine.loadVisualState)
                .frame(height: 12)
        }
        .widgetURL(URL(string: "ambientops://display/load"))
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.machine.machineName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(LoadStatePalette.label(for: entry.machine.loadVisualState.state))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AmbientTheme.statusColor(entry.machine.loadVisualState.state))
                Spacer()
                Text("\(MetricFormat.tps(entry.machine.oneMinute.tps)) TPS")
                    .font(.title.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            LoadGlyph(visual: entry.machine.loadVisualState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .widgetURL(URL(string: "ambientops://display/load"))
    }
}

private struct LoadGlyph: View {
    let visual: LoadVisualState

    var body: some View {
        Canvas { context, size in
            let color = AmbientTheme.statusColor(visual.state)
            let count = visual.clusterCount == 0 ? 0 : Int(8 + visual.taskDensity * 26)
            let bands = max(1, visual.clusterCount)

            let baseline = Path(CGRect(x: 0, y: size.height / 2, width: size.width, height: 1))
            context.fill(baseline, with: .color(.secondary.opacity(0.18)))

            for index in 0..<count {
                let progress = CGFloat(index + 1) / CGFloat(max(1, count + 1))
                let band = CGFloat(index % bands) - CGFloat(bands - 1) / 2
                let y = size.height / 2 + band * min(9, size.height / CGFloat(bands + 1))
                let rect = CGRect(
                    x: progress * size.width,
                    y: y,
                    width: index.isMultiple(of: 6) ? 4 : 2,
                    height: 2
                )
                context.fill(Path(rect), with: .color(index.isMultiple(of: 5) ? AmbientTheme.blue : color))
            }
        }
        .accessibilityHidden(true)
    }
}

struct AmbientLoadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LoadActivityAttributes.self) { context in
            LiveActivitySurface(state: context.state)
                .activityBackgroundTint(AmbientTheme.surface)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.machineName)
                            .font(.caption)
                            .lineLimit(1)
                        Text(LoadStatePalette.label(for: context.state.state))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AmbientTheme.statusColor(context.state.state))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(MetricFormat.tps(context.state.tps))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label("\(MetricFormat.integer(context.state.activeSessions))", systemImage: "bubble.left.and.bubble.right")
                        Spacer()
                        Text("CPU \(MetricFormat.percent(context.state.cpuPercent))")
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(AmbientTheme.statusColor(context.state.state))
            } compactTrailing: {
                Text(MetricFormat.tps(context.state.tps))
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            } minimal: {
                Circle()
                    .fill(AmbientTheme.statusColor(context.state.state))
            }
            .widgetURL(URL(string: "ambientops://display/load"))
            .keylineTint(AmbientTheme.statusColor(context.state.state))
        }
    }
}

private struct LiveActivitySurface: View {
    let state: LoadActivityAttributes.ContentState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            standBy
                .frame(minWidth: 520)
            lockScreen
        }
        .widgetURL(URL(string: "ambientops://display/load"))
    }

    private var standBy: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.machineName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(LoadStatePalette.label(for: state.state))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmbientTheme.statusColor(state.state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                HStack(spacing: 14) {
                    Label("\(MetricFormat.tps(state.tps)) TPS", systemImage: "waveform.path.ecg")
                    Label(
                        "\(MetricFormat.integer(state.activeSessions)) active",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    Text("CPU \(MetricFormat.percent(state.cpuPercent))")
                }
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            glyph
                .frame(minWidth: 180, idealWidth: 260, maxWidth: 320, minHeight: 72, idealHeight: 90)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var lockScreen: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.machineName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(LoadStatePalette.label(for: state.state))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AmbientTheme.statusColor(state.state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                ViewThatFits(in: .horizontal) {
                    Text(
                        "\(MetricFormat.tps(state.tps)) TPS · "
                            + "\(MetricFormat.integer(state.activeSessions)) active"
                    )
                    Text("\(MetricFormat.tps(state.tps)) TPS")
                }
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            glyph
                .frame(width: 68, height: 44)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var glyph: some View {
        LoadGlyph(visual: activityVisual)
    }

    private var activityVisual: LoadVisualState {
        state.visual ?? LoadVisualState(
            modelVersion: nil,
            state: state.state,
            label: state.state.uppercased(),
            score: state.score,
            constrained: state.state == "constrained",
            activity: state.score,
            parallel: min(1, state.activeSessions / 12),
            tempo: 1,
            travelMs: 1_500,
            clusterCount: max(1, min(4, Int(state.activeSessions / 3))),
            taskDensity: state.score,
            pressure: state.state == "constrained" ? 1 : 0,
            queueDepth: state.state == "constrained" ? 1 : 0,
            heat: state.state == "constrained" ? 1 : 0
        )
    }
}
