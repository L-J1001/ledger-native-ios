import SwiftUI

struct TaxonomyView: View {
    @EnvironmentObject private var store: LedgerStore
    let kind: TaxonomyKind
    @State private var direction: Direction = .expense
    @State private var newValue = ""

    var body: some View {
        List {
            Section {
                if kind == .categories {
                    Picker("收支方向", selection: $direction) {
                        Text("支出分类").tag(Direction.expense)
                        Text("收入分类").tag(Direction.income)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                ForEach(values, id: \.self) { value in
                    HStack {
                        Text(value)
                        Spacer()
                        if store.isCustomTaxonomy(kind, value: value, direction: direction) {
                            Button("移除", role: .destructive) {
                                store.removeTaxonomy(kind, value: value, direction: direction)
                            }
                            .font(.system(size: 12))
                        } else {
                            Text("账目里用过")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("当前账本 · \(store.selectedBook?.name ?? "我的账本")")
            } footer: {
                Text("记账时只能从这些选项里选择，避免输错导致账本对不上。桌面端记录里用过的成员/分类/账户，同步后会自动出现在这里。")
            }

            Section("新增") {
                HStack {
                    TextField(kind == .members ? "新增成员" : (kind == .accounts ? "新增账户" : "新增分类"),
                              text: $newValue)
                    Button("添加") {
                        let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        store.addTaxonomy(kind, value: value, direction: direction)
                        newValue = ""
                    }
                    .disabled(newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("其它选项") {
                ForEach(TaxonomyKind.allCases.filter { $0 != kind }) { item in
                    NavigationLink {
                        TaxonomyView(kind: item)
                            .environmentObject(store)
                    } label: {
                        Label("管理\(item.title)", systemImage: item == .members
                              ? "person.2.fill" : (item == .accounts ? "creditcard.fill" : "square.grid.2x2.fill"))
                    }
                }
            }
        }
        .navigationTitle("管理\(kind.title)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var values: [String] {
        store.taxonomyValues(kind: kind, direction: direction)
    }
}
