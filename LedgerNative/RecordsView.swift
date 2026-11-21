import SwiftUI

private enum RecordDateScope: String, CaseIterable, Identifiable {
    case month = "本月"
    case all = "全部"
    case last7 = "近 7 天"
    case last30 = "近 30 天"
    case year = "今年"
    case custom = "自定义"
    var id: String { rawValue }
}

private enum RecordDirectionFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case expense = "支出"
    case income = "收入"
    var id: String { rawValue }
}

private enum RecordKeywordScope: String, CaseIterable, Identifiable {
    case all = "全部字段"
    case note = "备注"
    case category = "分类"
    case member = "成员"
    case account = "账户"
    case date = "日期"
    case amount = "金额"
    var id: String { rawValue }
}

/// 只影响明细页的显示条件，不写回任何账目。
private struct RecordFilter: Equatable {
    var dateScope: RecordDateScope = .month
    var customFrom = ""
    var customTo = ""
    var direction: RecordDirectionFilter = .all
    var member = "全部"
    var category = "全部"
    var account = "全部"
    var amountMin = ""
    var amountMax = ""
    var keywordScope: RecordKeywordScope = .all
    var noteOnly = false
    var splitOnly = false
    var excludeOnly = false
    var pendingOnly = false

    /// 日期范围只是浏览范围，不算“筛选条件”；其余条件命中时切到明细模式。
    var narrowCount: Int {
        var n = 0
        if direction != .all { n += 1 }
        if member != "全部" { n += 1 }
        if category != "全部" { n += 1 }
        if account != "全部" { n += 1 }
        if !amountMin.isEmpty || !amountMax.isEmpty { n += 1 }
        if noteOnly { n += 1 }
        if splitOnly { n += 1 }
        if excludeOnly { n += 1 }
        if pendingOnly { n += 1 }
        return n
    }

    var isNarrow: Bool { narrowCount > 0 }
}

private struct RecordFilterChip: Identifiable {
    let key: String
    let label: String
    var id: String { key }
}

private struct FilterHit: Identifiable {
    let record: LedgerRecord
    let splitIndex: Int
    let splitTotal: Int
    var id: String { record.id }
    var splitLabel: String? {
        guard splitTotal > 1 else { return nil }
        return "拆分 \(splitIndex)/\(splitTotal)"
    }
}

private struct FilterDay: Identifiable {
    var id: String { date }
    let date: String
    let hits: [FilterHit]
    var total: Int {
        hits.reduce(0) { $0 + ($1.record.direction == .income ? $1.record.amountCents : -$1.record.amountCents) }
    }
}

