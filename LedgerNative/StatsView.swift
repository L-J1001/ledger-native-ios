import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var monthOffset = 0

    private struct DayPoint: Identifiable {
        let id: String
        let label: String
        let expense: Int
        let income: Int
    }

    private struct CategoryPoint: Identifiable {
        var id: String { name }
        let name: String
        let cents: Int
        let ratio: Double
    }

    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isWide {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 18) {
                            monthHeader
                            summaryCard
                            trendCard
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 18) {
                            categoryCard
                            insightCard
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                } else {
                    VStack(spacing: 18) {
                        monthHeader
                        summaryCard
                        trendCard
                        categoryCard
                        insightCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
            .background(AppTheme.grouped.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { monthOffset -= 1 } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(AppTheme.card)
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())

            Spacer()
            VStack(spacing: 2) {
                Text(monthTitle)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("\(monthRecords.count) 笔记录")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()

            Button { monthOffset += 1 } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(AppTheme.card)
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.top, 4)
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryMetric(title: "收入", cents: incomeCents, color: AppTheme.income)
            Divider().frame(height: 42)
            summaryMetric(title: "支出", cents: expenseCents, color: AppTheme.expense)
            Divider().frame(height: 42)
            summaryMetric(title: "结余", cents: incomeCents - expenseCents, color: AppTheme.accent)
        }
        .cardStyle(padding: 18)
    }

    private func summaryMetric(title: String, cents: Int, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text(money(cents))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近 7 天")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                HStack(spacing: 8) {
                    legend(color: AppTheme.expense, text: "支出")
                    legend(color: AppTheme.income, text: "收入")
                }
            }

            if dailyPoints.isEmpty {
                Text("这个月还没有记录")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(dailyPoints) { point in
                        BarMark(
                            x: .value("日期", point.label),
                            y: .value("金额", Double(point.expense) / 100.0)
                        )
                        .foregroundStyle(AppTheme.expense.opacity(0.82))
                        .cornerRadius(4)
                        .position(by: .value("类型", "支出"))

                        BarMark(
                            x: .value("日期", point.label),
                            y: .value("金额", Double(point.income) / 100.0)
                        )
                        .foregroundStyle(AppTheme.income.opacity(0.82))
                        .cornerRadius(4)
                        .position(by: .value("类型", "收入"))
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(AppTheme.hairline)
                        AxisValueLabel()
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(AppTheme.hairline)
                        AxisValueLabel()
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .frame(height: isWide ? 240 : 190)
            }
        }
        .cardStyle(padding: 16)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("支出分类")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Text("按金额排序")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if categoryPoints.isEmpty {
                Text("这个月还没有支出")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                VStack(spacing: 12) {
                    ForEach(categoryPoints) { point in
                        HStack(spacing: 10) {
                            Text(point.name)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 58, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(AppTheme.hairline)
                                    Capsule()
                                        .fill(AppTheme.accent)
                                        .frame(width: max(6, proxy.size.width * point.ratio))
                                }
                            }
                            .frame(height: 7)
                            Text(money(point.cents))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                                .monospacedDigit()
                                .frame(width: 78, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .cardStyle(padding: 16)
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("本月小结", systemImage: "sparkles")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
            Text(insightText)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    private var insightText: String {
        guard expenseCents > 0 else {
            return "这个月还没有支出。记几笔之后，这里会显示支出结构和预算进度。"
        }
        let top = categoryPoints.first?.name ?? "其他"
        let avg = expenseCents / max(1, Set(monthRecords.map { $0.date }).count)
        var text = "支出最多的是\(top)，共 \(money(categoryPoints.first?.cents ?? 0))。"
        text += " 有记录的 \(Set(monthRecords.map { $0.date }).count) 天里，日均支出约 \(money(avg))。"
        if store.monthlyBudgetCents > 0 {
            text += store.monthExpenseCents > store.monthlyBudgetCents
                ? " 已经超出本月预算，后面几天可以收一收。"
                : " 本月预算还剩 \(money(store.monthBudgetRemainingCents))。"
        }
        return text
    }

    private var selectedMonthDate: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var monthKey: String {
        String(dateString(selectedMonthDate).prefix(7))
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: selectedMonthDate)
    }

    private var monthRecords: [LedgerRecord] {
        store.records.filter { $0.bookUid == store.writeBookID && $0.monthKey == monthKey }
    }

    private var incomeCents: Int {
        monthRecords.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
    }

    private var expenseCents: Int {
        monthRecords.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents }
    }

    private var dailyPoints: [DayPoint] {
        let calendar = Calendar.current
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: selectedMonthDate) ?? selectedMonthDate
        let lastDay = calendar.date(byAdding: .day, value: -1, to: monthEnd) ?? selectedMonthDate
        let display = DateFormatter()
        display.locale = Locale(identifier: "zh_CN")
        display.dateFormat = "M/d"
        let points = (0..<7).compactMap { offset -> DayPoint? in
            guard let day = calendar.date(byAdding: .day, value: -6 + offset, to: lastDay) else { return nil }
            let key = dateString(day)
            let dayRecords = monthRecords.filter { $0.date == key }
            let expense = dayRecords.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents }
            let income = dayRecords.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
            return DayPoint(id: key, label: display.string(from: day), expense: expense, income: income)
        }
        return points.filter { $0.expense + $0.income > 0 }
    }

    private var categoryPoints: [CategoryPoint] {
        let expenses = monthRecords.filter { $0.direction == .expense }
        let grouped = Dictionary(grouping: expenses, by: { $0.category.isEmpty ? "未分类" : $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amountCents } }
        let maxValue = grouped.values.max() ?? 1
        return grouped
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { CategoryPoint(name: $0.key, cents: $0.value, ratio: Double($0.value) / Double(max(maxValue, 1))) }
    }
}
