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
    @FocusState private var amountFocused: Bool

    init(record: LedgerRecord? = nil) {
        editing = record
        _direction = State(initialValue: record?.direction ?? .expense)
        _amountText = State(initialValue: record.map { String(format: "%.2f", $0.amountYuan) } ?? "")
        _date = State(initialValue: record?.dateValue ?? Date())
        _category = State(initialValue: record?.category ?? "餐饮")
        _note = State(initialValue: record?.note ?? "")
        _member = State(initialValue: record?.member ?? "我")
        _account = State(initialValue: record?.account ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    amountCard
                    metaCard
                    categoryCard
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
                TextField("0.00", text: $amountText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)
                    .monospacedDigit()
                    .focused($amountFocused)
                Spacer(minLength: 0)
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

    private func save(continueAfter: Bool) {
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
            groupNote: editing?.groupNote ?? "",
            splitGroup: editing?.splitGroup,
            excludeTotal: editing?.excludeTotal ?? false,
            updatedAt: nowMillis(),
            pending: true
        )
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
}
