import SwiftUI

/// 已登录后的账号页：点头像只查看账号与同步状态，不再反复要求输入密码。
struct AccountView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("账号") {
                    LabeledContent("昵称", value: store.accountName.isEmpty ? "已登录" : store.accountName)
                    if let auth = store.auth {
                        LabeledContent("账号", value: auth.username)
                        LabeledContent("当前账本", value: store.selectedBook?.name ?? "我的账本")
                    }
                }

                Section("同步") {
                    LabeledContent("状态", value: store.isLoggedIn ? "已连接云端" : "本地模式")
                    if store.isSyncing {
                        LabeledContent("正在进行", value: "同步中")
                    }
                    if let last = store.lastSyncAt {
                        LabeledContent("上次同步", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let error = store.lastError, !error.isEmpty {
                        LabeledContent("上次错误", value: error)
                    }
                    Button("立即同步") {
                        Task { await store.syncNow() }
                    }
                }

                Section("账本") {
                    ForEach(store.books) { book in
                        HStack {
                            Circle()
                                .fill(Color(hex: book.colorHex))
                                .frame(width: 9, height: 9)
                            Text(book.name)
                            Spacer()
                            if book.id == store.writeBookID {
                                Text("当前")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }

                Section {
                    Button("退出登录", role: .destructive) {
                        store.logout()
                        dismiss()
                    }
                } footer: {
                    Text("退出登录不会删除本机账目；重新登录后继续同步。")
                }
            }
            .navigationTitle("我的账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
