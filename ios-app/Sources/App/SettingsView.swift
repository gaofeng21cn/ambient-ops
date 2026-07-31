import SwiftUI

struct SettingsView: View {
    @Bindable var store: AmbientOpsStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @FocusState private var isServerAddressFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    HStack(spacing: 12) {
                        Image(systemName: connectionIcon)
                            .font(.title3)
                            .foregroundStyle(connectionColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Current source")
                                .font(.caption)
                                .foregroundStyle(AmbientTheme.muted)
                            Text(currentSourceName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(currentSourceDetail)
                                .font(.caption)
                                .foregroundStyle(AmbientTheme.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        connectionBadge
                    }
                    .padding(.vertical, 4)

                    Button(
                        store.isDiscovering ? "Search Again" : "Find on Local Network",
                        systemImage: "dot.radiowaves.left.and.right"
                    ) {
                        store.startDiscovery()
                    }
                }

                if !store.discoveredServers.isEmpty {
                    Section("Nearby sources") {
                        ForEach(store.discoveredServers) { server in
                            Button {
                                store.choose(server)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(server.name)
                                        Spacer()
                                        Text(server.kind.providerLabel)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(
                                                server.kind == .gateway
                                                    ? AmbientTheme.blue
                                                    : AmbientTheme.green
                                            )
                                    }
                                    Text(server.url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(AmbientTheme.muted)
                                }
                            }
                        }
                    }
                }

                Section("Manual Connection") {
                    TextField("http://ambient-ops.local:8787", text: $store.serverAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .focused($isServerAddressFocused)
                        .submitLabel(.done)
                        .onSubmit { isServerAddressFocused = false }

                    Button("Connect", systemImage: "arrow.trianglehead.2.clockwise") {
                        Task { await store.connect() }
                    }
                    .disabled(store.serverAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("StandBy & Lock Screen") {
                    Button {
                        guard let machine = store.selectedMachine else { return }
                        Task { await store.liveActivity.start(status: store.status, machine: machine) }
                    } label: {
                        if store.liveActivity.isActive {
                            Label("Restart Load Live Activity", systemImage: "bolt.horizontal.circle")
                        } else {
                            Label("Start Load Live Activity", systemImage: "bolt.horizontal.circle")
                        }
                    }
                    .disabled(store.selectedMachine == nil)

                    if store.liveActivity.isActive {
                        Button("End Live Activity", systemImage: "stop.circle", role: .destructive) {
                            Task { await store.liveActivity.end() }
                        }
                    }

                    Text("Live Activity shows the focused host on the Lock Screen, Dynamic Island, and StandBy. It updates while the app can refresh; remote background updates require the optional push relay.")
                        .font(.footnote)
                        .foregroundStyle(AmbientTheme.muted)

                    if let message = store.liveActivity.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(AmbientTheme.red)
                    }
                }

                Section("Privacy") {
                    LabeledContent("Conversation content", value: "Never collected")
                    LabeledContent("Session identifiers", value: "Never collected")
                    LabeledContent("Metrics", value: "Aggregate only")
                    Text("The app reads your self-hosted Ambient Ops status. It does not need Codex credentials or router credentials.")
                        .font(.footnote)
                        .foregroundStyle(AmbientTheme.muted)
                }

                Section("About") {
                    LabeledContent("Source", value: store.providerLabel)
                    LabeledContent("Status schema", value: "v\(store.status.schemaVersion)")
                    LabeledContent("Server", value: store.status.serverVersion)
                    LabeledContent("Push relay") {
                        Text(
                            store.status.capabilities.liveActivityPush
                                ? String(localized: "Available")
                                : String(localized: "Not configured")
                        )
                    }
                }

                Section("Preview") {
                    Toggle(
                        "Demo Mode",
                        isOn: Binding(
                            get: { store.isDemoMode },
                            set: { enabled in
                                if enabled {
                                    store.useDemoMode()
                                } else {
                                    store.useAutomaticSourceMode()
                                }
                            }
                        )
                    )
                    Text("Demo Mode uses sample fleet data for preview and App Store review.")
                        .font(.footnote)
                        .foregroundStyle(AmbientTheme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaPadding(.bottom, verticalSizeClass == .compact ? 58 : 0)
            .background(AmbientTheme.background)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isServerAddressFocused = false
                    }
                }
            }
        }
    }

    private var currentSourceName: String {
        if store.isDemoMode {
            return String(localized: "Demo data")
        }
        switch store.connectionState {
        case .live, .stale:
            return store.status.effectiveProvider.name
        case .loading where store.isDiscovering:
            return String(localized: "Searching local network…")
        default:
            return AmbientOpsClient.normalizedServerURL(store.serverAddress)?.host
                ?? String(localized: "No live source")
        }
    }

    private var currentSourceDetail: String {
        if store.isDemoMode {
            return String(localized: "Sample fleet preview")
        }
        switch store.connectionState {
        case .live, .stale:
            return store.providerLabel
        case .loading where store.isDiscovering:
            return String(localized: "Gateway and Codex TPS")
        case let .error(message):
            return message
        default:
            return String(localized: "Gateway and Codex TPS")
        }
    }

    private var connectionIcon: String {
        if store.isDemoMode { return "play.rectangle" }
        return switch store.connectionState {
        case .live: "checkmark.circle.fill"
        case .stale: "clock.badge.exclamationmark"
        case .error: "exclamationmark.triangle.fill"
        default: store.isDiscovering ? "dot.radiowaves.left.and.right" : "network.slash"
        }
    }

    private var connectionColor: Color {
        if store.isDemoMode { return AmbientTheme.blue }
        return switch store.connectionState {
        case .live: AmbientTheme.green
        case .stale: AmbientTheme.amber
        case .error: AmbientTheme.red
        default: store.isDiscovering ? AmbientTheme.green : AmbientTheme.muted
        }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        if store.isDemoMode {
            StatusPill(status: "active", label: "DEMO")
        } else {
            switch store.connectionState {
            case .live:
                StatusPill(status: "live")
            case .stale:
                StatusPill(status: "stale")
            case .error:
                StatusPill(status: "error")
            default:
                if store.isDiscovering {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text("AUTO")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AmbientTheme.green)
                    }
                } else {
                    StatusPill(status: "idle", label: "OFFLINE")
                }
            }
        }
    }
}
