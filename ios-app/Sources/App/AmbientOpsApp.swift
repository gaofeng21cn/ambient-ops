import SwiftUI

@main
struct AmbientOpsApp: App {
    @State private var store = AmbientOpsStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(.dark)
                .tint(AmbientTheme.green)
                .onChange(of: scenePhase) { _, phase in
                    store.scenePhaseChanged(isActive: phase == .active)
                }
        }
    }
}

private struct RootView: View {
    @Bindable var store: AmbientOpsStore
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            HomeView(store: store, openDisplay: {
                store.displayMode = .load
                selection = 2
            })
            .tabItem { Label("Home", systemImage: "square.grid.2x2") }
            .tag(0)

            MachinesView(store: store)
                .tabItem { Label("Machines", systemImage: "laptopcomputer.and.iphone") }
                .tag(1)

            DisplayView(store: store)
                .tabItem { Label("Display", systemImage: "rectangle.inset.filled") }
                .tag(2)

            SettingsView(store: store)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
        .background(AmbientTheme.background)
        .onOpenURL { url in
            guard url.scheme == "ambientops",
                  url.host == "display",
                  url.path == "/load" else {
                return
            }
            store.displayMode = .load
            selection = 2
        }
        .onAppear {
            UITabBar.appearance().unselectedItemTintColor = UIColor(AmbientTheme.muted)
        }
    }
}
