import SwiftUI

struct SettingsView: View {
    @Bindable var store: AmbientOpsStore
    @State private var showDiscoveryExplanation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Data source") {
                    Toggle(
                        "Demo Mode",
                        isOn: Binding(
                            get: { store.isDemoMode },
                            set: { enabled in
                                if enabled {
                                    store.useDemoMode()
                                }
                            }
                        )
                    )

                    TextField("http://ambient-ops.local:8787", text: $store.serverAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    Button("Connect", systemImage: "arrow.trianglehead.2.clockwise") {
                        Task { await store.connect() }
                    }
                    .disabled(store.serverAddress.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Find on Local Network", systemImage: "dot.radiowaves.left.and.right") {
                        showDiscoveryExplanation = true
                    }
                }

                if store.isDiscovering || !store.discoveredServers.isEmpty {
                    Section("Nearby servers") {
                        if store.isDiscovering && store.discoveredServers.isEmpty {
                            HStack {
                                ProgressView()
                                Text("Searching…")
                            }
                        }
                        ForEach(store.discoveredServers) { server in
                            Button {
                                store.choose(server)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(server.name)
                                    Text(server.url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(AmbientTheme.muted)
                                }
                            }
                        }
                    }
                }

                Section("Lock Screen") {
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
            }
            .scrollContentBackground(.hidden)
            .background(AmbientTheme.background)
            .navigationTitle("Settings")
            .alert("Allow Local Network Access?", isPresented: $showDiscoveryExplanation) {
                Button("Not Now", role: .cancel) {}
                Button("Continue") { store.startDiscovery() }
            } message: {
                Text("Ambient Ops uses Bonjour only to find your self-hosted server on this Wi-Fi network. It does not scan devices or send local data to a cloud service.")
            }
        }
    }
}
