import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var reminder: RenewalReminder
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showEditor = false
    @State private var editingRecord: LedgerRecord?
    @State private var showAccount = false
    @State private var showBudget = false
    @State private var showTaxonomy = false
    @State private var showRecords = false

    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isWide {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 18) {
                            header
                            hero
                            quickActions
                            budgetCard
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 18) {
                            recentSection
                            categorySection
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                } else {
                    VStack(spacing: 18) {
                        header
                        hero
                        quickActions
                        budgetCard
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
            .refreshable { await store.syncNow() }
            .sheet(isPresented: $showEditor) {
                RecordEditorView().environmentObject(store)
            }
            .sheet(item: $editingRecord) { record in
                RecordEditorView(record: record).environmentObject(store)
            }
            .sheet(isPresented: $showAccount) {
                AccountSheet().environmentObject(store)
            }
            .sheet(isPresented: $showBudget) {
                NavigationStack { BudgetView().environmentObject(store) }
            }
            .sheet(isPresented: $showTaxonomy) {
                NavigationStack { TaxonomyView().environmentObject(store) }
            }
            .sheet(isPresented: $showRecords) {
                NavigationStack { RecordsView().environmentObject(store) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("记账本")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { showAccount = true } label: {
                    Image(systemName: store.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(store.isLoggedIn ? AppTheme.accent : AppTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.card)
                        .clipShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())

                SyncBadge(isLoggedIn: store.isLoggedIn, isSyncing: store.isSyncing)
            }
        }
        .padding(.top, 6)
    }

    private var hero: some View {
        VStack(spacing: 12) {
            BalanceHero(
                book: store.selectedBook,
                balanceCents: store.balanceCents,
                incomeCents: store.monthIncomeCents,
                expenseCents: store.monthExpenseCents,
                monthTitle: store.monthLabel()
            )
            if reminder.daysRemaining <= 3 {
                Button { showAccount = false; reminder.showAlert = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("签名还剩 \(reminder.daysRemaining) 天，点此查看续签提醒")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.gold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.gold.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            quickTile("记一笔", icon: "plus.circle.fill", color: AppTheme.accent) { showEditor = true }
            quickTile("成员分类", icon: "person.2.fill", color: AppTheme.income) { showTaxonomy = true }
            quickTile("本月预算", icon: "gauge.with.dots.needle.50percent", color: AppTheme.gold) { showBudget = true }
            quickTile("我的账号", icon: "person.crop.circle", color: AppTheme.expense) { showAccount = true }
        }
    }

    private func quickTile(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(11)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(PressableButtonStyle())
    }

    @ViewBuilder
    private var budgetCard: some View {
        if store.monthlyBudgetCents > 0 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("本月预算")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(Int(store.monthBudgetRatio * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(store.monthBudgetRatio > 1 ? AppTheme.expense : AppTheme.accent)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.hairline)
                        Capsule()
                            .fill(store.monthBudgetRatio > 1 ? AppTheme.expense : AppTheme.accent)
                            .frame(width: max(6, proxy.size.width * min(1, store.monthBudgetRatio)))
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("已用 \(money(store.monthExpenseCents))")
                    Spacer()
                    Text(store.monthBudgetRatio > 1 ? "超支 \(money(store.monthExpenseCents - store.monthlyBudgetCents))" : "剩余 \(money(store.monthlyBudgetRemainingCents))")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            }
            .cardStyle(padding: 15)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "最近记录", action: "查看全部") {
                showRecords = true
            }
            if store.recentRecords.isEmpty {
                emptyRecords
            } else {
                VStack(spacing: 0) {
                    ForEach(store.recentRecords.prefix(isWide ? 8 : 6)) { record in
                        Button { editingRecord = record } label: {
                            RecordRow(record: record)
                        }
                        .buttonStyle(.plain)
                        if record.id != store.recentRecords.prefix(isWide ? 8 : 6).last?.id {
                            Divider().overlay(AppTheme.hairline)
                        }
                    }
                }
                .cardStyle(padding: 14)
            }
        }
    }

    private var emptyRecords: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.textSecondary)
            Text("还没有记录")
                .font(.system(size: 15, weight: .semibold))
            Text("点上面的「记一笔」开始")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
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
                                    Capsule().fill(AppTheme.hairline)
                                    Capsule()
                                        .fill(LinearGradient(colors: [AppTheme.accent.opacity(0.75), AppTheme.accent], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(6, proxy.size.width * slice.ratio))
                                }
                            }
                            .frame(height: 7)
                            Text(money(slice.cents))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                                .monospacedDigit()
                                .frame(width: 76, alignment: .trailing)
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
