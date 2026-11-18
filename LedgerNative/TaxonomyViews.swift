import SwiftUI

struct TaxonomyView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var newMember = ""
    @State private var newCategory = ""
    @State private var newAccount = ""

    var body: some View {
        List {
            Section {
                ForEach(store.customMembers, id: \.self) { member in
                    HStack {
                        Label(member, systemImage: "person")
                        Spacer()
                        Button(role: .destructive) {
                            store.removeMember(member)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("新增成员", text: $newMember)
                    Button("添加") {
                        store.addMember(newMember)
                        newMember = ""
                    }
                    .disabled(newMember.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("成员")
            } footer: {
                Text("记账时只能从列表选择，避免手输错字导致账本对不上。")
            }

            Section {
                ForEach(store.customCategories, id: \.self) { category in
                    HStack {
                        Label(category, systemImage: "tag")
                        Spacer()
                        Button(role: .destructive) {
                            store.removeCategory(category)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("新增分类", text: $newCategory)
                    Button("添加") {
                        store.addCategory(newCategory)
                        newCategory = ""
                    }
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("分类")
            } footer: {
                Text("常用分类会自动出现；桌面端已经用过的分类同步后也会出现在这里。")
            }

            Section {
                ForEach(store.customAccounts, id: \.self) { account in
                    HStack {
                        Label(account, systemImage: "creditcard")
                        Spacer()
                        Button(role: .destructive) {
                            store.removeAccount(account)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("新增账户", text: $newAccount)
                    Button("添加") {
                        store.addAccount(newAccount)
                        newAccount = ""
                    }
                    .disabled(newAccount.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("账户")
            }
        }
        .navigationTitle("成员 · 分类 · 账户")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BudgetView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var budgetText = ""
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    Text("¥")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("0", text: $budgetText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .focused($focused)
                }
                HStack {
                    Text("本月已支出")
                    Spacer()
                    Text(money(store.monthExpenseCents))
                        .foregroundStyle(AppTheme.expense)
                }
                HStack {
                    Text("剩余")
                    Spacer()
                    Text(money(store.monthBudgetRemainingCents))
                        .foregroundStyle(store.monthExpenseCents > store.monthlyBudgetCents ? AppTheme.expense : AppTheme.income)
                }
            } header: {
                Text("本月预算")
            } footer: {
                Text("预算只保存在本机，用于首页和统计页的进度提醒；不会改动桌面端设置。")
            }

            Section {
                ForEach([500, 1000, 2000, 3000, 5000], id: \.self) { preset in
                    Button("¥\(preset)") {
                        budgetText = "\(preset)"
                        store.setBudget(preset * 100)
                    }
                }
            }

            Section {
                Button("保存预算") {
                    let value = Double(budgetText.replacingOccurrences(of: ",", with: ".")) ?? 0
                    store.setBudget(Int(round(value * 100)))
                    focused = false
                }
                .disabled(budgetText.isEmpty)
                Button("清除预算", role: .destructive) {
                    store.setBudget(0)
                    budgetText = ""
                }
            }
        }
        .navigationTitle("预算")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            budgetText = store.monthlyBudgetCents > 0
                ? String(format: "%.2f", Double(store.monthlyBudgetCents) / 100.0)
                : ""
        }
    }
}
