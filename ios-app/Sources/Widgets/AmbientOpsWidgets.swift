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

private struct AmbientLoadProvider: TimelineProvider {
    func placeholder(in context: Context) -> AmbientLoadEntry {
        entry()
    }

    func getSnapshot(in context: Context, completion: @escaping (AmbientLoadEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AmbientLoadEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> AmbientLoadEntry {
        let stored = SharedSnapshotStore.load()
        let status = stored?.status ?? DemoFixtures.status()
        let machine = status.focusedMachine(preferredID: stored?.focusedMachineID)
            ?? DemoFixtures.status().machines[0]
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
            LiveActivityLockScreen(context: context)
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
            } minimal: {
                Circle()
                    .fill(AmbientTheme.statusColor(context.state.state))
            }
            .widgetURL(URL(string: "ambientops://display/load"))
            .keylineTint(AmbientTheme.statusColor(context.state.state))
        }
    }
}

private struct LiveActivityLockScreen: View {
    let context: ActivityViewContext<LoadActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.machineName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(LoadStatePalette.label(for: context.state.state))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AmbientTheme.statusColor(context.state.state))
                Text("\(MetricFormat.tps(context.state.tps)) TPS · \(MetricFormat.integer(context.state.activeSessions)) active")
                    .font(.caption.monospacedDigit())
            }
            Spacer()
            LoadGlyph(
                visual: LoadVisualState(
                    state: context.state.state,
                    label: context.state.state.uppercased(),
                    score: context.state.score,
                    constrained: context.state.state == "constrained",
                    activity: context.state.score,
                    parallel: min(1, context.state.activeSessions / 12),
                    tempo: 1,
                    travelMs: 1_500,
                    clusterCount: max(1, min(4, Int(context.state.activeSessions / 3))),
                    taskDensity: context.state.score,
                    pressure: context.state.state == "constrained" ? 1 : 0,
                    queueDepth: context.state.state == "constrained" ? 1 : 0,
                    heat: context.state.state == "constrained" ? 1 : 0
                )
            )
            .frame(width: 90, height: 54)
        }
        .padding(.horizontal, 4)
        .widgetURL(URL(string: "ambientops://display/load"))
    }
}
