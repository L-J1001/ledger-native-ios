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
                VStack(spacing: 16) {
                    amountCard
                    directionPicker
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
                if editing == nil {
                    amountFocused = true
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
                    Button("完成") { amountFocused = false }
                }
            }
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

    private var directionPicker: some View {
        Picker("方向", selection: $direction) {
            Text("支出").tag(Direction.expense)
            Text("收入").tag(Direction.income)
        }
        .pickerStyle(.segmented)
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
                TextField("我", text: $member)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)

            Divider().overlay(AppTheme.hairline)

            HStack {
                Text("账户")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 58, alignment: .leading)
                TextField("账户（选填）", text: $account)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
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
        var base = direction == .expense
            ? ["餐饮", "交通", "购物", "居住", "娱乐", "医疗", "学习", "人情", "其他"]
            : ["工资", "兼职", "理财", "红包", "报销", "其他"]
        if !base.contains(category), !category.isEmpty {
            base.insert(category, at: 0)
        }
        return base
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

        let record = LedgerRecord(
            id: editing?.id ?? ULID.generate(),
            bookUid: store.writeBookID,
            date: dateString(date),
            direction: direction,
            amountCents: cents,
            category: category.isEmpty ? "未分类" : category,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            member: member.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我" : member,
            account: account.trimmingCharacters(in: .whitespacesAndNewlines),
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
