import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                syncSection
                booksSection
                dataSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.grouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await store.syncNow()
            }
            .sheet(isPresented: $showLogin) {
                LoginView()
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var accountSection: some View {
        Section {
            if store.isLoggedIn {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accentSoft)
                            .frame(width: 44, height: 44)
                        Text(store.accountName.isEmpty ? "账" : String(store.accountName.prefix(1)))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.accountName)
                            .font(.system(size: 16, weight: .semibold))
                        Text(store.auth?.username ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    Text("已登录")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.income)
                }
                .padding(.vertical, 4)

                Button(role: .destructive) {
                    store.logout()
                } label: {
                    Text("退出登录")
                }
            } else {
                Button {
                    showLogin = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("登录云端账号")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("和桌面账本双向同步")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("账号")
        } footer: {
            if let auth = store.auth {
                Text("配对码 \(auth.pairCode) · 与桌面/手机使用同一账号")
            }
        }
    }

    private var syncSection: some View {
        Section {
            HStack {
                Label("同步状态", systemImage: store.isLoggedIn ? "checkmark.icloud" : "icloud.slash")
                Spacer()
                Text(store.isSyncing ? "同步中…" : (store.isLoggedIn ? "已连接" : "本地模式"))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Button {
                Task { await store.syncNow() }
            } label: {
                HStack {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if store.pendingCount > 0 {
                        Text("\(store.pendingCount) 条待同步")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .disabled(!store.isLoggedIn || store.isSyncing)

            if let lastSyncAt = store.lastSyncAt {
                HStack {
                    Text("上次同步")
                    Spacer()
                    Text(lastSyncAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            if let lastError = store.lastError {
                Text(lastError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        } header: {
            Text("同步")
        } footer: {
            Text("无网也能记；联网后自动补推，不会因为网络中断丢账。")
        }
    }

    private var booksSection: some View {
        Section {
            ForEach(store.books) { book in
                Button {
                    store.selectBook(book.id)
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: book.colorHex))
                            .frame(width: 9, height: 9)
                        Text(book.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if store.selectedBook?.id == book.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }
            }
        } header: {
            Text("账本")
        } footer: {
            Text("这边只做切换；新建/改名请在桌面端操作。")
        }
    }

    private var dataSection: some View {
        Section("数据") {
            ShareLink(item: store.exportCSV()) {
                Label("导出当前账本 CSV", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0 · 原生 SwiftUI")
                    .foregroundStyle(AppTheme.textSecondary)
            }
            HStack {
                Text("服务地址")
                Spacer()
                Text(store.auth?.endpoint ?? SyncService.defaultEndpoint)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            Text("这是自用 IPA。免费 Apple ID 签名 7 天有效，到期用 Sideloadly 覆盖安装即可，数据保留。")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}
