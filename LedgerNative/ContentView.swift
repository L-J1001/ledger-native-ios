import SwiftUI

private enum AppTab: Hashable {
    case home, records, stats, settings
}

struct ContentView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(AppTab.home)

            RecordsView()
                .tabItem {
                    Label("明细", systemImage: "list.bullet.rectangle")
                }
                .tag(AppTab.records)

            StatsView()
                .tabItem {
                    Label("统计", systemImage: "chart.pie.fill")
                }
                .tag(AppTab.stats)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "person.crop.circle")
                }
                .tag(AppTab.settings)
        }
        .tint(AppTheme.accent)
        .task {
            RenewalReminder.configure()
            await store.syncNow()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await store.syncNow() }
            }
        }
    }
}
