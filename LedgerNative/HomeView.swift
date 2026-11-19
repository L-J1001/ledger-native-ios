import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @State private var showEditor = false
    @State private var editingRecord: LedgerRecord?
    @State private var showLogin = false
    @State private var showAccount = false
    @State private var taxonomyKind: TaxonomyKind?

    var body: some View {
        Group {
            if horizontalSize == .regular {
                // iPad：记一笔用全屏呈现，sheet 在平板上只有一个小浮窗，没法用。
                baseScreen
                    .fullScreenCover(isPresented: $showEditor) {
                        RecordEditorView()
                            .environmentObject(store)
                    }
                    .fullScreenCover(item: $editingRecord) { record in
                        RecordEditorView(record: record)
                            .environmentObject(store)
                    }
            } else {
                baseScreen
                    .sheet(isPresented: $showEditor) {
                        RecordEditorView()
                            .environmentObject(store)
                    }
                    .sheet(item: $editingRecord) { record in
                        RecordEditorView(record: record)
                            .environmentObject(store)
                    }
            }
        }
    }

    private var baseScreen: some View {
        NavigationStack {
            ScrollView {
                if horizontalSize == .regular {
                    HStack(alignment: .top, spacing: 20) {
                        mainColumn
                        recentSection
                            .frame(minWidth: 320, maxWidth: 420, alignment: .top)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                } else {
                    VStack(spacing: 18) {
                        header
                        if !store.isLoggedIn { loginBanner }
                        BalanceHero(
                            book: store.selectedBook,
                            balanceCents: store.balanceCents,
                            incomeCents: store.monthIncomeCents,
                            expenseCents: store.monthExpenseCents,
                            monthTitle: store.monthLabel()
                        )
                        quickActions
                        recentSection
                        categorySection
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
            .background(AppTheme.grouped.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .refreshable {
                await store.syncNow()
            }
            .sheet(isPresented: $showLogin) {
                LoginView()
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAccount) {
                AccountView()
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $taxonomyKind) { kind in
                NavigationStack {
                    TaxonomyView(kind: kind)
                        .environmentObject(store)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { taxonomyKind = nil }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 18) {
            header
            if !store.isLoggedIn { loginBanner }
            BalanceHero(
                book: store.selectedBook,
                balanceCents: store.balanceCents,
                incomeCents: store.monthIncomeCents,
                expenseCents: store.monthExpenseCents,
                monthTitle: store.monthLabel()
            )
            quickActions
            categorySection
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("记账本")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide)))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            SyncBadge(isLoggedIn: store.isLoggedIn, isSyncing: store.isSyncing)
        }
        .padding(.top, 6)
    }

    private var loginBanner: some View {
        Button {
            showLogin = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("登录后与桌面账本双向同步")
                        .font(.system(size: 14, weight: .semibold))
                    Text("手机记一笔，电脑上也能看到")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(14)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.accent.opacity(0.18), lineWidth: 0.8)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            Button {
                showEditor = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("记一笔")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 10) {
                quickTile(icon: "person.2.fill", title: "成员 / 分类",
                          subtitle: "当前账本 · 只能选择") {
                    taxonomyKind = .members
                }
                quickTile(icon: store.isLoggedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle",
                          title: store.isLoggedIn ? "我的账号" : "登录同步",
                          subtitle: store.isLoggedIn ? "已连接云端" : "和桌面双向同步") {
                    if store.isLoggedIn { showAccount = true } else { showLogin = true }
                }
            }
        }
    }

    private func quickTile(icon: String, title: String, subtitle: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "最近记录")
            if store.recentGroups.isEmpty {
                emptyRecords
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.recentGroups.prefix(6))) { group in
                        Button {
                            editingRecord = group.first
                        } label: {
                            RecordGroupRow(group: group)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(AppTheme.hairline)
                    }
                }
                .cardStyle(padding: 14)
            }
        }
    }

    private var emptyRecords: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 26))
                .foregroundStyle(AppTheme.textSecondary)
            Text("还没有记录")
                .font(.system(size: 15, weight: .medium))
            Text("点上面的「记一笔」开始")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .cardStyle(padding: 0)
    }

    private var categorySection: some View {
        let slices = expenseSlices
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "本月支出分布")
            if slices.isEmpty {
                Text("本月还没有支出")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 12) {
                    ForEach(slices) { slice in
                        HStack(spacing: 10) {
                            Text(slice.name)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 58, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(AppTheme.hairline)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [AppTheme.accent.opacity(0.75), AppTheme.accent],
                                                startPoint: .leading, endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(6, proxy.size.width * slice.ratio))
                                }
                            }
                            .frame(height: 7)
                            Text(money(slice.cents))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                                .monospacedDigit()
                                .frame(width: 78, alignment: .trailing)
                        }
                    }
                }
                .cardStyle(padding: 16)
            }
        }
    }

    private struct CategorySlice: Identifiable {
        let id = UUID()
        let name: String
        let cents: Int
        let ratio: Double
    }

    private var expenseSlices: [CategorySlice] {
        let expenses = store.monthRecords.filter { $0.direction == .expense }
        let grouped = Dictionary(grouping: expenses, by: { $0.category.isEmpty ? "未分类" : $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amountCents } }
        let maxValue = grouped.values.max() ?? 1
        return grouped
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { CategorySlice(name: $0.key, cents: $0.value, ratio: Double($0.value) / Double(max(maxValue, 1))) }
    }
}
