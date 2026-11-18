import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home, records, stats, settings

    var title: String {
        switch self {
        case .home: "首页"
        case .records: "明细"
        case .stats: "统计"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .records: "list.bullet.rectangle"
        case .stats: "chart.pie.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var reminder: RenewalReminder
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home

    var body: some View {
        Group {
            if sizeClass == .regular {
                TabletShell(tab: $tab)
            } else {
                PhoneShell(tab: $tab)
            }
        }
        .tint(AppTheme.accent)
        .task {
            reminder.bootstrap()
            await store.syncNow()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                reminder.refresh()
                Task { await store.syncNow() }
            }
        }
        .alert("签名快到期了", isPresented: $reminder.showAlert) {
            Button("知道了", role: .cancel) {}
            Button("我已续签") { reminder.markRenewed() }
        } message: {
            Text("免费 Apple ID 签名还剩 \(reminder.daysRemaining) 天。请在电脑上打开 Sideloadly，让手机和电脑保持同一 Wi‑Fi，完成续签。")
        }
    }
}

private struct PhoneShell: View {
    @Binding var tab: AppTab

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(AppTab.home)
            RecordsView()
                .tabItem { Label("明细", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.records)
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.pie.fill") }
                .tag(AppTab.stats)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
    }
}

private struct TabletShell: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var tab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 250)
            Divider()
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.grouped)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("记账本")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("桌面账本 · 移动端")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 22)

            VStack(spacing: 6) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { tab = item }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 24)
                            Text(item.title)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(tab == item ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(tab == item ? AppTheme.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: store.isSyncing ? "arrow.triangle.2.circlepath" : (store.isLoggedIn ? "checkmark.icloud" : "icloud.slash"))
                    Text(store.isSyncing ? "同步中" : (store.isLoggedIn ? "云端已连接" : "本地模式"))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

                Text(store.selectedBook?.name ?? "我的账本")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(18)
        }
        .background(AppTheme.card)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .home: HomeView()
        case .records: RecordsView()
        case .stats: StatsView()
        case .settings: SettingsView()
        }
    }
}
