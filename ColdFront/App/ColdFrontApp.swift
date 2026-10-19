import SwiftUI

@main
struct ColdFrontApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if store.loggedIn {
                HomeView()
            } else {
                LoginView()
            }
        }
        .onChange(of: phase) { _, p in
            guard store.loggedIn else { return }
            if p == .active { store.startPolling() } else { store.stopPolling() }
        }
        .onChange(of: store.loggedIn) { _, on in
            if on { store.startPolling() } else { store.stopPolling() }
        }
        .task {
            if store.loggedIn { store.startPolling() }
        }
    }
}
