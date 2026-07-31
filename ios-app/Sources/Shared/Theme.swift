import SwiftUI

enum AmbientTheme {
    static let background = Color(red: 0.025, green: 0.035, blue: 0.045)
    static let surface = Color(red: 0.055, green: 0.071, blue: 0.083)
    static let elevated = Color(red: 0.075, green: 0.094, blue: 0.106)
    static let line = Color.white.opacity(0.1)
    static let muted = Color(red: 0.47, green: 0.52, blue: 0.56)
    static let green = Color(red: 0.22, green: 0.85, blue: 0.57)
    static let blue = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let purple = Color(red: 0.70, green: 0.46, blue: 0.96)
    static let amber = Color(red: 1.0, green: 0.71, blue: 0.30)
    static let red = Color(red: 1.0, green: 0.36, blue: 0.42)

    static func statusColor(_ status: String) -> Color {
        switch status {
        case "live", "active": green
        case "stale", "heavy": amber
        case "error", "constrained", "failed": red
        case "quiet", "idle": .secondary
        default: muted
        }
    }
}

struct StatusPill: View {
    let status: String
    var label: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AmbientTheme.statusColor(status))
                .frame(width: 7, height: 7)
            Text(label ?? status.uppercased())
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(AmbientTheme.statusColor(status))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(AmbientTheme.statusColor(status).opacity(0.1))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(AmbientTheme.statusColor(status).opacity(0.28))
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
    }
}

struct OpsPanel<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmbientTheme.muted)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AmbientTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(AmbientTheme.line)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct MetricValue: View {
    let label: String
    let value: String
    var unit: String? = nil
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AmbientTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(AmbientTheme.muted)
                }
            }
        }
    }
}

enum MetricFormat {
    static func tps(_ value: Double) -> String {
        if value >= 100_000 {
            return String(format: "%.0fk", value / 1_000)
        }
        if value >= 10_000 {
            return String(format: "%.1fk", value / 1_000)
        }
        if value >= 1_000 {
            return String(format: "%.2fk", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    static func decimal(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: value >= 100 ? "%.0f" : "%.1f", value)
    }

    static func integer(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return "\(Int(value.rounded()))%"
    }
}
