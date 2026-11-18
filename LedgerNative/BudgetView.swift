import SwiftUI

struct BudgetView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init() {
        _text = State(initialValue: "")
    }

    var body: some View {
        Form {
            Section("本月预算") {
                HStack {
                    Text("¥")
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("0.00", text: $text)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                }
                Text("预算只存在本机，不会写进账目；按当前账本单独计算。")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Section {
                Button("保存预算") { save() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if store.budgetCents > 0 {
                    Button("清除预算", role: .destructive) {
                        store.setBudget(0)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("本月预算")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            text = store.budgetCents > 0 ? String(format: "%.2f", Double(store.budgetCents) / 100) : ""
        }
    }

    private func save() {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: ".")
        guard let yuan = Double(cleaned), yuan >= 0 else { return }
        store.setBudget(Int(round(yuan * 100)))
        dismiss()
    }
}
