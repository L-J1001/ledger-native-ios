import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var store: LedgerStore

    private enum StatsRange: String, CaseIterable, Identifiable {
        case day = "按天"
        case month = "按月"
        case year = "按年"
        var id: String { rawValue }

        /// 趋势图窗口与柱/点粒度。
        var precision: String {
            switch self {
            case .day: return "近 30 天 · 每天一格"
            case .month: return "近 12 个月 · 每月一格"
            case .year: return "近 6 年 · 每年一格"
            }
        }
    }

    @State private var range: StatsRange = .day
    @State private var offset = 0

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
                    rangePicker
                    periodHeader
                    summaryCard
                    factsCard
                    trendCard
                    categoryCard
                    insightCard
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

    private var rangePicker: some View {
        Picker("统计范围", selection: $range) {
            ForEach(StatsRange.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: range) { _, _ in
            offset = 0
        }
    }

    private var periodHeader: some View {
        HStack {
            Button {
                offset -= 1
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
                Text(periodTitle)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(offset == 0 ? "当前区间" : "点箭头回到当前")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()

            Button {
                if offset < 0 { offset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(AppTheme.card)
                    .clipShape(Circle())
                    .opacity(offset < 0 ? 1 : 0.35)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(offset >= 0)
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
        let expenseTitle = range == .day ? "当日支出" : "日均支出"
        let expenseHint = range == .day ? periodTitle : "按 \(periodDays) 天计"
        let facts: [(String, String, String)] = [
            ("记账笔数", "\(periodRecords.count) 笔", "含拆分后的明细"),
            (expenseTitle, money(dailyExpenseCents), expenseHint),
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

    /// 固定窗口趋势：不跟手、不滑动，只随上方区间箭头整体换一段。
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("收支趋势")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("\(windowNote) · \(range.precision)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    legend(color: AppTheme.expense, text: "支出")
                    legend(color: AppTheme.income, text: "收入")
                }
            }

            if trendTotal == 0 {
                Text("这一段窗口里还没有记录")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                trendChart(points: trendPoints)
            }
        }
        .cardStyle(padding: 16)
    }

    private func trendChart(points: [DayPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("时间", point.date),
                    y: .value("金额", Double(point.expense) / 100.0)
                )
                .foregroundStyle(AppTheme.expense)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .interpolationMethod(.catmullRom)
                .symbol(.circle)
                .symbolSize(10)

                LineMark(
                    x: .value("时间", point.date),
                    y: .value("金额", Double(point.income) / 100.0)
                )
                .foregroundStyle(AppTheme.income)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .interpolationMethod(.catmullRom)
                .symbol(.circle)
                .symbolSize(10)
            }
        }
        .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 8))
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(AppTheme.hairline)
                switch range {
                case .day:
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .foregroundStyle(AppTheme.textSecondary)
                case .month:
                    AxisValueLabel(format: .dateTime.year(.twoDigits).month(.defaultDigits))
                        .foregroundStyle(AppTheme.textSecondary)
                case .year:
                    AxisValueLabel(format: .dateTime.year())
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(AppTheme.hairline)
                AxisValueLabel()
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(height: 190)
        .transition(.opacity)
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
                Text("这个区间还没有支出")
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

    private var insightCard: some View {
        let top = categoryPoints.first
        let text: String = {
            guard let top else {
                return "这个区间还没有支出。记几笔之后，这里会显示消费结构、日均和最大单笔。"
            }
            let base = "支出最多的是\(top.name)，共 \(money(top.cents))。"
            if range == .day {
                return base + " 当天共记 \(periodRecords.count) 笔。"
            }
            return base + " 日均支出 \(money(dailyExpenseCents))，已记 \(periodRecords.count) 笔；共 \(periodDays) 天。"
        }()
        return VStack(alignment: .leading, spacing: 6) {
            Text("区间小结")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    /* ---------------- 区间与数据 ---------------- */

    private var calendar: Calendar { Calendar.current }
    private var today: Date { calendar.startOfDay(for: Date()) }

    /// 按天=某一天、按月=某个月、按年=某一年；offset 决定前翻几格。
    private var periodStart: Date {
        switch range {
        case .day:
            return calendar.date(byAdding: .day, value: offset, to: today) ?? today
        case .month:
            let anchor = calendar.date(byAdding: .month, value: offset, to: startOfMonth(today)) ?? today
            return startOfMonth(anchor)
        case .year:
            let anchor = calendar.date(byAdding: .year, value: offset, to: startOfYear(today)) ?? today
            return startOfYear(anchor)
        }
    }

    private var periodEnd: Date {
        let end: Date
        switch range {
        case .day:
            end = periodStart
        case .month:
            end = endOfMonth(periodStart)
        case .year:
            end = endOfYear(periodStart)
        }
        return min(end, today)
    }

    private var periodDays: Int {
        max(1, (calendar.dateComponents([.day], from: periodStart, to: periodEnd).day ?? 0) + 1)
    }

    private var periodTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        switch range {
        case .day:
            f.dateFormat = "yyyy年M月d日"
        case .month:
            f.dateFormat = "yyyy年M月"
        case .year:
            f.dateFormat = "yyyy年"
        }
        return f.string(from: periodStart)
    }

    private var windowEnd: Date { periodEnd }

    /// 趋势窗口：按天近 30 天、按月近 12 个月、按年近 6 年，都以当前区间为最后一段。
    private var windowStart: Date {
        switch range {
        case .day:
            return calendar.date(byAdding: .day, value: -29, to: windowEnd) ?? windowEnd
        case .month:
            return calendar.date(byAdding: .month, value: -11, to: startOfMonth(periodStart)) ?? periodStart
        case .year:
            return calendar.date(byAdding: .year, value: -5, to: startOfYear(periodStart)) ?? periodStart
        }
    }

    private var windowNote: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        switch range {
        case .day:
            f.dateFormat = "M/d"
            return "\(f.string(from: windowStart))–\(f.string(from: windowEnd))"
        case .month:
            f.dateFormat = "yyyy年M月"
            return "\(f.string(from: windowStart))–\(f.string(from: windowEnd))"
        case .year:
            return "\(calendar.component(.year, from: windowStart))–\(calendar.component(.year, from: windowEnd))年"
        }
    }

    private var startOfMonth: (Date) -> Date {
        { date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        }
    }

    private var startOfYear: (Date) -> Date {
        { date in
            calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
        }
    }

    private func endOfMonth(_ date: Date) -> Date {
        calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth(date)) ?? date
    }

    private func endOfYear(_ date: Date) -> Date {
        calendar.date(byAdding: DateComponents(year: 1, day: -1), to: startOfYear(date)) ?? date
    }

    private func records(from start: Date, to end: Date) -> [LedgerRecord] {
        let s = dateString(start)
        let e = dateString(end)
        return store.records.filter {
            $0.bookUid == store.writeBookID && !$0.excludeTotal && $0.date >= s && $0.date <= e
        }
    }

    private var periodRecords: [LedgerRecord] { records(from: periodStart, to: periodEnd) }

    private var incomeCents: Int {
        periodRecords.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
    }

    private var expenseCents: Int {
        periodRecords.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents }
    }

    private var dailyExpenseCents: Int {
        expenseCents / max(1, periodDays)
    }

    private var maxSingleExpense: LedgerRecord? {
        periodRecords.filter { $0.direction == .expense }.max { $0.amountCents < $1.amountCents }
    }

    private var maxSingleExpenseCents: Int { maxSingleExpense?.amountCents ?? 0 }

    private var maxSingleExpenseCategory: String {
        guard let record = maxSingleExpense else { return "这个区间还没有支出" }
        let category = record.category.isEmpty ? "未分类" : record.category
        return "\(category) · \(shortDate(record.date))"
    }

    private var topMemberName: String {
        let grouped = Dictionary(grouping: periodRecords.filter { !$0.member.isEmpty }, by: \.member)
        let top = grouped.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            return lhs.value.reduce(0) { $0 + $1.amountCents } < rhs.value.reduce(0) { $0 + $1.amountCents }
        }
        return top?.key ?? "—"
    }

    private var topMemberDetail: String {
        let grouped = Dictionary(grouping: periodRecords.filter { !$0.member.isEmpty }, by: \.member)
        guard let top = grouped.max(by: { $0.value.count < $1.value.count }) else { return "还没有成员记录" }
        let amount = top.value.reduce(0) { $0 + $1.amountCents }
        return "\(top.value.count) 笔 · \(money(amount))"
    }

    private var trendTotal: Int { trendPoints.reduce(0) { $0 + $1.expense + $1.income } }

    private var trendPoints: [DayPoint] {
        let rows = records(from: windowStart, to: windowEnd)
        switch range {
        case .year:
            let firstYear = calendar.component(.year, from: windowStart)
            let lastYear = calendar.component(.year, from: windowEnd)
            return (firstYear...max(firstYear, lastYear)).map { year in
                let key = String(format: "%04d", year)
                let date = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? windowStart
                let items = rows.filter { $0.date.hasPrefix(key) }
                return DayPoint(
                    id: key,
                    date: date,
                    expense: items.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents },
                    income: items.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
                )
            }
        case .month:
            let first = calendar.component(.year, from: windowStart) * 12 + calendar.component(.month, from: windowStart)
            let last = calendar.component(.year, from: windowEnd) * 12 + calendar.component(.month, from: windowEnd)
            return (first...max(first, last)).map { index in
                let year = index / 12
                let month = index % 12
                let realMonth = month == 0 ? 12 : month
                let realYear = month == 0 ? year - 1 : year
                let key = String(format: "%04d-%02d", realYear, realMonth)
                let date = calendar.date(from: DateComponents(year: realYear, month: realMonth, day: 1)) ?? windowStart
                let items = rows.filter { $0.date.hasPrefix(key) }
                return DayPoint(
                    id: key,
                    date: date,
                    expense: items.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents },
                    income: items.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
                )
            }
        case .day:
            var points: [DayPoint] = []
            var day = windowStart
            while day <= windowEnd {
                let key = dateString(day)
                let items = rows.filter { $0.date == key }
                points.append(DayPoint(
                    id: key,
                    date: day,
                    expense: items.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents },
                    income: items.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
                ))
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
            }
            return points
        }
    }

    private var categoryPoints: [CategoryPoint] {
        let expenses = periodRecords.filter { $0.direction == .expense }
        let grouped = Dictionary(grouping: expenses, by: { $0.category.isEmpty ? "未分类" : $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amountCents } }
        let total = max(1, grouped.values.reduce(0, +))
        return grouped
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { CategoryPoint(name: $0.key, cents: $0.value, ratio: Double($0.value) / Double(total)) }
    }
}
