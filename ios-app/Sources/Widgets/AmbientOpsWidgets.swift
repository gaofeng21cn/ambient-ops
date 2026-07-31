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
                .environment(\.colorScheme, .dark)
                .containerBackground(AmbientTheme.surface, for: .widget)
        }
        .configurationDisplayName("Codex Load")
        .description("See the focused Codex host's current development load.")
        .supportedFamilies([.accessoryRectangular, .systemSmall, .systemMedium])
        .contentMarginsDisabled()
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
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(MetricFormat.tps(entry.machine.oneMinute.tps))
                    .font(.headline.monospacedDigit().weight(.bold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .layoutPriority(1)
                Text("TPS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                LoadStateBadge(state: entry.machine.loadVisualState.state, compact: true)
            }
            HStack(spacing: 5) {
                Text(entry.machine.machineName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 2)
                Label(
                    MetricFormat.integer(entry.machine.activeSessions),
                    systemImage: "bubble.left.and.bubble.right.fill"
                )
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
            }
            .font(.caption2)
            LoadGlyph(
                visual: entry.machine.loadVisualState,
                phase: entry.date,
                compact: true
            )
            .frame(height: 8)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .widgetURL(URL(string: "ambientops://display/load"))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                LoadPulse(state: entry.machine.loadVisualState.state, phase: entry.date)
                Text(entry.machine.machineName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 3)
                Circle()
                    .fill(AmbientTheme.statusColor(entry.machine.status))
                    .frame(width: 7, height: 7)
            }

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(MetricFormat.tps(entry.machine.oneMinute.tps))
                    .font(.system(size: 29, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                Text("TPS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
            }

            LoadGlyph(visual: entry.machine.loadVisualState, phase: entry.date)
                .frame(maxHeight: .infinity)

            HStack(alignment: .bottom, spacing: 9) {
                Text(LoadStatePalette.compactLabel(for: entry.machine.loadVisualState.state))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AmbientTheme.statusColor(entry.machine.loadVisualState.state))
                    .lineLimit(1)
                    .accessibilityLabel(
                        LoadStatePalette.label(for: entry.machine.loadVisualState.state)
                    )
                Spacer(minLength: 4)
                CompactMetric(
                    label: "ACT",
                    value: MetricFormat.integer(entry.machine.activeSessions)
                )
                CompactMetric(
                    label: "CPU",
                    value: MetricFormat.percent(entry.machine.cpuPercent)
                )
            }
        }
        .padding(12)
        .widgetURL(URL(string: "ambientops://display/load"))
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                LoadPulse(state: entry.machine.loadVisualState.state, phase: entry.date)
                Text(entry.machine.machineName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                LoadStateBadge(state: entry.machine.loadVisualState.state)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(MetricFormat.tps(entry.machine.oneMinute.tps))
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("TPS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 20) {
                        CompactMetric(
                            label: "ACTIVE",
                            value: MetricFormat.integer(entry.machine.activeSessions)
                        )
                        CompactMetric(
                            label: "CPU",
                            value: MetricFormat.percent(entry.machine.cpuPercent)
                        )
                    }
                }
                .frame(maxWidth: 150, alignment: .leading)

                LoadGlyph(visual: entry.machine.loadVisualState, phase: entry.date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .widgetURL(URL(string: "ambientops://display/load"))
    }
}

private struct LoadGlyph: View {
    let visual: LoadVisualState
    var phase: Date = .now
    var compact = false

