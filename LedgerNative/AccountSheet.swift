import SwiftUI

struct AccountSheet: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoggedIn {
                    loggedIn
                } else {
                    loggedOut
                }
            }
            .background(AppTheme.grouped.ignoresSafeArea())
            .navigationTitle(store.isLoggedIn ? "我的账号" : "登录云端")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView()
                    .environmentObject(store)
            }
        }
    }

    private var loggedOut: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(AppTheme.accent)
            VStack(spacing: 6) {
                Text("登录后和桌面账本同步")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("手机记一笔，电脑上也能看到。未登录时也能离线记账。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Button("登录云端账号") { showLogin = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 30)
            Spacer()
        }
        .padding(20)
    }

    private var loggedIn: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accentSoft)
                            .frame(width: 74, height: 74)
                        Text(store.accountName.isEmpty ? "账" : String(store.accountName.prefix(1)))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text(store.accountName.isEmpty ? "已登录" : store.accountName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(store.auth?.username ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .cardStyle()

                VStack(spacing: 0) {
                    infoRow("配对码", store.auth?.pairCode ?? "—", icon: "number")
                    Divider().overlay(AppTheme.hairline)
                    infoRow("账本", store.selectedBook?.name ?? "我的账本", icon: "books.vertical")
                    Divider().overlay(AppTheme.hairline)
                    infoRow("同步状态", store.isSyncing ? "同步中…" : (store.pendingCount > 0 ? "\(store.pendingCount) 条待同步" : "已同步"), icon: "checkmark.icloud")
                    Divider().overlay(AppTheme.hairline)
                    infoRow("服务地址", store.auth?.endpoint ?? SyncService.defaultEndpoint, icon: "link")
                }
                .cardStyle(padding: 4)

                Button {
                    Task { await store.syncNow() }
                } label: {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.isSyncing)

                Button(role: .destructive) {
                    store.logout()
                    dismiss()
                } label: {
                    Text("退出登录")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .padding(18)
        }
    }

    private func infoRow(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}
