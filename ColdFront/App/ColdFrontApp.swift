import SwiftUI
import BackgroundTasks

let refreshTaskID = "com.soum91.coldfront.refresh"

func scheduleBackgroundRefresh() {
    let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
    req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(req)
}

@main
struct ColdFrontApp: App {
    @StateObject private var store = Store.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .backgroundTask(.appRefresh(refreshTaskID)) {
            scheduleBackgroundRefresh()
            await Store.shared.backgroundTick()
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
            if p == .active {
                store.startPolling()
                if !Govee.shared.links.isEmpty { Govee.shared.start() }
            } else {
                store.stopPolling()
                Govee.shared.stop()
                if p == .background, store.smart.values.contains(where: \.enabled) {
                    scheduleBackgroundRefresh()
                }
            }
        }
        .onChange(of: store.loggedIn) { _, on in
            if on { store.startPolling() } else { store.stopPolling() }
        }
        .task {
            if store.loggedIn { store.startPolling() }
            if !Govee.shared.links.isEmpty { Govee.shared.start() }
        }
    }
}
