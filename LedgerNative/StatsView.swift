import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var monthOffset = 0

    private struct DayPoint: Identifiable {
        let id: String
        let date: Date
        let expense: Int
        let income: Int
    }

    private struct CategoryPoint: Identifiable {
        var id: String { name }
        let name: String
        let cents: Int
        let ratio: Double
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    monthHeader
                    summaryCard
                    factsCard
                    trendCard
                    categoryCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(AppTheme.grouped.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                monthOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(AppTheme.card)
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())

            Spacer()
            VStack(spacing: 3) {
                Text(monthTitle)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                if monthOffset != 0 {
                    Button("回到本月") { monthOffset = 0 }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .buttonStyle(.plain)
                }
            }
            Spacer()

            Button {
                monthOffset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(AppTheme.card)
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
        }
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
                .font(.system(size: 11))
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

    private var factsCard: some View {
        let facts: [(String, String, String)] = [
            ("记账笔数", "\(monthRecords.count) 笔", "含拆分后的明细"),
            ("日均支出", money(dailyExpenseCents), "按 \(monthDays) 天计"),
            ("最大单笔", money(maxSingleExpenseCents), maxSingleExpenseCategory),
            ("最常记", topMemberName, topMemberDetail)
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                         spacing: 12) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(item.1)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text(item.2)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 0.5)
                )
            }
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最近 7 天")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    if !weekRangeText.isEmpty {
                        Text(weekRangeText)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
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
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("金额", Double(point.expense) / 100.0)
                        )
                        .foregroundStyle(AppTheme.expense)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("金额", Double(point.expense) / 100.0)
                        )
                        .foregroundStyle(AppTheme.expense)
                        .symbolSize(12)

                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("金额", Double(point.income) / 100.0)
                        )
                        .foregroundStyle(AppTheme.income)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 1)) { value in
                        AxisGridLine().foregroundStyle(AppTheme.hairline)
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
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
                .frame(height: 190)
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
            Text("支出分类")
                .font(.system(size: 16, weight: .bold, design: .rounded))

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
                            Text("\(Int((point.ratio * 100).rounded()))%")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                                .monospacedDigit()
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .cardStyle(padding: 16)
    }

    private var selectedMonthStart: Date {
        let calendar = Calendar.current
        let today = Date()
        let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        return calendar.date(byAdding: .month, value: monthOffset, to: startOfThisMonth) ?? startOfThisMonth
    }

    private var monthKey: String {
        String(dateString(selectedMonthStart).prefix(7))
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: selectedMonthStart)
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

    private var monthDays: Int {
        let calendar = Calendar.current
        if monthOffset == 0 {
            return max(1, calendar.component(.day, from: Date()))
        }
        return calendar.range(of: .day, in: .month, for: selectedMonthStart)?.count ?? 30
    }

    private var dailyExpenseCents: Int {
        expenseCents / max(1, monthDays)
    }

    private var maxSingleExpense: LedgerRecord? {
        monthRecords.filter { $0.direction == .expense }.max { $0.amountCents < $1.amountCents }
    }

    private var maxSingleExpenseCents: Int { maxSingleExpense?.amountCents ?? 0 }

    private var maxSingleExpenseCategory: String {
        guard let record = maxSingleExpense else { return "这个月还没有支出" }
        let category = record.category.isEmpty ? "未分类" : record.category
        return "\(category) · \(shortDate(record.date))"
    }

    private var topMemberName: String {
        let grouped = Dictionary(grouping: monthRecords.filter { !$0.member.isEmpty }, by: \.member)
        let top = grouped.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            return lhs.value.reduce(0) { $0 + $1.amountCents } < rhs.value.reduce(0) { $0 + $1.amountCents }
        }
        return top?.key ?? "—"
    }

    private var topMemberDetail: String {
        let grouped = Dictionary(grouping: monthRecords.filter { !$0.member.isEmpty }, by: \.member)
        guard let top = grouped.max(by: { $0.value.count < $1.value.count }) else { return "还没有成员记录" }
        let amount = top.value.reduce(0) { $0 + $1.amountCents }
        return "\(top.value.count) 笔 · \(money(amount))"
    }

    private var weekRangeText: String {
        guard let first = dailyPoints.first, let last = dailyPoints.last else { return "" }
        return "\(shortDate(dateString(first.date)))–\(shortDate(dateString(last.date)))"
    }

    private var dailyPoints: [DayPoint] {
        let calendar = Calendar.current
        // 「最近 7 天」必须属于当前查看的月份：
        // 看本月时锚在今天；看历史月份时锚在那个月最后一天，而不是“今天往前 7 天”。
        let anchor: Date
        if monthOffset == 0 {
            anchor = Date()
        } else {
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonthStart) ?? selectedMonthStart
            anchor = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? selectedMonthStart
        }
        let bookRecords = store.records.filter { $0.bookUid == store.writeBookID }
        return (0..<7).map { offset -> DayPoint in
            let day = calendar.date(byAdding: .day, value: -6 + offset, to: anchor) ?? anchor
            let key = dateString(day)
            let dayRecords = bookRecords.filter { $0.date == key }
            let expense = dayRecords.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents }
            let income = dayRecords.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
            return DayPoint(id: key, date: day, expense: expense, income: income)
        }
    }

    private var categoryPoints: [CategoryPoint] {
        let expenses = monthRecords.filter { $0.direction == .expense }
        let grouped = Dictionary(grouping: expenses, by: { $0.category.isEmpty ? "未分类" : $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amountCents } }
        let total = max(1, grouped.values.reduce(0, +))
        return grouped
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { CategoryPoint(name: $0.key, cents: $0.value, ratio: Double($0.value) / Double(total)) }
    }
}
