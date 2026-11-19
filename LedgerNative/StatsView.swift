import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var store: LedgerStore

    private enum StatsRange: String, CaseIterable, Identifiable {
        case day = "按天"
        case month = "按月"
        case year = "按年"
        var id: String { rawValue }

        /// 图表每一段代表的时间粒度，与区间本身区分开。
        var precision: String {
            switch self {
            case .day: return "每天一格"
            case .month: return "每月一格"
            case .year: return "每年一格"
            }
        }
    }

    @State private var range: StatsRange = .day
    @State private var offset = 0
    @State private var dragX: CGFloat = 0

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
            dragX = 0
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
                if offset != 0 {
                    Button("回到当前") { offset = 0 }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .buttonStyle(.plain)
                }
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
        let facts: [(String, String, String)] = [
            ("记账笔数", "\(periodRecords.count) 笔", "含拆分后的明细"),
            ("日均支出", money(dailyExpenseCents), "按 \(periodDays) 天计"),
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
                    Text("收支趋势")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("\(periodTitle) · \(range.precision)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    legend(color: AppTheme.expense, text: "支出")
                    legend(color: AppTheme.income, text: "收入")
                }
            }

            GeometryReader { geo in
                let width = max(1, geo.size.width)
                ZStack {
                    if trendTotal == 0 {
                        Text("这个区间还没有记录")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        trendChart(points: trendPoints)
                            .frame(width: width)
                            .offset(x: dragX)
                        if dragX != 0 {
                            trendChart(points: trendPoints(at: offset + (dragX < 0 ? 1 : -1)))
                                .frame(width: width)
                                .offset(x: dragX + (dragX < 0 ? width : -width))
                        }
                    }
                }
                .frame(width: width, height: 190)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            var dx = value.translation.width
                            // 已在本期时往“更新”方向轻拉只给一点点位移，松手回弹。
                            if dx > 0 && offset <= 0 { dx *= 0.32 }
                            dragX = dx
                        }
                        .onEnded { value in
                            guard dragX != 0 else { return }
                            let forward = value.translation.width < 0
                            guard abs(value.predictedEndTranslation.width) > width * 0.28,
                                  abs(value.translation.width) > abs(value.translation.height) else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { dragX = 0 }
                                return
                            }
                            if !forward && offset <= 0 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { dragX = 0 }
                                return
                            }
                            // 先把相邻那一页整体推到屏幕中间，落定后同一帧换成新的一期，视觉上完全连续。
                            withAnimation(.easeOut(duration: 0.16)) { dragX = forward ? -width : width }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                                dragX = 0
                                offset += forward ? 1 : -1
                            }
                        }
                )
            }
            .frame(height: 190)
        .cardStyle(padding: 16)
    }

    /// 单页趋势图：收支双折线 + 日期轴。抽成函数是为了能同时画出相邻页。
    @ViewBuilder
    private func trendChart(points: [DayPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("日期", point.date),
                    y: .value("金额", Double(point.expense) / 100.0)
                )
                .foregroundStyle(AppTheme.expense)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .interpolationMethod(.catmullRom)
                .symbol(.circle)
                .symbolSize(12)

                LineMark(
                    x: .value("日期", point.date),
                    y: .value("金额", Double(point.income) / 100.0)
                )
                .foregroundStyle(AppTheme.income)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .interpolationMethod(.catmullRom)
                .symbol(.circle)
                .symbolSize(12)
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(AppTheme.hairline)
                switch range {
                case .day:
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .foregroundStyle(AppTheme.textSecondary)
                case .month:
                    AxisValueLabel(format: .dateTime.month(.defaultDigits))
                        .foregroundStyle(AppTheme.textSecondary)
                case .year:
                    AxisValueLabel(format: .dateTime.year())
                        .foregroundStyle(AppTheme.textSecondary)
                }
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

    /* ---------------- 区间与数据 ---------------- */

    private var calendar: Calendar { Calendar.current }
    private var today: Date { calendar.startOfDay(for: Date()) }

    private var periodStart: Date { periodStart(at: offset) }

    /// 取任意偏移的区间起点：趋势图要同时画出前后两页，才能跟手滑，而不是滑完再刷新。
    private func periodStart(at delta: Int) -> Date {
        switch range {
        case .day:
            let monthStart = startOfMonth(today)
            return calendar.date(byAdding: .month, value: delta, to: monthStart) ?? monthStart
        case .month:
            let yearStart = startOfYear(today)
            return calendar.date(byAdding: .year, value: delta, to: yearStart) ?? yearStart
        case .year:
            // 一次看连续 5 年：offset=0 是「今年往前数 5 年」，每往前一段再退 5 年。
            let endYear = calendar.component(.year, from: today) + delta * 5
            let endYearStart = calendar.date(from: DateComponents(year: endYear, month: 1, day: 1)) ?? today
            return calendar.date(byAdding: .year, value: -4, to: endYearStart) ?? endYearStart
        }
    }

    private var periodEnd: Date { periodEnd(at: offset) }

    private func periodEnd(at delta: Int) -> Date {
        switch range {
        case .day:
            if delta == 0 { return today }
            return endOfMonth(startOfMonth(periodStart(at: delta)))
        case .month:
            if delta == 0 { return today }
            return endOfYear(startOfYear(periodStart(at: delta)))
        case .year:
            let lastYearStart = startOfYear(calendar.date(byAdding: .year, value: 4, to: periodStart(at: delta)) ?? periodStart(at: delta))
            if delta == 0 { return today }
            return endOfYear(lastYearStart)
        }
    }

    private var periodDays: Int {
        max(1, (calendar.dateComponents([.day], from: periodStart, to: periodEnd).day ?? 0) + 1)
    }

    private var periodTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        switch range {
        case .day:
            f.dateFormat = "yyyy年M月"
            return f.string(from: periodStart)
        case .month:
            return "\(calendar.component(.year, from: periodStart))年"
        case .year:
            let startYear = calendar.component(.year, from: periodStart)
            let endYear = calendar.component(.year, from: periodEnd)
            return startYear == endYear ? "\(startYear)年" : "\(startYear) – \(endYear)年"
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

    private var periodRecords: [LedgerRecord] { periodRecords(at: offset) }

    private func periodRecords(at delta: Int) -> [LedgerRecord] {
        let start = dateString(periodStart(at: delta))
        let end = dateString(periodEnd(at: delta))
        return store.records.filter {
            $0.bookUid == store.writeBookID && !$0.excludeTotal && $0.date >= start && $0.date <= end
        }
    }

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

    private var trendTotal: Int { trendPoints(at: offset).reduce(0) { $0 + $1.expense + $1.income } }

    private var trendPoints: [DayPoint] { trendPoints(at: offset) }

    private func trendPoints(at delta: Int) -> [DayPoint] {
        let records = periodRecords(at: delta)
        let start = periodStart(at: delta)
        let end = periodEnd(at: delta)
        switch range {
        case .year:
            let firstYear = calendar.component(.year, from: start)
            let lastYear = calendar.component(.year, from: end)
            return (firstYear...max(firstYear, lastYear)).map { year in
                let key = String(format: "%04d", year)
                let date = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? start
                let rows = records.filter { $0.date.hasPrefix(key) }
                return DayPoint(
                    id: key,
                    date: date,
                    expense: rows.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents },
                    income: rows.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
                )
            }
        case .month:
            let year = calendar.component(.year, from: start)
            let lastMonth = (delta == 0 && calendar.component(.year, from: end) == year)
                ? calendar.component(.month, from: end) : 12
            return (1...max(1, lastMonth)).map { month in
                let key = String(format: "%04d-%02d", year, month)
                let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? start
                let rows = records.filter { $0.date.hasPrefix(key) }
                return DayPoint(
                    id: key,
                    date: date,
                    expense: rows.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents },
                    income: rows.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
                )
            }
        case .day:
            var points: [DayPoint] = []
            var day = start
            while day <= end {
                let key = dateString(day)
                let rows = records.filter { $0.date == key }
                points.append(DayPoint(
                    id: key,
                    date: day,
                    expense: rows.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents },
                    income: rows.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
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
