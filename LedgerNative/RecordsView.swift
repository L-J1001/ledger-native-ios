import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var scope: RecordScope = .month
    @State private var filter: Direction?
    @State private var query = ""
    @State private var showEditor = false
    @State private var editingRecord: LedgerRecord?

    private enum RecordScope: String, CaseIterable, Identifiable {
        case month = "本月"
        case all = "全部"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summary
                    filterBar
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedSections, id: \.key) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(section.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppTheme.textSecondary)
                                    Spacer()
                                    Text("\(section.records.count) 笔")
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                .padding(.horizontal, 4)
                                VStack(spacing: 0) {
                                    ForEach(section.records) { record in
                                        Button { editingRecord = record } label: {
                                            RecordRow(record: record)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button { editingRecord = record } label: {
                                                Label("编辑", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                store.delete(record)
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                        if record.id != section.records.last?.id {
                                            Divider().overlay(AppTheme.hairline)
                                        }
                                    }
                                }
                                .cardStyle(padding: 14)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .background(AppTheme.grouped.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("明细")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "搜索分类、成员、备注")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditor = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                RecordEditorView().environmentObject(store)
            }
            .sheet(item: $editingRecord) { record in
                RecordEditorView(record: record).environmentObject(store)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            MetricPill(title: "本月支出", value: money(store.monthExpenseCents), color: AppTheme.expense, icon: "arrow.down.right")
            MetricPill(title: "本月收入", value: money(store.monthIncomeCents), color: AppTheme.income, icon: "arrow.up.right")
            MetricPill(title: "结余", value: money(store.monthIncomeCents - store.monthExpenseCents), color: AppTheme.accent, icon: "equal")
        }
        .frame(maxWidth: .infinity)
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(RecordScope.allCases) { item in
                    SoftChip(title: item.rawValue, selected: scope == item) { scope = item }
                }
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SoftChip(title: "全部类型", selected: filter == nil) { filter = nil }
                    SoftChip(title: "支出", selected: filter == .expense, color: AppTheme.expense) { filter = .expense }
                    SoftChip(title: "收入", selected: filter == .income, color: AppTheme.income) { filter = .income }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.textSecondary)
            Text(query.isEmpty ? "还没有符合条件的记录" : "没有搜到「\(query)」")
                .font(.system(size: 15, weight: .semibold))
            Text("换个筛选条件，或点右上角记一笔")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .cardStyle(padding: 0)
    }

    private var sourceRecords: [LedgerRecord] {
        let base = scope == .month ? store.monthRecords : store.records.filter { $0.bookUid == store.writeBookID }
        return base.sorted { $0.date > $1.date }
    }

    private var filtered: [LedgerRecord] {
        sourceRecords.filter { record in
            if let filter, record.direction != filter { return false }
            guard !query.isEmpty else { return true }
            let haystack = [record.category, record.member, record.note, record.account, String(format: "%.2f", record.amountYuan)]
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(query.lowercased())
        }
    }

    private struct SectionGroup {
        let key: String
        let title: String
        let records: [LedgerRecord]
    }

    private var groupedSections: [SectionGroup] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let display = DateFormatter()
        display.locale = Locale(identifier: "zh_CN")
        display.dateFormat = "M月d日 EEEE"

        let groups = Dictionary(grouping: filtered) { $0.date }
        return groups.keys.sorted(by: >).map { key in
            let date = formatter.date(from: key) ?? Date()
            return SectionGroup(key: key, title: display.string(from: date), records: groups[key] ?? [])
        }
    }
}
