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
            Text(monthTitle)
                .font(.system(size: 20, weight: .bold, design: .rounded))
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
                        }
                    }
                }
            }
        }
        .cardStyle(padding: 16)
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
        let points = (0..<7).compactMap { offset -> DayPoint? in
            guard let day = calendar.date(byAdding: .day, value: -6 + offset, to: lastDay) else { return nil }
            let key = dateString(day)
            let dayRecords = monthRecords.filter { $0.date == key }
            let expense = dayRecords.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents }
            let income = dayRecords.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
            return DayPoint(id: key, date: day, expense: expense, income: income)
        }
        return points.filter { $0.expense + $0.income > 0 }
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
