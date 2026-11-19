import SwiftUI
import Charts

/// 统计页：三端口径统一（iPhone / iPad / 安卓 / PWA 完全一致）
/// · 按天：所选那一天 → 汇总只算这一天；趋势图＝含所选那天在内的最近 7 天
/// · 按月：所选那个月 → 汇总只算这个月；趋势图＝含本月在内的最近 6 个月
/// · 按年：所选那一年 → 汇总只算这一年；趋势图＝含今年在内的最近 5 年，共 5 根
/// 趋势图固定展示、不跟手滑动；翻页只用左右箭头。不在本期时给「回到今天」胶囊，双击日期同效。
struct StatsView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage("stats_range") private var storedRange: String = "day"

    private enum StatsRange: String, CaseIterable, Identifiable {
        case day = "按天"
        case month = "按月"
        case year = "按年"
        var id: String { rawValue }

        var key: String {
            switch self {
            case .day: return "day"
            case .month: return "month"
            case .year: return "year"
            }
        }

        /// 趋势图每一格代表的时间粒度。
        var precision: String {
            switch self {
            case .day: return "每天一格"
            case .month: return "每月一格"
            case .year: return "每年一格"
            }
        }
    }

    @State private var range: StatsRange = .day
    @State private var anchor: Date = Calendar.current.startOfDay(for: Date())

    private struct Bucket: Identifiable {
        let id: Int
        let index: Double
        let label: String
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
                VStack(spacing: 14) {
                    rangePicker
                    periodHeader
                    if !atLatest {
                        backTodayCapsule
                    }
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
            .onAppear {
                range = StatsRange.allCases.first { $0.key == storedRange } ?? .day
                anchor = today
            }
        }
    }

    /* ---------------- 顶部 ---------------- */

    private var rangePicker: some View {
        Picker("统计范围", selection: $range) {
            ForEach(StatsRange.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: range) { _, newValue in
            storedRange = newValue.key
            anchor = today
        }
    }

    private var periodHeader: some View {
        HStack(spacing: 10) {
            arrowButton(system: "chevron.left", enabled: true) { shift(-1) }

            VStack(spacing: 3) {
                Text(periodTitle)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(atLatest ? windowNote : "双击日期回到今天")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { backToToday() }

            arrowButton(system: "chevron.right", enabled: !atLatest) {
                if !atLatest { shift(1) }
            }
            .opacity(atLatest ? 0.35 : 1)
        }
    }

    private func arrowButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 0.5)
                )
        }
        .buttonStyle(PressableButtonStyle())
        .allowsHitTesting(enabled)
    }

    private var backTodayCapsule: some View {
        Button {
            backToToday()
        } label: {
            Text("回到今天")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .frame(maxWidth: .infinity, alignment: .center)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    /* ---------------- 卡片 ---------------- */

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
            (range == .day ? "当日支出" : "日均支出", money(dailyExpenseCents),
             range == .day ? periodTitle : "按 \(periodDays) 天计"),
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

            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let points = buckets
                ZStack {
                    if points.allSatisfy({ $0.expense == 0 && $0.income == 0 }) {
                        Text("这个区间还没有记录")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        chart(points: points, width: width)
                    }
                }
                .frame(width: width, height: 190)
            }
            .frame(height: 190)
        }
        .cardStyle(padding: 16)
    }

    /// 固定展示、不可滑动的趋势图。X 轴用序号定位，标签按格子数量自适应抽稀。
    private func chart(points: [Bucket], width: CGFloat) -> some View {
        let labels = labelIndexes(count: points.count)
        return Chart(points) { point in
            LineMark(
                x: .value("格", point.index),
                y: .value("支出", Double(point.expense) / 100.0)
            )
            .foregroundStyle(AppTheme.expense)
            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .interpolationMethod(points.count > 2 ? .catmullRom : .linear)
            .symbol(Circle())
            .symbolSize(CGFloat(points.count > 24 ? 6 : 10))

            LineMark(
                x: .value("格", point.index),
                y: .value("收入", Double(point.income) / 100.0)
            )
            .foregroundStyle(AppTheme.income)
            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .interpolationMethod(points.count > 2 ? .catmullRom : .linear)
            .symbol(Circle())
            .symbolSize(CGFloat(points.count > 24 ? 6 : 10))
        }
        .chartXScale(domain: -0.5...(Double(max(1, points.count)) - 0.5))
        .chartXAxis {
            AxisMarks(values: labels.map { Double($0) }) { value in
                AxisGridLine().foregroundStyle(AppTheme.hairline)
                if let raw = value.as(Double.self) {
                    let idx = Int(raw.rounded())
                    if idx >= 0 && idx < points.count {
                        AxisValueLabel {
                            Text(points[idx].label)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(AppTheme.hairline)
                AxisValueLabel()
                    .foregroundStyle(AppTheme.textSecondary)
                    .font(.system(size: 9))
            }
        }
        .frame(width: width, height: 190)
    }

    /// 标签抽稀：≤8 格全显示，更多时按等间隔挑选，首尾必显示。
    private func labelIndexes(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        if count <= 8 { return Array(0..<count) }
        let step = Int(ceil(Double(count) / 7.0))
        var result: [Int] = []
        var i = 0
        while i < count {
            result.append(i)
            i += step
        }
        if result.last != count - 1 { result.append(count - 1) }
        if result.count > 2 {
            let picked = Set(result)
            result = result.filter { idx in
                if idx == 0 || idx == count - 1 { return true }
                return !(picked.contains(idx - 1) && picked.contains(idx + 1))
            }
        }
        return result
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
                .animation(.easeOut(duration: 0.25), value: periodTitle)
            }
        }
        .cardStyle(padding: 16)
    }

    /* ---------------- 区间与数据 ---------------- */

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var clampedAnchor: Date { min(anchor, today) }

    private var atLatest: Bool {
        let a = clampedAnchor
        switch range {
        case .day:
            return cal.isDate(a, inSameDayAs: today)
        case .month:
            return cal.component(.year, from: a) == cal.component(.year, from: today)
                && cal.component(.month, from: a) == cal.component(.month, from: today)
        case .year:
            return cal.component(.year, from: a) >= cal.component(.year, from: today)
        }
    }

    private var startOfMonth: (Date) -> Date {
        { date in cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date }
    }

    private var startOfYear: (Date) -> Date {
        { date in cal.date(from: cal.dateComponents([.year], from: date)) ?? date }
    }

    private func endOfMonth(_ date: Date) -> Date {
        cal.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth(date)) ?? date
    }

    private func endOfYear(_ date: Date) -> Date {
        cal.date(byAdding: DateComponents(year: 1, day: -1), to: startOfYear(date)) ?? date
    }

    private func periodStart(_ a: Date) -> Date {
        switch range {
        case .day: return cal.startOfDay(for: a)
        case .month: return startOfMonth(a)
        case .year: return startOfYear(a)
        }
    }

    private func periodEndDate(_ a: Date) -> Date {
        switch range {
        case .day:
            return cal.startOfDay(for: a)
        case .month:
            return min(endOfMonth(a), today)
        case .year:
            return min(endOfYear(a), today)
        }
    }

    private var periodStartDate: Date { periodStart(clampedAnchor) }
    private var periodEnd: Date { max(periodStartDate, periodEndDate(clampedAnchor)) }
    private var periodDays: Int { max(1, (cal.dateComponents([.day], from: periodStartDate, to: periodEnd).day ?? 0) + 1) }
    /// 按天翻页一次走一天（趋势图仍固定显示含今天在内的 7 天，翻页只挪汇总日）。
    private var dayStep: Int { 1 }

    private var windowStart: Date {
        switch range {
        case .day: return cal.date(byAdding: .day, value: -6, to: clampedAnchor) ?? clampedAnchor
        case .month: return cal.date(byAdding: .month, value: -5, to: periodStartDate) ?? periodStartDate
        case .year: return cal.date(byAdding: .year, value: -4, to: periodStartDate) ?? periodStartDate
        }
    }

    private var windowEnd: Date { periodEnd }

    private var windowNote: String {
        switch range {
        case .day: return "近 7 天"
        case .month:
            let months = (cal.dateComponents([.month], from: windowStart, to: windowEnd).month ?? 5) + 1
            return "近 \(min(6, max(1, months))) 个月"
        case .year: return "近 5 年"
        }
    }

    private var periodTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        switch range {
        case .day:
            f.dateFormat = "yyyy年M月d日"
            return f.string(from: periodStartDate)
        case .month:
            f.dateFormat = "yyyy年M月"
            return f.string(from: periodStartDate)
        case .year:
            return "\(cal.component(.year, from: periodStartDate))年"
        }
    }

    private func shift(_ step: Int) {
        var next = clampedAnchor
        let magnitude = range == .day ? dayStep : 1
        switch range {
        case .day: next = cal.date(byAdding: .day, value: step * magnitude, to: next) ?? next
        case .month: next = cal.date(byAdding: .month, value: step * magnitude, to: next) ?? next
        case .year: next = cal.date(byAdding: .year, value: step * magnitude, to: next) ?? next
        }
        if step > 0 && next > today { next = today }
        withAnimation(.easeOut(duration: 0.18)) {
            anchor = next
        }
    }

    private func backToToday() {
        guard !atLatest else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            anchor = today
        }
    }

    private var periodRecords: [LedgerRecord] {
        let startKey = dateString(periodStartDate)
        let endKey = dateString(periodEnd)
        return store.records.filter {
            $0.bookUid == store.writeBookID && !$0.excludeTotal && $0.date >= startKey && $0.date <= endKey
        }
    }

    private var incomeCents: Int {
        periodRecords.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
    }

    private var expenseCents: Int {
        periodRecords.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents }
    }

    private var dailyExpenseCents: Int { expenseCents / max(1, periodDays) }

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

    /// 趋势分桶：按天逐日、按月逐月（跨年补年份）、按年逐年，都按窗口首尾对齐。
    private var buckets: [Bucket] {
        let all = store.records.filter { $0.bookUid == store.writeBookID && !$0.excludeTotal }
        var result: [Bucket] = []
        switch range {
        case .day:
            var day = cal.startOfDay(for: windowStart)
            var index = 0
            while day <= windowEnd {
                let key = dateString(day)
                let rows = all.filter { $0.date == key }
                result.append(Bucket(
                    id: index,
                    index: Double(index),
                    label: monthDayLabel(day),
                    date: day,
                    expense: rows.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents },
                    income: rows.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
                ))
                index += 1
                day = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
            }
        case .month:
            var month = startOfMonth(windowStart)
            let last = startOfMonth(windowEnd)
            var index = 0
            let sameYear = cal.component(.year, from: windowStart) == cal.component(.year, from: windowEnd)
            while month <= last {
                let key = String(format: "%04d-%02d", cal.component(.year, from: month), cal.component(.month, from: month))
                let rows = all.filter { $0.date.hasPrefix(key) }
                result.append(Bucket(
                    id: index,
                    index: Double(index),
                    label: sameYear
                        ? "\(cal.component(.month, from: month))月"
                        : String(format: "%02d/%d", cal.component(.year, from: month) % 100, cal.component(.month, from: month)),
                    date: month,
                    expense: rows.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents },
                    income: rows.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
                ))
                index += 1
                month = cal.date(byAdding: .month, value: 1, to: month) ?? month
            }
        case .year:
            let firstYear = cal.component(.year, from: windowStart)
            let lastYear = max(firstYear, cal.component(.year, from: windowEnd))
            var index = 0
            for year in firstYear...lastYear {
                let key = String(format: "%04d-", year)
                let rows = all.filter { $0.date.hasPrefix(key) }
                let date = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? windowStart
                result.append(Bucket(
                    id: index,
                    index: Double(index),
                    label: String(format: "%02d年", year % 100),
                    date: date,
                    expense: rows.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents },
                    income: rows.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
                ))
                index += 1
            }
        }
        return result
    }

    private func monthDayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d"
        return f.string(from: date)
    }

    private var categoryPoints: [CategoryPoint] {
        let expenses = periodRecords.filter { $0.direction == .expense }
        let grouped = Dictionary(grouping: expenses, by: { $0.category.isEmpty ? "未分类" : $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amountCents } }
        let total = max(1, grouped.values.reduce(0, +))
        return grouped
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { CategoryPoint(name: $0.key, cents: $0.value, ratio: Double($0.value) / Double(total)) }
    }
}
