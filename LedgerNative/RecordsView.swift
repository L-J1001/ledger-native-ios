import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var search = ""
    @State private var scope = 0
    @State private var directionFilter: DirectionFilter = .all
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
        let records: [LedgerRecord]
        var total: Int {
            records.reduce(0) { $0 + ($1.direction == .income ? $1.amountCents : -$1.amountCents) }
        }
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
                                ForEach(group.records) { record in
                                    Button {
                                        editingRecord = record
                                    } label: {
                                        RecordRow(record: record, showsDate: false)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(AppTheme.card)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            store.delete(record)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                        Button {
                                            editingRecord = record
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
                Text("\(groups.reduce(0) { $0 + $1.records.count }) 条")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var groups: [DayGroup] {
        var list = store.records.filter { $0.bookUid == store.writeBookID }
        if scope == 0 {
            list = list.filter { $0.monthKey == store.currentMonthKey }
        }
        if directionFilter == .expense {
            list = list.filter { $0.direction == .expense }
        } else if directionFilter == .income {
            list = list.filter { $0.direction == .income }
        }
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let keyword = search.lowercased()
            list = list.filter {
                $0.note.lowercased().contains(keyword)
                    || $0.category.lowercased().contains(keyword)
                    || $0.member.lowercased().contains(keyword)
            }
        }
        let grouped = Dictionary(grouping: list, by: { $0.date })
        return grouped
            .map { DayGroup(date: $0.key, records: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { $0.date > $1.date }
    }
}
