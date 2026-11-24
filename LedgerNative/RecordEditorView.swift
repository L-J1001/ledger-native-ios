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
    @State private var splitEnabled: Bool
    @State private var splitLines: [SplitLine]
    @State private var groupNote: String
    @State private var excludeTotal: Bool
    @State private var didLoadSplit = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var savedHint = false

    /// 记一笔页所有可输入框共用一套焦点：金额、备注、每条明细的金额/备注。
    /// 键盘上方的「完成」只清一个 Bool 时，备注和明细框会收不回键盘。
    private enum Field: Hashable {
        case amount
        case note
        case splitAmount(UUID)
        case splitNote(UUID)
    }
    @FocusState private var focusedField: Field?

    init(record: LedgerRecord? = nil) {
        editing = record
        _direction = State(initialValue: record?.direction ?? .expense)
        _amountText = State(initialValue: record.map { String(format: "%.2f", $0.amountYuan) } ?? "")
        _date = State(initialValue: record?.dateValue ?? Date())
        _category = State(initialValue: record?.category ?? "餐饮")
        _note = State(initialValue: record?.note ?? "")
        _member = State(initialValue: (record?.member == "我" ? "" : record?.member) ?? "")
        _account = State(initialValue: record?.account ?? "")
        _splitEnabled = State(initialValue: record?.splitGroup != nil)
        _splitLines = State(initialValue: [])
        _groupNote = State(initialValue: record?.groupNote ?? "")
        _excludeTotal = State(initialValue: record?.excludeTotal ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if splitEnabled {
                        splitAmountCard
                    } else {
                        amountCard
                    }
                    directionPicker
                    splitToggle
                    metaCard
                    if splitEnabled {
                        splitCard
                    } else {
                        categoryCard
                    }
                    noteCard
                    excludeCard
                    actionButtons
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 26)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.grouped.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .onAppear(perform: loadSplitIfNeeded)
            .onChange(of: direction) { _, newValue in
                let options = store.categories(for: newValue)
                if !options.contains(category), let first = options.first { category = first }
                for index in splitLines.indices where !options.contains(splitLines[index].category) {
                    splitLines[index].category = options.first ?? "其他"
                }
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
                    Button("完成") { focusedField = nil }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .alert("提示", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
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

    private func loadSplitIfNeeded() {
        guard !didLoadSplit else { return }
        didLoadSplit = true
        if let editing, let group = editing.splitGroup, !group.isEmpty {
            splitEnabled = true
            let siblings = store.splitRecords(group: group, bookID: editing.bookUid)
            let list = siblings.isEmpty ? [editing] : siblings
            splitLines = list.map {
                SplitLine(category: $0.category,
                          amountText: String(format: "%.2f", $0.amountYuan),
                          note: $0.note)
            }
            // 整笔金额 = 各明细之和。编辑拆分账时如果只记下第一条金额，
            // 用户取消拆分后会把整笔金额悄悄改成第一条的金额、并删掉其余明细。
            let total = list.reduce(0) { $0 + $1.amountCents }
            if total > 0 {
                amountText = String(format: "%.2f", Double(total) / 100.0)
            }
            groupNote = editing.groupNote
            member = editing.member
            account = editing.account
            excludeTotal = editing.excludeTotal
        } else if editing == nil {
            splitLines = [SplitLine(category: category, amountText: "", note: "")]
            // 新账不要停在「不选账户」：直接预选当前账本最常用账户。
            if account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                account = store.preferredEntryAccount
            }
            focusedField = .amount
        }
        if member.isEmpty || member == "我",
           let first = store.memberOptions.first {
            member = first
        }
    }

    private var amountCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("¥")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                TextField("0.00", text: $amountText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)
                    .monospacedDigit()
                    .focused($focusedField, equals: .amount)
                Spacer(minLength: 0)
            }

            Divider().overlay(AppTheme.hairline)

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

    private var splitAmountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("整笔金额")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("\(splitLines.count) 条明细")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Text(money(splitTotalCents))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Divider().overlay(AppTheme.hairline)
            HStack {
                Text("合计以明细为准，和桌面端同一笔账")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(store.selectedBook?.name ?? "我的账本")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .cardStyle(padding: 18)
    }

    private var directionPicker: some View {
        Picker("方向", selection: $direction) {
            Text("支出").tag(Direction.expense)
            Text("收入").tag(Direction.income)
        }
        .pickerStyle(.segmented)
    }

    private var splitToggle: some View {
        Toggle(isOn: $splitEnabled.animation(.easeInOut(duration: 0.22))) {
            VStack(alignment: .leading, spacing: 3) {
                Text("按分类拆开")
                    .font(.system(size: 14, weight: .semibold))
                Text("一张票多行明细，和桌面端同一套账")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .tint(AppTheme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 0.5)
        )
        .onChange(of: splitEnabled) { _, enabled in
            if enabled && splitLines.isEmpty {
                splitLines = [SplitLine(category: category,
                                        amountText: amountText,
                                        note: note)]
            } else if !enabled {
                let total = splitTotalCents
                if total > 0 {
                    amountText = String(format: "%.2f", Double(total) / 100.0)
                }
                if let first = splitLines.first {
                    category = first.category
                    if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        note = first.note
                    }
                }
                if !groupNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    note = groupNote
                }
                groupNote = ""
            }
        }
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

            HStack {
                Text("成员")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 58, alignment: .leading)
                Spacer()
                Picker("成员", selection: $member) {
                    ForEach(memberChoices, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(AppTheme.accent)
            }
            .padding(.vertical, 8)

            Divider().overlay(AppTheme.hairline)

            HStack {
                Text("账户")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 58, alignment: .leading)
                Spacer()
                Picker("账户", selection: $account) {
                    Text("不选账户").tag("")
                    ForEach(accountChoices, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(AppTheme.accent)
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 16)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 0.5)
        )
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分类")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
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

    private var splitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("明细")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("合计 \(money(splitTotalCents))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .monospacedDigit()
            }

            ForEach($splitLines) { $line in
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Picker("分类", selection: $line.category) {
                            ForEach(splitCategories(line.category), id: \.self) { item in
                                Text(item).tag(item)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(.primary)
                        .frame(maxWidth: 112, alignment: .leading)

                        TextField("0.00", text: $line.amountText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .splitAmount(line.id))
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 88)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AppTheme.grouped)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Spacer(minLength: 0)

                        Button {
                            if splitLines.count > 1 {
                                if focusedField == .splitAmount(line.id) || focusedField == .splitNote(line.id) {
                                    focusedField = nil
                                }
                                splitLines.removeAll { $0.id == line.id }
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(AppTheme.grouped)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(splitLines.count > 1 ? 1 : 0.35)
                    }

                    TextField("明细备注（选填）", text: $line.note)
                        .font(.system(size: 12))
                        .focused($focusedField, equals: .splitNote(line.id))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AppTheme.grouped)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(.vertical, 4)
                if line.id != splitLines.last?.id {
                    Divider().overlay(AppTheme.hairline)
                }
            }

            Button {
                let next = store.categories(for: direction)
                splitLines.append(SplitLine(category: next.first ?? category, amountText: "", note: ""))
            } label: {
                Label("添加一行", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .cardStyle(padding: 14)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(splitEnabled ? "整笔备注" : "备注")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            TextField(splitEnabled ? "整笔备注（选填）" : "备注（选填）",
                      text: splitEnabled ? $groupNote : $note, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 14))
                .focused($focusedField, equals: .note)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
        }
        .cardStyle(padding: 14)
    }

    private var excludeCard: some View {
        Toggle(isOn: $excludeTotal) {
            VStack(alignment: .leading, spacing: 3) {
                Text("不计入总收支")
                    .font(.system(size: 14, weight: .semibold))
                Text("和桌面端一致：只留流水，不参与余额和统计")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .tint(AppTheme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 0.5)
        )
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if editing == nil {
                Button {
                    save(continueAfter: true)
                } label: {
                    Text("保存并继续")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Button {
                save(continueAfter: false)
            } label: {
                Text(editing == nil ? "保存" : "保存修改")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var categories: [String] {
        var base = store.categories(for: direction)
        if !category.isEmpty, !base.contains(category) { base.insert(category, at: 0) }
        return base
    }

    /// 明细行也要保留自己原来的分类：桌面端隐藏/改名后，历史账目不能因此
    /// 显示成空白，更不能在保存时被悄悄改成第一项。
    private func splitCategories(_ current: String) -> [String] {
        var base = store.categories(for: direction)
        if !current.isEmpty, !base.contains(current) { base.insert(current, at: 0) }
        return base
    }

    private var memberChoices: [String] {
        var base = store.memberOptions
        if !member.isEmpty, member != "我", !base.contains(member) { base.insert(member, at: 0) }
        return base
    }

    private var accountChoices: [String] {
        var base = store.accountOptions
        if !account.isEmpty, !base.contains(account) { base.insert(account, at: 0) }
        return base
    }

    private var splitTotalCents: Int {
        splitLines.reduce(0) { total, line in
            total + (cents(from: line.amountText) ?? 0)
        }
    }

    private func cents(from text: String) -> Int? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return Int(round(value * 100))
    }

    private func save(continueAfter: Bool) {
        if splitEnabled {
            saveSplit(continueAfter: continueAfter)
        } else {
            saveSingle(continueAfter: continueAfter)
        }
    }

    private func saveSingle(continueAfter: Bool) {
        guard let cents = cents(from: amountText) else {
            errorMessage = "请输入大于 0 的金额"
            showError = true
            return
        }
        let who = member.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty, who != "我" else {
            errorMessage = "请先选择成员；如果列表为空，请到设置 → 成员管理里添加或同步成员"
            showError = true
            return
        }

        let old: [LedgerRecord] = {
            guard let editing else { return [] }
            if let group = editing.splitGroup, !group.isEmpty {
                return store.splitRecords(group: group, bookID: editing.bookUid)
            }
            return [editing]
        }()

        let record = LedgerRecord(
            id: editing?.id ?? ULID.generate(),
            bookUid: store.writeBookID,
            date: dateString(date),
            direction: direction,
            amountCents: cents,
            category: category.isEmpty ? "未分类" : category,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            member: member.trimmingCharacters(in: .whitespacesAndNewlines),
            account: account.trimmingCharacters(in: .whitespacesAndNewlines),
            groupNote: "",
            splitGroup: nil,
            excludeTotal: excludeTotal,
            updatedAt: nowMillis(),
            pending: true
        )
        store.replaceRecords([record], removing: old)
        finishSave(continueAfter: continueAfter)
    }

    private func saveSplit(continueAfter: Bool) {
        guard splitLines.count >= 2 else {
            errorMessage = "拆分记账至少要两行明细"
            showError = true
            return
        }
        for (index, line) in splitLines.enumerated() {
            guard cents(from: line.amountText) != nil else {
                errorMessage = "第 \(index + 1) 行金额不正确"
                showError = true
                return
            }
            guard !line.category.isEmpty else {
                errorMessage = "第 \(index + 1) 行请选择分类"
                showError = true
                return
            }
        }
        let who = member.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty, who != "我" else {
            errorMessage = "请先选择成员；整笔拆分共用这一个成员"
            showError = true
            return
        }
        guard splitTotalCents > 0 else {
            errorMessage = "明细合计必须大于 0"
            showError = true
            return
        }
        let group = editing?.splitGroup?.isEmpty == false
            ? editing!.splitGroup!
            : "sg-" + ULID.generate()
        let old: [LedgerRecord] = {
            guard let editing else { return [] }
            if let group = editing.splitGroup, !group.isEmpty {
                return store.splitRecords(group: group, bookID: editing.bookUid)
            }
            return [editing]
        }()

        let now = nowMillis()
        let newRecords = splitLines.enumerated().map { index, line -> LedgerRecord in
            LedgerRecord(
                id: index < old.count ? old[index].id : ULID.generate(),
                bookUid: store.writeBookID,
                date: dateString(date),
                direction: direction,
                amountCents: cents(from: line.amountText) ?? 0,
                category: line.category,
                note: line.note.trimmingCharacters(in: .whitespacesAndNewlines),
                member: who,
                account: account.trimmingCharacters(in: .whitespacesAndNewlines),
                groupNote: groupNote.trimmingCharacters(in: .whitespacesAndNewlines),
                splitGroup: group,
                excludeTotal: excludeTotal,
                updatedAt: now,
                pending: true
            )
        }
        store.replaceRecords(newRecords, removing: old)
        finishSave(continueAfter: continueAfter)
    }

    private func finishSave(continueAfter: Bool) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        focusedField = nil

        if continueAfter {
            amountText = ""
            note = ""
            groupNote = ""
            category = store.categories(for: direction).first ?? "其他"
            splitLines = [SplitLine(category: category, amountText: "", note: "")]
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                savedHint = true
            }
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

private struct SplitLine: Identifiable, Equatable {
    let id = UUID()
    var category: String
    var amountText: String
    var note: String
}
