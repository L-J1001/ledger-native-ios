import SwiftUI

struct BookEditorTarget: Identifiable {
    let id = UUID()
    let book: LedgerBook?
}

struct BookEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    private let book: LedgerBook?
    @State private var name: String
    @State private var openingText: String
    @State private var colorHex: String
    @State private var errorMessage = ""
    @State private var showError = false

    private let palette = ["#3F7CFF", "#0FA069", "#E54259", "#C79A3A", "#6B5BD2", "#2D9CDB"]

    init(book: LedgerBook?) {
        self.book = book
        _name = State(initialValue: book?.name ?? "")
        _openingText = State(initialValue: book.map { String(format: "%.2f", Double($0.openingCents) / 100.0) } ?? "0.00")
        _colorHex = State(initialValue: book?.colorHex ?? "#3F7CFF")
    }

    var body: some View {
        Form {
            Section("账本") {
                TextField("账本名称", text: $name)
                HStack {
                    Text("期初余额")
                    Spacer()
                    Text("¥")
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("0.00", text: $openingText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                        .monospacedDigit()
                }
            }

            Section("主题色") {
                HStack(spacing: 12) {
                    ForEach(palette, id: \.self) { hex in
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(colorHex == hex ? 0.9 : 0), lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Text(book == nil
                     ? "新账本会先在手机本地建好；登录后自动推到云端，桌面端也能看到。"
                     : "改期初只影响余额显示，不会改动已有明细。")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Section {
                Button {
                    save()
                } label: {
                    Text(book == nil ? "创建账本" : "保存修改")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(book == nil ? "新建账本" : "编辑账本")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: $showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func save() {
        let cleaned = openingText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: ".")
        let yuan = Double(cleaned) ?? 0
        guard yuan >= 0 else {
            errorMessage = "期初余额不能为负数"
            showError = true
            return
        }
        let cents = Int(round(yuan * 100))
        if let error = store.saveBook(id: book?.id, name: name,
                                      openingCents: cents, colorHex: colorHex) {
            errorMessage = error
            showError = true
            return
        }
        dismiss()
    }
}
