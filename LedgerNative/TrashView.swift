import SwiftUI

struct TrashView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var confirmClear = false

    var body: some View {
        List {
            if store.trashRecords.isEmpty {
                ContentUnavailableView("回收站是空的", systemImage: "trash",
                                      description: Text("删除的账目会先放这里，可还原"))
            } else {
                Section {
                    ForEach(store.trashRecords) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.category.isEmpty ? "未分类" : record.category)
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text("\(record.direction.sign)\(money(record.amountCents))")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                            Text("\(shortDate(record.date)) · \(record.member)")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.purge(record)
                            } label: {
                                Label("彻底删除", systemImage: "trash.slash")
                            }
                            Button {
                                store.restore(record)
                            } label: {
                                Label("还原", systemImage: "arrow.uturn.backward")
                            }
                            .tint(AppTheme.accent)
                        }
                    }
                } footer: {
                    Text("还原后会重新同步到云端；彻底删除不可恢复。")
                }
            }
        }
        .navigationTitle("回收站")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.trashRecords.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) { confirmClear = true }
                }
            }
        }
        .confirmationDialog("清空当前账本回收站？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { store.clearTrash() }
        }
    }
}
