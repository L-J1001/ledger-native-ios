import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var reminder: RenewalReminder
    @State private var showAccount = false
    @State private var showBudget = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                renewalSection
                syncSection
                preferenceSection
                booksSection
                dataSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.grouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await store.syncNow() }
            .sheet(isPresented: $showAccount) {
                AccountSheet().environmentObject(store)
            }
            .sheet(isPresented: $showBudget) {
                NavigationStack { BudgetView().environmentObject(store) }
            }
        }
    }

    private var accountSection: some View {
        Section {
            Button { showAccount = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accentSoft)
                            .frame(width: 46, height: 46)
                        Text(store.isLoggedIn ? (store.accountName.isEmpty ? "账" : String(store.accountName.prefix(1))) : "账")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.isLoggedIn ? (store.accountName.isEmpty ? "已登录" : store.accountName) : "登录云端账号")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(store.isLoggedIn ? (store.auth?.username ?? "") : "和桌面账本双向同步")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)

            if store.isLoggedIn {
                HStack {
                    Text("配对码")
                    Spacer()
                    Text(store.auth?.pairCode ?? "—")
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()
                }
                Button(role: .destructive) {
                    store.logout()
                } label: {
                    Text("退出登录")
                }
            }
        } header: {
            Text("账号")
        } footer: {
            Text(store.isLoggedIn ? "手机和桌面使用同一账号；退出只清除本机会话，不影响云端账本。" : "未登录也可以离线记账，登录后再补同步。")
        }
    }

    private var renewalSection: some View {
        Section {
            HStack {
                Label("签名剩余", systemImage: "signature")
                Spacer()
                Text("\(reminder.daysRemaining) 天")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(reminder.daysRemaining <= 2 ? AppTheme.expense : AppTheme.income)
            }
            HStack {
                Text("到期日")
                Spacer()
                Text(reminder.expiryDate.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Button("我已续签，重新计时") {
                reminder.markRenewed()
            }
            Text("免费 Apple ID 签名 7 天有效。App 会在第 5、6、7 天发通知；到期前打开电脑上的 Sideloadly 覆盖安装即可，账目保留。")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        } header: {
            Text("签名与续签")
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

    private var preferenceSection: some View {
        Section {
            NavigationLink {
                TaxonomyView().environmentObject(store)
            } label: {
                Label("成员 · 分类 · 账户", systemImage: "square.grid.2x2")
            }

            Button { showBudget = true } label: {
                HStack {
                    Label("本月预算", systemImage: "gauge.with.dots.needle.50percent")
                    Spacer()
                    Text(store.monthlyBudgetCents > 0 ? money(store.monthlyBudgetCents) : "未设置")
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        } header: {
            Text("记账偏好")
        } footer: {
            Text("成员、分类和账户只从列表选择，避免手输错字导致账本对不上；桌面端已用过的值同步后会自动出现。")
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
                Text("1.1.0 · 原生 SwiftUI · iPhone / iPad")
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