struct RecordsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var search = ""
    @State private var filter = RecordFilter()
    @State private var draft = RecordFilter()
    @State private var showFilterSheet = false
    @State private var showEditor = false
    @State private var editingRecord: LedgerRecord?

    @Environment(\.horizontalSizeClass) private var horizontalSize

    var body: some View {
        Group {
            if horizontalSize == .regular {
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
            VStack(spacing: 0) {
                filterBar
                if visibleCount == 0 {
                    ContentUnavailableView(
                        "没有匹配的账目",
                        systemImage: "list.bullet.rectangle",
                        description: Text("换个筛选条件，或者点右上角记一笔")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        if detailMode {
                            ForEach(filterDays) { day in
                                Section {
                                    ForEach(day.hits) { hit in
                                        Button {
                                            editingRecord = hit.record
                                        } label: {
                                            RecordRow(record: hit.record, showsDate: false,
                                                      splitLabel: hit.splitLabel)
                                        }
                                        .buttonStyle(.plain)
                                        .listRowBackground(AppTheme.card)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                store.delete(hit.record)
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                            Button {
                                                editingRecord = hit.record
                                            } label: {
                                                Label("编辑", systemImage: "pencil")
                                            }
                                            .tint(AppTheme.accent)
                                        }
                                    }
                                } header: {
                                    HStack {
                                        Text(shortDate(day.date))
                                        Spacer()
                                        Text("\(day.hits.count) 条")
                                            .monospacedDigit()
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                        } else {
                            ForEach(displayGroups) { group in
                                Section {
                                    ForEach(group.entries) { entry in
                                        Button {
                                            editingRecord = entry.first
                                        } label: {
                                            RecordGroupRow(group: entry, showsDate: false)
                                        }
                                        .buttonStyle(.plain)
                                        .listRowBackground(AppTheme.card)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                store.deleteGroup(entry)
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                            Button {
                                                editingRecord = entry.first
                                            } label: {
                                                Label("编辑", systemImage: "pencil")
                                            }
                                            .tint(AppTheme.accent)
                                        }
                                    }
                                } header: {
                                    HStack {
                                        Text(shortDate(group.date))
                                        Spacer()
                                        Text(money(abs(group.total)))
                                            .monospacedDigit()
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.grouped)
                    .refreshable {
                        await store.syncNow()
                    }
                }
            }
            .background(AppTheme.grouped.ignoresSafeArea())
            .navigationTitle("明细")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, prompt: "搜索备注、分类、成员")
            .sheet(isPresented: $showFilterSheet) {
                filterSheet
            }
            .onChange(of: store.writeBookID) { _, _ in
                // 换账本必须立刻清掉上一本的筛选与搜索结果，否则会拿旧条件筛新账本。
                filter = RecordFilter()
                draft = RecordFilter()
                search = ""
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
            }
        }
    }

    // MARK: - 顶部筛选入口与已选条件

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                Button {
                    draft = filter
                    if draft.dateScope == .custom {
                        ensureCustomDates()
                    }
                    showFilterSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 12, weight: .semibold))
                        Text("筛选")
                            .font(.system(size: 12, weight: .semibold))
                        if activeConditionCount > 0 {
                            Text("\(activeConditionCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(AppTheme.accent)
                                .clipShape(Circle())
                        }
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppTheme.accentSoft)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Text(filter.dateScope.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer(minLength: 6)

                Text(detailMode ? "命中 \(visibleCount) 条" : "共 \(visibleCount) 笔")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if !activeChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(activeChips) { chip in
                            Button {
                                clearFilter(chip.key)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(chip.label)
                                        .lineLimit(1)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(AppTheme.accentSoft)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            resetAllFilters()
                        } label: {
                            Text("清除全部")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(AppTheme.card)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 26)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private var activeChips: [RecordFilterChip] {
        var chips: [RecordFilterChip] = []
        let keyword = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            chips.append(RecordFilterChip(key: "search", label: "搜索 · \(keyword)"))
            if filter.keywordScope != .all {
                chips.append(RecordFilterChip(key: "scope", label: "关键词 · \(filter.keywordScope.rawValue)"))
            }
        }
        if filter.dateScope != .month {
            chips.append(RecordFilterChip(key: "date", label: dateChipLabel))
        }
        if filter.member != "全部" {
            chips.append(RecordFilterChip(key: "member", label: "成员 · \(filter.member)"))
        }
        if filter.category != "全部" {
            chips.append(RecordFilterChip(key: "category", label: "分类 · \(filter.category)"))
        }
        if filter.account != "全部" {
            chips.append(RecordFilterChip(key: "account", label: "账户 · \(filter.account)"))
        }
        if filter.direction != .all {
            chips.append(RecordFilterChip(key: "direction", label: "只看\(filter.direction.rawValue)"))
        }
        if !filter.amountMin.isEmpty || !filter.amountMax.isEmpty {
            let min = filter.amountMin.isEmpty ? "" : "¥\(filter.amountMin)"
            let max = filter.amountMax.isEmpty ? "" : "¥\(filter.amountMax)"
            let text = !min.isEmpty && !max.isEmpty ? "\(min)~\(max)" : (min.isEmpty ? "≤\(max)" : "≥\(min)")
            chips.append(RecordFilterChip(key: "amount", label: "金额 · \(text)"))
        }
        if filter.noteOnly { chips.append(RecordFilterChip(key: "note", label: "有备注")) }
        if filter.splitOnly { chips.append(RecordFilterChip(key: "split", label: "拆分账")) }
        if filter.excludeOnly { chips.append(RecordFilterChip(key: "exclude", label: "不计入总收支")) }
        if filter.pendingOnly { chips.append(RecordFilterChip(key: "pending", label: "未上云")) }
        return chips
    }

    private var dateChipLabel: String {
        switch filter.dateScope {
        case .month, .all: return "日期 · \(filter.dateScope.rawValue)"
        case .last7, .last30, .year: return "日期 · \(filter.dateScope.rawValue)"
        case .custom:
            let from = filter.customFrom.isEmpty ? "不限" : filter.customFrom
            let to = filter.customTo.isEmpty ? "不限" : filter.customTo
            return "日期 · \(from)~\(to)"
        }
    }

    private var activeConditionCount: Int {
        var n = filter.narrowCount
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { n += 1 }
        return n
    }

    private func clearFilter(_ key: String) {
        switch key {
        case "search": search = ""
        case "scope": filter.keywordScope = .all
        case "date": filter.dateScope = .all; filter.customFrom = ""; filter.customTo = ""
        case "member": filter.member = "全部"
        case "category": filter.category = "全部"
        case "account": filter.account = "全部"
        case "direction": filter.direction = .all
        case "amount": filter.amountMin = ""; filter.amountMax = ""
        case "note": filter.noteOnly = false
        case "split": filter.splitOnly = false
        case "exclude": filter.excludeOnly = false
        case "pending": filter.pendingOnly = false
        default: break
        }
    }

    private func resetAllFilters() {
        filter = RecordFilter()
        draft = RecordFilter()
        search = ""
    }

    // MARK: - 结果计算

    private var detailMode: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter.isNarrow
    }

    private var visibleCount: Int {
        detailMode ? matchingHits.count : displayGroups.reduce(0) { $0 + $1.recordCount }
    }

    private var displayGroups: [RecordsDayGroup] {
        store.groups(for: store.writeBookID)
            .filter { inDateScope($0.date) }
            .sorted { $0.date > $1.date }
            .map { RecordsDayGroup(date: $0.date, entries: $0.entries) }
    }

    private struct RecordsDayGroup: Identifiable {
        var id: String { date }
        let date: String
        let entries: [RecordGroup]
        var total: Int {
            entries.reduce(0) { $0 + ($1.direction == .income ? $1.amountCents : -$1.amountCents) }
        }
        var recordCount: Int { entries.reduce(0) { $0 + $1.records.count } }
    }

    private var splitPositions: [String: (index: Int, total: Int)] {
        var buckets: [String: [LedgerRecord]] = [:]
        for record in store.records where record.bookUid == store.writeBookID {
            guard let group = record.splitGroup, !group.isEmpty else { continue }
            let key = "\(group)|\(record.member)|\(record.date)"
            buckets[key, default: []].append(record)
        }
        var result: [String: (Int, Int)] = [:]
        for (_, list) in buckets {
            let sorted = list.sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
                return lhs.updatedAt < rhs.updatedAt
            }
            for (offset, record) in sorted.enumerated() {
                result[record.id] = (offset + 1, sorted.count)
            }
        }
        return result
    }

    private var matchingHits: [FilterHit] {
        let positions = splitPositions
        let matched = store.records
            .filter { $0.bookUid == store.writeBookID && recordMatches($0) }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.updatedAt > rhs.updatedAt }
                return lhs.date > rhs.date
            }
        return matched.map { record in
            let pos = positions[record.id] ?? (index: 1, total: 1)
            return FilterHit(record: record, splitIndex: pos.0, splitTotal: pos.1)
        }
    }

    private var filterDays: [FilterDay] {
        let grouped = Dictionary(grouping: matchingHits) { $0.record.date }
        return grouped
            .map { FilterDay(date: $0.key, hits: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private func recordMatches(_ record: LedgerRecord) -> Bool {
        guard inDateScope(record.date) else { return false }
        if filter.direction == .expense && record.direction != .expense { return false }
        if filter.direction == .income && record.direction != .income { return false }
        if filter.member != "全部" && record.member != filter.member { return false }
        if filter.category != "全部" && record.category != filter.category { return false }
        if filter.account != "全部" && record.account != filter.account { return false }
        if let min = yuanCents(filter.amountMin), record.amountCents < min { return false }
        if let max = yuanCents(filter.amountMax), record.amountCents > max { return false }
        if filter.noteOnly {
            let note = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let groupNote = record.groupNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if note.isEmpty && groupNote.isEmpty { return false }
        }
        if filter.splitOnly && (record.splitGroup ?? "").isEmpty { return false }
        if filter.excludeOnly && !record.excludeTotal { return false }
        if filter.pendingOnly && !record.pending { return false }
        return matchesSearch(record)
    }

    private func matchesSearch(_ record: LedgerRecord) -> Bool {
        let tokens = search
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        if tokens.isEmpty { return true }
        let noteHay = "\(record.note) \(record.groupNote)".lowercased()
        let amountText = String(format: "%.2f", Double(record.amountCents) / 100.0)
        let amountHay = "\(record.amountCents) \(amountText) \(money(record.amountCents))".lowercased()
        func everyToken(in hay: String) -> Bool {
            tokens.allSatisfy { hay.contains($0) }
        }
        switch filter.keywordScope {
        case .note: return everyToken(in: noteHay)
        case .category: return everyToken(in: record.category.lowercased())
        case .member: return everyToken(in: record.member.lowercased())
        case .account: return everyToken(in: record.account.lowercased())
        case .date: return everyToken(in: record.date.lowercased())
        case .amount: return everyToken(in: amountHay)
        case .all:
            let hay = "\(record.member) \(record.note) \(record.groupNote) \(record.category) \(record.account) \(record.date) \(amountHay)".lowercased()
            return everyToken(in: hay)
        }
    }

    private func inDateScope(_ date: String) -> Bool {
        switch filter.dateScope {
        case .all:
            return true
        case .month:
            return date.hasPrefix(store.currentMonthKey)
        case .last7:
            return date >= relativeDay(-6)
        case .last30:
            return date >= relativeDay(-29)
        case .year:
            return date >= String(todayString().prefix(4)) + "-01-01"
        case .custom:
            if !filter.customFrom.isEmpty && date < filter.customFrom { return false }
            if !filter.customTo.isEmpty && date > filter.customTo { return false }
            return true
        }
    }

    private func relativeDay(_ offset: Int) -> String {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return dateString(day)
    }

    private func yuanCents(_ text: String) -> Int? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !clean.isEmpty, let value = Double(clean), value.isFinite, value >= 0 else { return nil }
        return Int((value * 100).rounded())
    }

    private func ensureCustomDates() {
        if draft.customFrom.isEmpty {
            draft.customFrom = dateString(Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date())
        }
        if draft.customTo.isEmpty {
            draft.customTo = todayString()
        }
    }

    // MARK: - 筛选面板

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("日期范围", selection: $draft.dateScope) {
                        ForEach(RecordDateScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    if draft.dateScope == .custom {
                        DatePicker("开始", selection: Binding(
                            get: { parseDate(draft.customFrom) ?? Date() },
                            set: { draft.customFrom = dateString($0) }
                        ), displayedComponents: .date)
                        DatePicker("结束", selection: Binding(
                            get: { parseDate(draft.customTo) ?? Date() },
                            set: { draft.customTo = dateString($0) }
                        ), displayedComponents: .date)
                    }
                } header: {
                    Text("日期")
                } footer: {
                    Text("本月是默认浏览范围；选自定义后可指定起止日期。")
                }

                Section("收支") {
                    Picker("只看", selection: $draft.direction) {
                        ForEach(RecordDirectionFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("分类 / 成员 / 账户") {
                    Picker("成员", selection: $draft.member) {
                        Text("全部").tag("全部")
                        ForEach(store.memberOptions, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                    Picker("分类", selection: $draft.category) {
                        Text("全部").tag("全部")
                        ForEach(allCategories, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                    Picker("账户", selection: $draft.account) {
                        Text("全部").tag("全部")
                        ForEach(store.accountOptions, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("最低")
                        Spacer()
                        TextField("不限", text: $draft.amountMin)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    HStack {
                        Text("最高")
                        Spacer()
                        TextField("不限", text: $draft.amountMax)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                } header: {
                    Text("金额")
                } footer: {
                    Text("留空表示不限；填写后会按单条明细金额过滤。")
                }

                Section {
                    Picker("搜索范围", selection: $draft.keywordScope) {
                        ForEach(RecordKeywordScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                } header: {
                    Text("关键词")
                } footer: {
                    Text("顶部搜索框会按这里选择的字段匹配；空格分隔多个词时需全部命中。")
                }

                Section("更多条件") {
                    Toggle("只看有备注", isOn: $draft.noteOnly)
                    Toggle("只看拆分账", isOn: $draft.splitOnly)
                    Toggle("只看不计入总收支", isOn: $draft.excludeOnly)
                    Toggle("只看未上云", isOn: $draft.pendingOnly)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.grouped)
            .navigationTitle("筛选账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重置") {
                        draft = RecordFilter()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        if draft.dateScope == .custom {
                            ensureCustomDates()
                        }
                        filter = draft
                        showFilterSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: draft.dateScope) { _, scope in
                if scope == .custom {
                    ensureCustomDates()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var allCategories: [String] {
        var result: [String] = []
        for item in store.categories(for: .expense) + store.categories(for: .income) {
            if !item.isEmpty && !result.contains(item) { result.append(item) }
        }
        return result
    }
}
