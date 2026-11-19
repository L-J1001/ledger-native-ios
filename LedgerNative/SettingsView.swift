import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var showLogin = false
    @State private var bookTarget: BookEditorTarget?

    var body: some View {
        NavigationStack {
            List {
                accountSection
                syncSection
                booksSection
                taxonomySection
                budgetSection
                dataSection
                supportSection
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
            .sheet(item: $bookTarget) { target in
                NavigationStack {
                    BookEditorView(book: target.book)
                        .environmentObject(store)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("取消") { bookTarget = nil }
                            }
                        }
                }
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
                HStack(spacing: 10) {
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        bookTarget = BookEditorTarget(book: book)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button {
                bookTarget = BookEditorTarget(book: nil)
            } label: {
                Label("新建账本", systemImage: "plus.circle.fill")
                    .foregroundStyle(AppTheme.accent)
            }
        } header: {
            Text("账本")
        } footer: {
            Text("账本可在这里切、建、改名和改期初；每个账本的成员/分类/账户只显示当前账本。")
        }
    }

    private var taxonomySection: some View {
        Section {
            NavigationLink {
                TaxonomyView(kind: .members)
                    .environmentObject(store)
            } label: {
                Label("成员管理", systemImage: "person.2.fill")
            }
            NavigationLink {
                TaxonomyView(kind: .categories)
                    .environmentObject(store)
            } label: {
                Label("分类管理", systemImage: "square.grid.2x2.fill")
            }
            NavigationLink {
                TaxonomyView(kind: .accounts)
                    .environmentObject(store)
            } label: {
                Label("账户管理", systemImage: "creditcard.fill")
            }
        } header: {
            Text("当前账本 · 选项")
        } footer: {
            Text("记账时只从这些选项里选，不再手输；桌面端记录里用过的值同步后会自动出现。")
        }
    }

    private var budgetSection: some View {
        Section("预算与回收站") {
            NavigationLink {
                BudgetView()
                    .environmentObject(store)
            } label: {
                HStack {
                    Label("本月预算", systemImage: "gauge.with.dots.needle.67percent")
                    Spacer()
                    Text(store.budgetCents > 0 ? money(store.budgetCents) : "未设置")
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            NavigationLink {
                TrashView()
                    .environmentObject(store)
            } label: {
                HStack {
                    Label("回收站", systemImage: "trash")
                    Spacer()
                    Text("\(store.trashRecords.count) 条")
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private var dataSection: some View {
        Section("数据") {
            ShareLink(item: store.exportCSV()) {
                Label("导出当前账本 CSV", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var supportSection: some View {
        Section {
            NavigationLink {
                HealthView()
                    .environmentObject(store)
            } label: {
                Label("数据体检", systemImage: "stethoscope")
            }
            NavigationLink {
                FeedbackView()
                    .environmentObject(store)
            } label: {
                Label("意见反馈", systemImage: "bubble.left.and.bubble.right")
            }
        } header: {
            Text("帮助与支持")
        } footer: {
            Text("反馈匿名提交；数据体检只在本机运行，不上传账目。")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text("1.2.6 · 原生 SwiftUI")
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

