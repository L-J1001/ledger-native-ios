import SwiftUI

private enum AppTab: Hashable, CaseIterable {
    case home, records, stats, settings

    var title: String {
        switch self {
        case .home: return "首页"
        case .records: return "明细"
        case .stats: return "统计"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .records: return "list.bullet.rectangle"
        case .stats: return "chart.pie.fill"
        case .settings: return "person.crop.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @State private var tab: AppTab = .home

    var body: some View {
        Group {
            if horizontalSize == .regular {
                padShell
            } else {
                phoneTabs
            }
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

    /// 手机：保持系统底栏，交互和以前一致。
    private var phoneTabs: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.icon) }
                .tag(AppTab.home)

            RecordsView()
                .tabItem { Label(AppTab.records.title, systemImage: AppTab.records.icon) }
                .tag(AppTab.records)

            StatsView()
                .tabItem { Label(AppTab.stats.title, systemImage: AppTab.stats.icon) }
                .tag(AppTab.stats)

            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
                .tag(AppTab.settings)
        }
    }

    /// 平板：系统的 TabView 在 iPad 上会把按钮挤到顶部一条浮动条里，
    /// 这里改成左侧固定导航栏 + 右侧内容区，真正的平板布局。
    private var padShell: some View {
        HStack(spacing: 0) {
            padSidebar
            Rectangle()
                .fill(AppTheme.hairline)
                .frame(width: 0.6)
                .ignoresSafeArea()
            padContent
                .frame(maxWidth: 1040)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.grouped.ignoresSafeArea())
    }

    private var padSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("记账本")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("多端同步 · 记账")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.bottom, 18)

            Text("页面")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.leading, 4)

            ForEach(AppTab.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { tab = item }
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 20)
                        Text(item.title)
                            .font(.system(size: 14.5, weight: tab == item ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(tab == item ? AppTheme.accent : AppTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(tab == item ? AppTheme.accentSoft : Color.clear)
                    )
                }
                .buttonStyle(PressableButtonStyle())
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Circle()
                    .fill(store.isLoggedIn ? AppTheme.income : AppTheme.textSecondary)
                    .frame(width: 7, height: 7)
                Text(store.isLoggedIn ? "已连接云端" : "未登录")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.leading, 4)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .frame(width: 244)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppTheme.grouped)
    }

    @ViewBuilder
    private var padContent: some View {
        switch tab {
        case .home: HomeView()
        case .records: RecordsView()
        case .stats: StatsView()
        case .settings: SettingsView()
        }
    }
}
