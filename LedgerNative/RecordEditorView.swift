import SwiftUI
import UIKit

struct RecordEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    private let editing: LedgerRecord?

    @State private var direction: Direction
    @State private var amountText: String
    @State private var date: Date
    @State private var category: String
    @State private var note: String
    @State private var member: String
    @State private var account: String
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var savedHint = false
    @State private var showTaxonomy = false
    @State private var splitEnabled = false
    @State private var splitRows: [SplitDraft] = [SplitDraft()]
    @State private var didLoadSplitRows = false
    @FocusState private var amountFocused: Bool

    private struct SplitDraft: Identifiable {
        let id = UUID()
        var category: String = "餐饮"
        var amountText: String = ""
        var note: String = ""
    }

    init(record: LedgerRecord? = nil) {
        editing = record
        _direction = State(initialValue: record?.direction ?? .expense)
        _amountText = State(initialValue: record.map { String(format: "%.2f", $0.amountYuan) } ?? "")
        _date = State(initialValue: record?.dateValue ?? Date())
        _category = State(initialValue: record?.category ?? "餐饮")
        _note = State(initialValue: record?.note ?? "")
        _member = State(initialValue: record?.member ?? "我")
        _account = State(initialValue: record?.account ?? "")
        _splitEnabled = State(initialValue: record?.splitGroup != nil)
        if let record, record.splitGroup != nil {
            _splitRows = State(initialValue: [SplitDraft(category: record.category,
                                                       amountText: String(format: "%.2f", record.amountYuan),
                                                       note: record.note)])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    amountCard
                    metaCard
                    if splitEnabled {
                        splitCard
                    } else {
                        categoryCard
                    }
                    noteCard
                    actionButtons
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 26)
            }
            .background(AppTheme.grouped.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .onAppear {
                if editing == nil { amountFocused = true }
                normalizeCategory()
                loadSplitRowsIfNeeded()
            }
            .navigationTitle(editing == nil ? "记一笔" : "编辑账目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(continueAfter: false) }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { amountFocused = false }
                }
            }
            .alert("提示", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showTaxonomy) {
                NavigationStack { TaxonomyView().environmentObject(store) }
            }
            .overlay(alignment: .top) {
                if savedHint {
                    Text("已保存，继续记下一笔")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.78))
                        .clipShape(Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var amountCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("¥")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                if splitEnabled {
                    Text(String(format: "%.2f", splitTotal))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                } else {
                    TextField("0.00", text: $amountText)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                        .monospacedDigit()
                        .focused($amountFocused)
                    Spacer(minLength: 0)
                }
            }

            Picker("方向", selection: $direction) {
                Text("支出").tag(Direction.expense)
                Text("收入").tag(Direction.income)
            }
            .pickerStyle(.segmented)
            .onChange(of: direction) { _, _ in normalizeCategory() }

            HStack {
                Text(direction == .expense ? "记一笔支出" : "记一笔收入")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(store.selectedBook?.name ?? "我的账本")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .cardStyle(padding: 18)
    }

    private var metaCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("日期", systemImage: "calendar")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            .padding(.vertical, 12)

            Divider().overlay(AppTheme.hairline)

            Menu {
                ForEach(store.allMembers, id: \.self) { item in
                    Button(item) { member = item }
                }
            } label: {
                menuRow(title: "成员", value: member, icon: "person")
            }

            Divider().overlay(AppTheme.hairline)

            Menu {
                Button("不选账户") { account = "" }
                ForEach(store.allAccounts, id: \.self) { item in
                    Button(item) { account = item }
                }
            } label: {
                menuRow(title: "账户", value: account.isEmpty ? "未选" : account, icon: "creditcard")
            }

            Divider().overlay(AppTheme.hairline)

            Toggle(isOn: $splitEnabled) {
                Label("拆分多笔", systemImage: "square.split.2x1")
                    .font(.system(size: 13, weight: .medium))
            }
            .tint(AppTheme.accent)
            .padding(.vertical, 10)
            .onChange(of: splitEnabled) { _, on in
                if on, splitRows.isEmpty { splitRows = [SplitDraft()] }
            }

            Divider().overlay(AppTheme.hairline)

            Button { showTaxonomy = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("管理成员和分类")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 0.5)
        )
    }

    private func menuRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, 12)
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("分类")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("只能从列表选择")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                ForEach(categories, id: \.self) { item in
                    Button {
                        category = item
                    } label: {
                        Text(item)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(category == item ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(category == item ? AppTheme.accent : AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(category == item ? Color.clear : AppTheme.hairline, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .cardStyle(padding: 14)
    }

    private var splitTotal: Double {
        splitRows.reduce(0) { $0 + (Double($1.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) }
    }

    private var splitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("明细 · \(splitRows.count) 笔")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("合计 ¥\(String(format: "%.2f", splitTotal))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            Text("一张票按分类拆开，金额自动合计；保存后会作为一组账单。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
            ForEach($splitRows) { $row in
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(categories, id: \.self) { item in
                                Button(item) { $row.category = item }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(row.category)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AppTheme.grouped)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        TextField("0.00", text: $row.amountText)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(AppTheme.grouped)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .frame(width: 92)
                        Button {
                            splitRows.removeAll { $0.id == row.id }
                            if splitRows.isEmpty { splitRows = [SplitDraft()] }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("明细备注（选填）", text: $row.note)
                        .font(.system(size: 12))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(AppTheme.grouped)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .padding(10)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.hairline, lineWidth: 0.5))
            }
            Button {
                splitRows.append(SplitDraft(category: categories.first ?? "其他"))
            } label: {
                Label("添加一行", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(AppTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .cardStyle(padding: 14)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            TextField("备注（选填）", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 14))
        }
        .cardStyle(padding: 14)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if editing == nil {
                Button { save(continueAfter: true) } label: {
                    Text("保存并继续")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Button { save(continueAfter: false) } label: {
                Text(editing == nil ? "保存" : "保存修改")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var categories: [String] {
        store.categories(for: direction)
    }

    private func normalizeCategory() {
        let list = categories
        if !list.contains(category), let first = list.first {
            category = first
        }
    }

    private func loadSplitRowsIfNeeded() {
        guard !didLoadSplitRows, let editing, let group = editing.splitGroup else { return }
        didLoadSplitRows = true
        let siblings = store.records
            .filter { $0.bookUid == store.writeBookID && $0.splitGroup == group }
            .sorted { $0.id < $1.id }
        guard !siblings.isEmpty else { return }
        splitRows = siblings.map {
            SplitDraft(category: $0.category,
                       amountText: String(format: "%.2f", $0.amountYuan),
                       note: $0.note)
        }
    }

    private func save(continueAfter: Bool) {
        if splitEnabled {
            saveSplit(continueAfter: continueAfter)
            return
        }
        let cleaned = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else {
            errorMessage = "请输入大于 0 的金额"
            showError = true
            return
        }
        let cents = Int(round(value * 100))
        guard cents > 0 else {
            errorMessage = "金额太小了"
            showError = true
            return
        }
        guard categories.contains(category) else {
            errorMessage = "请从分类列表里选择，避免账本分类不一致"
            showError = true
            return
        }
        guard store.allMembers.contains(member) else {
            errorMessage = "请从成员列表里选择"
            showError = true
            return
        }

        let record = LedgerRecord(
            id: editing?.id ?? ULID.generate(),
            bookUid: store.writeBookID,
            date: dateString(date),
            direction: direction,
            amountCents: cents,
            category: category,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            member: member,
            account: account,
            groupNote: "",
            splitGroup: nil,
            excludeTotal: false,
            updatedAt: nowMillis(),
            pending: true
        )
        if let editing, let oldGroup = editing.splitGroup {
            store.records
                .filter { $0.bookUid == store.writeBookID && $0.splitGroup == oldGroup && $0.id != record.id }
                .forEach(store.delete)
        }
        store.upsert(record)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        amountFocused = false

        if continueAfter {
            amountText = ""
            note = ""
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { savedHint = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.25)) { savedHint = false }
                }
            }
        } else {
            dismiss()
        }
    }

    private func saveSplit(continueAfter: Bool) {
        let rows = splitRows.filter {
            !$0.amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !rows.isEmpty else {
            errorMessage = "拆分记账至少要有一笔金额"
            showError = true
            return
        }
        guard store.allMembers.contains(member) else {
            errorMessage = "请从成员列表里选择"
            showError = true
            return
        }
        var parsed: [(SplitDraft, Int)] = []
        for row in rows {
            let cleaned = row.amountText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "，", with: ".")
                .replacingOccurrences(of: ",", with: ".")
            guard let value = Double(cleaned), value > 0, Int(round(value * 100)) > 0 else {
                errorMessage = "「\(row.category)」的金额不正确"
                showError = true
                return
            }
            guard categories.contains(row.category) else {
                errorMessage = "请从分类列表里选择，避免账本分类不一致"
                showError = true
                return
            }
            parsed.append((row, Int(round(value * 100))))
        }

        let group = editing?.splitGroup ?? "split-\(ULID.generate())"
        if let editing, let oldGroup = editing.splitGroup {
            store.records
                .filter { $0.bookUid == store.writeBookID && $0.splitGroup == oldGroup }
                .forEach(store.delete)
        }
        for (index, item) in parsed.enumerated() {
            let row = item.0
            let cents = item.1
            let record = LedgerRecord(
                id: index == 0 ? (editing?.id ?? ULID.generate()) : ULID.generate(),
                bookUid: store.writeBookID,
                date: dateString(date),
                direction: direction,
                amountCents: cents,
                category: row.category,
                note: row.note.trimmingCharacters(in: .whitespacesAndNewlines),
                member: member,
                account: account,
                groupNote: note.trimmingCharacters(in: .whitespacesAndNewlines),
                splitGroup: group,
                excludeTotal: false,
                updatedAt: nowMillis(),
                pending: true
            )
            store.upsert(record)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        amountFocused = false

        if continueAfter {
            splitRows = [SplitDraft(category: categories.first ?? "其他")]
            note = ""
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { savedHint = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.25)) { savedHint = false }
                }
            }
        } else {
            dismiss()
        }
    }
}
