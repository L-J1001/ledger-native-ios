import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var showLogin = false
    @State private var bookTarget: BookEditorTarget?
    @State private var pendingDeleteBook: LedgerBook?

    var body: some View {
        NavigationStack {
            List {
                accountSection
                syncSection
                booksSection
                taxonomySection
                trashSection
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
            .alert("删除账本？", isPresented: Binding(
                get: { pendingDeleteBook != nil },
                set: { if !$0 { pendingDeleteBook = nil } }
            ), presenting: pendingDeleteBook) { book in
                Button("永久删除", role: .destructive) {
                    _ = store.deleteBook(id: book.id)
                    pendingDeleteBook = nil
                }
                Button("取消", role: .cancel) { pendingDeleteBook = nil }
            } message: { book in
                Text("「\(book.name)」的本机账目会清空，并同步删除到其它设备，无法恢复。")
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
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if store.selectedBook?.id != book.id {
                        Button(role: .destructive) {
                            pendingDeleteBook = book
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
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

    private var trashSection: some View {
        Section("回收站") {
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

    /// 版本号必须直接读包信息：写死过一次 1.2.6，结果装到 1.4.1 还显示旧号。
    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "\(short) · 原生 SwiftUI" : "\(short) (\(build)) · 原生 SwiftUI"
    }

    /// 从包内 embedded.mobileprovision 读取签名到期日。
    /// 免签 IPA 有效期由描述文件决定，直接看系统返回的签名信息并不可靠。
    private var provisionExpiration: Date? {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = FileManager.default.contents(atPath: path) else { return nil }
        // 描述文件外层是 CMS 签名，不能整段按 UTF-8 解码；
        // 先定位 plist 的 key，再只解码它后面一小段。
        let marker = Data("<key>ExpirationDate</key>".utf8)
        guard let range = data.range(of: marker) else { return nil }
        let tailEnd = min(data.count, range.upperBound + 220)
        let tailData = data.subdata(in: range.upperBound..<tailEnd)
        guard let tail = String(data: tailData, encoding: .utf8),
              let start = tail.range(of: "<date>"),
              let end = tail.range(of: "</date>") else { return nil }
        let raw = String(tail[start.upperBound..<end.lowerBound])
        let iso = ISO8601DateFormatter()
        return iso.date(from: raw)
    }

    private var signatureExpired: Bool {
        guard let date = provisionExpiration else { return false }
        return date < Date()
    }

    private var signatureRemainingText: String {
        guard let date = provisionExpiration else { return "读取不到描述文件有效期" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        let expiry = f.string(from: date)
        if days < 0 { return "已过期 · \(expiry)" }
        if days == 0 { return "今天到期 · \(expiry)" }
        return "剩余 \(days) 天 · \(expiry) 到期"
    }

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text(appVersionText)
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
            HStack {
                Text("签名剩余")
                Spacer()
                Text(signatureRemainingText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(signatureExpired ? AppTheme.expense : AppTheme.textSecondary)
            }
            Text("这是自用 IPA。免费 Apple ID 签名 7 天有效，到期用 Sideloadly 覆盖安装即可，数据保留。")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}