    var body: some View {
        Canvas { context, size in
            let color = AmbientTheme.statusColor(visual.state)
            let laneCount = max(1, min(4, visual.clusterCount))
            let hasWork = visual.clusterCount > 0 && visual.taskDensity > 0.01
            let inset = compact ? CGFloat(1) : CGFloat(4)
            let usableHeight = max(1, size.height - inset * 2)
            let laneSpacing = usableHeight / CGFloat(laneCount)
            let packetsPerLane = max(1, Int(2 + visual.taskDensity.clamped(to: 0...1) * 5))
            let travelSeconds = max(0.75, visual.travelMs / 1_000)
            let timePhase = phase.timeIntervalSinceReferenceDate / travelSeconds
            let packetHeight = max(1.5, min(compact ? 2 : 4, laneSpacing * 0.34))
            let trackEnd = max(inset + 8, size.width - inset - 7)

            for lane in 0..<laneCount {
                let y = inset + laneSpacing * (CGFloat(lane) + 0.5)
                let track = Path(
                    CGRect(
                        x: inset,
                        y: y - 0.5,
                        width: max(1, trackEnd - inset),
                        height: 1
                    )
                )
                context.fill(track, with: .color(.secondary.opacity(hasWork ? 0.22 : 0.12)))

                var arrow = Path()
                arrow.move(to: CGPoint(x: size.width - inset - 6, y: y - 3))
                arrow.addLine(to: CGPoint(x: size.width - inset, y: y))
                arrow.addLine(to: CGPoint(x: size.width - inset - 6, y: y + 3))
                context.stroke(arrow, with: .color(color.opacity(hasWork ? 0.55 : 0.18)), lineWidth: 1)

                guard hasWork else { continue }
                for packet in 0..<packetsPerLane {
                    let seed = Double(packet) / Double(packetsPerLane)
                        + Double(lane) * 0.173
                    let speed = max(0.25, visual.tempo) * (0.12 + Double(lane) * 0.012)
                    let progress = (seed + timePhase * speed).truncatingRemainder(dividingBy: 1)
                    let packetWidth = CGFloat(packet.isMultiple(of: 3) ? 8 : 5)
                    let x = inset + CGFloat(progress) * max(1, trackEnd - inset - packetWidth)
                    let packetRect = CGRect(
                        x: x,
                        y: y - packetHeight / 2,
                        width: packetWidth,
                        height: packetHeight
                    )
                    let packetColor = packet.isMultiple(of: 4) ? AmbientTheme.blue : color
                    context.fill(
                        Path(packetRect),
                        with: .color(packetColor.opacity(0.62 + visual.heat.clamped(to: 0...1) * 0.3))
                    )
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: compact ? 2 : 4)
                .fill(AmbientTheme.elevated.opacity(compact ? 0.28 : 0.58))
                .overlay(alignment: .top) {
                    if visual.pressure > 0.15 {
                        Rectangle()
                            .fill(AmbientTheme.statusColor(visual.state).opacity(0.5))
                            .frame(height: 1)
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 2 : 4))
        .animation(.easeOut(duration: 0.45), value: visual.normalizedScore)
        .accessibilityHidden(true)
    }
}

private struct LoadPulse: View {
    let state: String
    let phase: Date

    var body: some View {
        Image(systemName: "bolt.horizontal.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(AmbientTheme.statusColor(state))
            .symbolEffect(.pulse.byLayer, value: phase)
            .accessibilityHidden(true)
    }
}

private struct LoadStateBadge: View {
    let state: String
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Circle()
                .fill(AmbientTheme.statusColor(state))
                .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
            Text(compact ? LoadStatePalette.compactLabel(for: state) : LoadStatePalette.label(for: state))
                .lineLimit(1)
        }
        .font((compact ? Font.caption2 : .caption).weight(.bold))
        .foregroundStyle(AmbientTheme.statusColor(state))
        .padding(.horizontal, compact ? 5 : 8)
        .frame(height: compact ? 18 : 24)
        .background(AmbientTheme.statusColor(state).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel(LoadStatePalette.label(for: state))
    }
}

private struct CompactMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

struct AmbientLoadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LoadActivityAttributes.self) { context in
            LiveActivitySurface(state: context.state)
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(AmbientTheme.surface)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.machineName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        LoadStateBadge(state: context.state.state, compact: true)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(MetricFormat.tps(context.state.tps))
                            .font(.title3.monospacedDigit().weight(.bold))
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                        Text("TPS")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 5) {
                        LoadGlyph(
                            visual: visual(for: context.state),
                            phase: context.state.updatedAt,
                            compact: true
                        )
                        .frame(height: 12)
                        HStack {
                            Label(
                                MetricFormat.integer(context.state.activeSessions),
                                systemImage: "bubble.left.and.bubble.right.fill"
                            )
                            Spacer()
                            Text("CPU \(MetricFormat.percent(context.state.cpuPercent))")
                        }
                        .font(.caption2.monospacedDigit().weight(.semibold))
                    }
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

    private func visual(for state: LoadActivityAttributes.ContentState) -> LoadVisualState {
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

private struct LiveActivitySurface: View {
    let state: LoadActivityAttributes.ContentState

    var body: some View {
        ViewThatFits(in: [.horizontal, .vertical]) {
            standBy
                .frame(minWidth: 560, minHeight: 170)
            lockScreen
        }
        .widgetURL(URL(string: "ambientops://display/load"))
    }

    private var standBy: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    LoadPulse(state: state.state, phase: state.updatedAt)
                    Text(state.machineName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(LoadStatePalette.label(for: state.state))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(AmbientTheme.statusColor(state.state))
                    .contentTransition(.interpolate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)

                HStack(alignment: .lastTextBaseline, spacing: 7) {
                    Text(MetricFormat.tps(state.tps))
                        .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Text("TPS")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 310, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 28) {
                    CompactMetric(
                        label: "ACTIVE",
                        value: MetricFormat.integer(state.activeSessions)
                    )
                    CompactMetric(label: "CPU", value: MetricFormat.percent(state.cpuPercent))
                }

                LoadGlyph(visual: activityVisual, phase: state.updatedAt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 8) {
                    Text("LIVE CODEX LOAD")
                    Spacer(minLength: 8)
                    Text(state.updatedAt, style: .relative)
                        .contentTransition(.numericText())
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                LoadPulse(state: state.state, phase: state.updatedAt)
                Text(state.machineName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 5)
                LoadStateBadge(state: state.state, compact: true)
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(MetricFormat.tps(state.tps))
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .layoutPriority(1)
                Text("TPS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                CompactMetric(
                    label: "ACTIVE",
                    value: MetricFormat.integer(state.activeSessions)
                )
                .frame(minWidth: 36, alignment: .leading)
                CompactMetric(label: "CPU", value: MetricFormat.percent(state.cpuPercent))
                    .frame(minWidth: 40, alignment: .leading)
            }

            LoadGlyph(visual: activityVisual, phase: state.updatedAt, compact: true)
                .frame(height: 18)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
