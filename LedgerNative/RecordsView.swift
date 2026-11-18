import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var search = ""
    @State private var scope = 0
    @State private var directionFilter: DirectionFilter = .all
    @State private var memberFilter = "全部"
    @State private var categoryFilter = "全部"
    @State private var accountFilter = "全部"
    @State private var showEditor = false
    @State private var editingRecord: LedgerRecord?

    private enum DirectionFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case expense = "支出"
        case income = "收入"
        var id: String { rawValue }
    }

    private struct DayGroup: Identifiable {
        var id: String { date }
        let date: String
        let entries: [RecordGroup]
        var total: Int {
            entries.reduce(0) { $0 + ($1.direction == .income ? $1.amountCents : -$1.amountCents) }
        }
        var recordCount: Int { entries.reduce(0) { $0 + $1.records.count } }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filters
                if groups.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的账目",
                        systemImage: "list.bullet.rectangle",
                        description: Text("换个筛选条件，或者点右上角记一笔")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groups) { group in
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
            .onChange(of: store.writeBookID) { _, _ in
                memberFilter = "全部"
                categoryFilter = "全部"
                accountFilter = "全部"
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

    private var filters: some View {
        VStack(spacing: 10) {
            Picker("范围", selection: $scope) {
                Text("本月").tag(0)
                Text("全部").tag(1)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                ForEach(DirectionFilter.allCases) { item in
                    Button {
                        directionFilter = item
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(directionFilter == item ? Color.white : AppTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(directionFilter == item ? AppTheme.accent : AppTheme.card)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(groups.reduce(0) { $0 + $1.recordCount }) 条")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 8) {
                filterMenu(title: "成员", selection: $memberFilter, options: store.memberOptions)
                filterMenu(title: "分类", selection: $categoryFilter,
                           options: store.categories(for: .expense) + store.categories(for: .income))
                filterMenu(title: "账户", selection: $accountFilter, options: store.accountOptions)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func filterMenu(title: String, selection: Binding<String>,
                            options: [String]) -> some View {
        var all = ["全部"]
        for item in options where !item.isEmpty && !all.contains(item) { all.append(item) }
        return Menu {
            ForEach(all, id: \.self) { item in
                Button(item) { selection.wrappedValue = item }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Text(selection.wrappedValue)
                    .fontWeight(.semibold)
                    .foregroundStyle(selection.wrappedValue == "全部" ? AppTheme.textSecondary : AppTheme.accent)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.card)
            .clipShape(Capsule())
        }
    }

    private var groups: [DayGroup] {
        var entries = store.groups(for: store.writeBookID)
        if scope == 0 {
            entries = entries.filter { String($0.date.prefix(7)) == store.currentMonthKey }
        }
        if directionFilter == .expense {
            entries = entries.filter { $0.direction == .expense }
        } else if directionFilter == .income {
            entries = entries.filter { $0.direction == .income }
        }
        if memberFilter != "全部" {
            entries = entries.filter { $0.records.contains { $0.member == memberFilter } }
        }
        if categoryFilter != "全部" {
            entries = entries.filter { $0.records.contains { $0.category == categoryFilter } }
        }
        if accountFilter != "全部" {
            entries = entries.filter { $0.records.contains { $0.account == accountFilter } }
        }
        let keyword = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !keyword.isEmpty {
            entries = entries.filter { entry in
                entry.records.contains { record in
                    record.note.lowercased().contains(keyword)
                        || record.category.lowercased().contains(keyword)
                        || record.member.lowercased().contains(keyword)
                        || record.groupNote.lowercased().contains(keyword)
                }
            }
        }
        let grouped = Dictionary(grouping: entries, by: \.date)
        return grouped
            .map { DayGroup(date: $0.key, entries: $0.value) }
            .sorted { $0.date > $1.date }
    }
}
