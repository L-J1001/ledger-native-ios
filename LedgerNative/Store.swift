import Foundation
import Combine
import CryptoKit

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var books: [LedgerBook] = []
    @Published private(set) var records: [LedgerRecord] = []
    @Published private(set) var outbox: [OutboxOp] = []
    @Published private(set) var auth: AuthState?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncAt: Date?
    /// 每本账本自己的成员 / 分类 / 账户；不会跨账本串。
    @Published private(set) var taxonomies: [String: BookTaxonomy] = [:]
    /// 本机回收站；删除先进这里，可还原，彻底删除才移除。
    @Published private(set) var trash: [LedgerRecord] = []

    private let persistence = Persistence()
    private let sync = SyncService.shared
    private var cursor: Int64 = 0
    @Published private var selectedBookID: String?
    private var deviceID: String = ""
    private var token: String?

    init() {
        var savedToken: String?
        if let saved = persistence.load() {
            books = saved.books
            records = saved.records
            outbox = saved.outbox
            cursor = saved.cursor
            selectedBookID = saved.selectedBookID
            auth = saved.auth
            deviceID = saved.deviceID
            lastSyncAt = saved.lastSyncAt
            taxonomies = saved.taxonomies ?? [:]
            trash = saved.trash ?? []
            savedToken = saved.token
        }

        if books.isEmpty {
            let defaultBook = LedgerBook(id: "book-local", name: "我的账本")
            books = [defaultBook]
            selectedBookID = defaultBook.id
        }
        if deviceID.isEmpty {
            deviceID = "ios-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))
        }
        let keychainToken = Keychain.readToken()
        token = keychainToken ?? savedToken
        if keychainToken == nil, let token {
            Keychain.saveToken(token)
        }
        if auth != nil && token == nil {
            auth = nil
        }
        if selectedBookID == nil || !books.contains(where: { $0.id == selectedBookID }) {
            selectedBookID = books.first?.id
        }
    }

    var selectedBook: LedgerBook? {
        books.first(where: { $0.id == selectedBookID }) ?? books.first
    }

    var writeBookID: String {
        selectedBook?.id ?? auth?.bookUid ?? "book-local"
    }

    var isLoggedIn: Bool { auth != nil && token != nil }
    var accountName: String { auth?.displayName ?? "" }
    var pendingCount: Int { outbox.count }

    var balanceCents: Int {
        let base = selectedBook?.openingCents ?? 0
        let scoped = records.filter { $0.bookUid == writeBookID && !$0.excludeTotal }
        return base + scoped.reduce(0) { total, record in
            total + (record.direction == .income ? record.amountCents : -record.amountCents)
        }
    }

    var currentMonthKey: String {
        String(todayString().prefix(7))
    }

    var monthRecords: [LedgerRecord] {
        records.filter { $0.bookUid == writeBookID && $0.monthKey == currentMonthKey }
    }

    var monthIncomeCents: Int {
        monthRecords.filter { $0.direction == .income && !$0.excludeTotal }
            .reduce(0) { $0 + $1.amountCents }
    }

    var monthExpenseCents: Int {
        monthRecords.filter { $0.direction == .expense && !$0.excludeTotal }
            .reduce(0) { $0 + $1.amountCents }
    }

    var trashRecords: [LedgerRecord] {
        trash.filter { $0.bookUid == writeBookID }
            .sorted { $0.date > $1.date }
    }

    func restore(_ record: LedgerRecord) {
        trash.removeAll { $0.id == record.id && $0.bookUid == record.bookUid }
        upsertLocal(record)
        save()
        Task { await syncNow() }
    }

    func purge(_ record: LedgerRecord) {
        trash.removeAll { $0.id == record.id && $0.bookUid == record.bookUid }
        deleteLocal(record)
        save()
        Task { await syncNow() }
    }

    func clearTrash() {
        for record in trashRecords { deleteLocal(record) }
        trash.removeAll { $0.bookUid == writeBookID }
        save()
        Task { await syncNow() }
    }

    var recentRecords: [LedgerRecord] {
        records.filter { $0.bookUid == writeBookID }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.updatedAt > rhs.updatedAt }
                return lhs.date > rhs.date
            }
    }

    func records(for bookID: String) -> [LedgerRecord] {
        records.filter { $0.bookUid == bookID }.sorted { $0.date > $1.date }
    }

    // MARK: - 当前账本的成员 / 分类 / 账户

    private static let defaultExpenseCategories = ["餐饮", "交通", "住宿", "购物", "娱乐", "医疗", "学习", "日用品", "其他"]
    private static let defaultIncomeCategories = ["活动经费", "AA收款", "充值", "其他"]
    private static let defaultAccounts = ["现金", "微信", "支付宝", "银行卡"]

    private func taxonomy(for bookID: String) -> BookTaxonomy {
        taxonomies[bookID] ?? BookTaxonomy()
    }

    func categories(for direction: Direction) -> [String] {
        let bookID = writeBookID
        let custom = taxonomy(for: bookID)
        let synced = direction == .income ? custom.incomeCategories : custom.expenseCategories
        let base: [String]
        if synced.isEmpty {
            base = direction == .income ? Self.defaultIncomeCategories : Self.defaultExpenseCategories
        } else {
            base = synced
        }
        var seen = Set<String>()
        return base.filter { seen.insert($0).inserted }
    }

    var memberOptions: [String] {
        let bookID = writeBookID
        let custom = taxonomy(for: bookID).members
        var seen = Set<String>()
        return custom
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "我" }
            .filter { seen.insert($0).inserted }
    }

    var accountOptions: [String] {
        let bookID = writeBookID
        let custom = taxonomy(for: bookID).accounts
        let base = custom.isEmpty ? Self.defaultAccounts : custom
        var seen = Set<String>()
        return base.filter { seen.insert($0).inserted }
    }

    /// 新记一笔时默认选中的账户：按当前账本历史使用次数取最常用，
    /// 次数相同时取最近用过的那一个；没有历史时退回账户列表第一项。
    /// 只影响表单预选，不会改写任何历史账目。
    var preferredEntryAccount: String {
        let options = accountOptions
        guard let fallback = options.first else { return "" }
        let bookID = writeBookID
        var counts: [String: Int] = [:]
        var latest: [String: Int64] = [:]
        for record in records where record.bookUid == bookID {
            let name = record.account.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, options.contains(name) else { continue }
            counts[name, default: 0] += 1
            latest[name] = max(latest[name] ?? 0, record.updatedAt)
        }
        var best = fallback
        for option in options {
            let count = counts[option] ?? 0
            let last = latest[option] ?? 0
            let bestCount = counts[best] ?? 0
            let bestLast = latest[best] ?? 0
            if count > bestCount || (count == bestCount && last > bestLast) {
                best = option
            }
        }
        return best
    }

    /// 设置页/编辑器使用的统一入口；分类按收支方向区分。
    func taxonomyValues(kind: TaxonomyKind, direction: Direction = .expense) -> [String] {
        switch kind {
        case .members: return memberOptions
        case .accounts: return accountOptions
        case .categories: return categories(for: direction)
        }
    }

    func addTaxonomy(_ kind: TaxonomyKind, value rawValue: String,
                     direction: Direction = .expense) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let bookID = writeBookID
        var item = taxonomy(for: bookID)
        switch kind {
        case .members:
            if item.members.isEmpty { item.members = memberOptions }
            if !item.members.contains(value) { item.members.append(value) }
        case .accounts:
            if item.accounts.isEmpty { item.accounts = accountOptions }
            if !item.accounts.contains(value) { item.accounts.append(value) }
        case .categories:
            if direction == .income {
                if item.incomeCategories.isEmpty {
                    item.incomeCategories = categories(for: .income)
                }
                if !item.incomeCategories.contains(value) { item.incomeCategories.append(value) }
            } else {
                if item.expenseCategories.isEmpty {
                    item.expenseCategories = categories(for: .expense)
                }
                if !item.expenseCategories.contains(value) { item.expenseCategories.append(value) }
            }
        }
        taxonomies[bookID] = item
        save()
        queueBookMeta(for: bookID, taxonomy: item)
    }

    func removeTaxonomy(_ kind: TaxonomyKind, value: String,
                        direction: Direction = .expense) {
        let bookID = writeBookID
        var item = taxonomy(for: bookID)
        switch kind {
        case .members:
            if item.members.isEmpty { item.members = memberOptions }
            item.members.removeAll { $0 == value }
        case .accounts:
            if item.accounts.isEmpty { item.accounts = accountOptions }
            item.accounts.removeAll { $0 == value }
        case .categories:
            if direction == .income {
                if item.incomeCategories.isEmpty { item.incomeCategories = categories(for: .income) }
                item.incomeCategories.removeAll { $0 == value }
            } else {
                if item.expenseCategories.isEmpty { item.expenseCategories = categories(for: .expense) }
                item.expenseCategories.removeAll { $0 == value }
            }
        }
        taxonomies[bookID] = item
        save()
        queueBookMeta(for: bookID, taxonomy: item)
    }

    func isCustomTaxonomy(_ kind: TaxonomyKind, value: String,
                          direction: Direction = .expense) -> Bool {
        let item = taxonomy(for: writeBookID)
        switch kind {
        case .members: return item.members.contains(value)
        case .accounts: return item.accounts.contains(value)
        case .categories:
            return direction == .income
                ? item.incomeCategories.contains(value)
                : item.expenseCategories.contains(value)
        }
    }

    // MARK: - 拆分账目展示（与桌面一致：同一 split_group 折叠成一笔）

    var recentGroups: [RecordGroup] {
        grouped(records.filter { $0.bookUid == writeBookID })
    }

    func groups(for bookID: String) -> [RecordGroup] {
        grouped(records.filter { $0.bookUid == bookID })
    }

    private func grouped(_ source: [LedgerRecord]) -> [RecordGroup] {
        var order: [String] = []
        var buckets: [String: [LedgerRecord]] = [:]
        for record in source.sorted(by: { lhs, rhs in
            if lhs.date == rhs.date { return lhs.updatedAt > rhs.updatedAt }
            return lhs.date > rhs.date
        }) {
            let key: String
            if let group = record.splitGroup, !group.isEmpty {
                // 同一次拆分按「记账人」再收口：一个人名下的几笔合成一行，
                // 不再把每个明细行铺成独立流水，也不会把两个人的项目混在一行。
                // 日期一起进 key：万一历史数据里多个批次共用同一个 split_group，
                // 也只会各成一行，不会把几十笔并成一张卡。
                key = "split:\(group):\(record.member):\(record.date)"
            } else {
                key = "one:\(record.id)"
            }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(record)
        }
        return order.compactMap { key in
            guard let list = buckets[key], !list.isEmpty else { return nil }
            return RecordGroup(id: key, records: list)
        }
    }

    func splitRecords(group: String, bookID: String) -> [LedgerRecord] {
        records
            .filter { $0.bookUid == bookID && $0.splitGroup == group }
            .sorted { $0.id < $1.id }
    }

    private static func stableBookID(_ name: String) -> String {
        let digest = SHA256.hash(data: Data(name.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "book-" + String(hex.prefix(16))
    }

    /// 新建 / 编辑账本；期初余额和主题色与桌面 `book_upsert` 完全同口径。
    /// 返回 nil 表示成功，否则返回错误文案。
    func saveBook(id: String?, name rawName: String, openingCents: Int,
                  colorHex: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "账本名称不能为空" }
        guard openingCents >= 0 else { return "期初余额不能为负数" }

        let bookID: String
        if let id, !id.isEmpty {
            bookID = id
        } else {
            bookID = Self.stableBookID(name)
            if books.contains(where: { $0.id == bookID }) {
                return "已有同名账本，请换个名称"
            }
        }

        let book = LedgerBook(id: bookID, name: name,
                              openingCents: openingCents,
                              colorHex: colorHex.isEmpty ? "#3F7CFF" : colorHex,
                              updatedAt: nowMillis(),
                              taxonomy: taxonomies[bookID])
        if let index = books.firstIndex(where: { $0.id == bookID }) {
            books[index] = book
        } else {
            books.append(book)
        }
        selectedBookID = bookID
        queueBookMeta(for: bookID, taxonomy: taxonomies[bookID])
        save()
        Task { await syncNow() }
        return nil
    }

    /// 删除账本：本地先清空，再写一条 book_delete 墓碑。
    /// 不允许删除当前正在写的账本，避免界面落在空目录上。
    func deleteBook(id: String) -> String? {
        guard id != selectedBookID else { return "请先切换到另一本账本" }
        guard books.contains(where: { $0.id == id }) else { return "账本不存在" }
        removeLocalBook(id)
        outbox.removeAll { $0.bookUid == id }
        outbox.append(OutboxOp(
            id: ULID.generate(), bookUid: id, entity: "book",
            entityUid: id, op: "book_delete", payload: nil,
            updatedAt: nowMillis(), deviceId: deviceID, splitGroup: nil
        ))
        save()
        Task { await syncNow() }
        return nil
    }

    private func removeLocalBook(_ id: String) {
        records.removeAll { $0.bookUid == id }
        taxonomies.removeValue(forKey: id)
        books.removeAll { $0.id == id }
        if selectedBookID == id { selectedBookID = books.first?.id }
    }

    /// 账本元数据 + 成员/分类/账户一起推。桌面端 /v1/books 会带回 taxonomy，
    /// 手机端新增或移除后也走同一条 op，其他设备下次同步即可看到。
    private func queueBookMeta(for bookID: String, taxonomy: BookTaxonomy?) {
        guard let book = books.first(where: { $0.id == bookID }) else { return }
        let metaUID = "bookmeta-\(bookID)"
        outbox.removeAll { $0.entity == "book" && $0.entityUid == metaUID }
        outbox.append(OutboxOp(
            id: ULID.generate(), bookUid: bookID, entity: "book",
            entityUid: metaUID, op: "book_upsert",
            payload: .book(name: book.name, openingCents: book.openingCents,
                           color: book.colorHex, taxonomy: taxonomy),
            updatedAt: nowMillis(), deviceId: deviceID, splitGroup: nil
        ))
    }

    func monthLabel() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f.string(from: Date())
    }

    func selectBook(_ id: String) {
        selectedBookID = id
        save()
    }

    func upsert(_ record: LedgerRecord) {
        upsertLocal(record)
        save()
        Task { await syncNow() }
    }

    /// 拆分组保存：一次删旧、一次写新、只触发一次同步，避免半保存。
    func replaceRecords(_ newRecords: [LedgerRecord], removing oldRecords: [LedgerRecord]) {
        for old in oldRecords {
            deleteLocal(old)
        }
        for record in newRecords {
            var rec = record
            rec.pending = true
            upsertLocal(rec)
        }
        save()
        Task { await syncNow() }
    }

    func deleteGroup(_ group: RecordGroup) {
        // 主行按成员收起后，删除仍然作用于整笔拆分：只删掉某个人那几行
        // 会把同一次拆分的其余明细留成孤儿。
        let targets: [LedgerRecord]
        if let split = group.first.splitGroup, !split.isEmpty {
            targets = records.filter { $0.bookUid == group.first.bookUid && $0.splitGroup == split }
        } else {
            targets = group.records
        }
        for record in targets {
            trash.append(record)
            deleteLocal(record)
        }
        save()
        Task { await syncNow() }
    }

    private func upsertLocal(_ record: LedgerRecord) {
        var rec = record
        rec.pending = true
        if let index = records.firstIndex(where: { $0.id == rec.id && $0.bookUid == rec.bookUid }) {
            records[index] = rec
        } else {
            records.append(rec)
        }

        outbox.removeAll { $0.entity == "record" && $0.entityUid == rec.id }
        outbox.append(OutboxOp(
            id: ULID.generate(),
            bookUid: rec.bookUid,
            entity: "record",
            entityUid: rec.id,
            op: "upsert",
            payload: rec.payload,
            updatedAt: rec.updatedAt,
            deviceId: deviceID,
            splitGroup: rec.splitGroup
        ))
    }

    func delete(_ record: LedgerRecord) {
        if !trash.contains(where: { $0.id == record.id && $0.bookUid == record.bookUid }) {
            trash.append(record)
        }
        deleteLocal(record)
        save()
        Task { await syncNow() }
    }

    private func deleteLocal(_ record: LedgerRecord) {
        records.removeAll { $0.id == record.id && $0.bookUid == record.bookUid }
        outbox.removeAll { $0.entity == "record" && $0.entityUid == record.id }
        outbox.append(OutboxOp(
            id: ULID.generate(),
            bookUid: record.bookUid,
            entity: "record",
            entityUid: record.id,
            op: "delete",
            payload: nil,
            updatedAt: nowMillis(),
            deviceId: deviceID,
            splitGroup: nil
        ))
    }

    func login(username: String, password: String) async -> String? {
        let endpoint = auth?.endpoint ?? SyncService.defaultEndpoint
        do {
            let response = try await sync.login(
                endpoint: endpoint,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                deviceID: deviceID
            )
            let newAuth = AuthState(
                username: response.username,
                displayName: response.displayName,
                ownerId: response.owner,
                bookUid: response.bookUid,
                pairCode: response.pairCode,
                endpoint: response.endpoint
            )
            let oldOwner = auth?.ownerId
            auth = newAuth
            Keychain.saveToken(response.token)
            token = response.token

            // 换账号必须从 cursor=0 重新拉，否则会沿用上一个账号的游标，
            // 云端已有的账本/明细全部被跳过，看起来就像“账本对不上”。
            if let oldOwner, oldOwner != response.owner {
                records = []
                outbox = []
                books = []
                taxonomies = [:]
                trash = []
                cursor = 0
                selectedBookID = nil
            }

            if let existing = books.first(where: { $0.id == response.bookUid }) {
                selectedBookID = existing.id
            } else {
                let book = LedgerBook(id: response.bookUid, name: "我的账本", updatedAt: nowMillis())
                books.insert(book, at: 0)
                selectedBookID = book.id
            }

            // 登录前的本地账目保留在独立账本，不自动迁入账号默认账本，避免串账。
            let localID = "book-local"
            if records.contains(where: { $0.bookUid == localID }) {
                if !books.contains(where: { $0.id == localID }) {
                    books.insert(LedgerBook(id: localID, name: "本地账本"), at: 0)
                }
                selectedBookID = localID
            }
            save()
            await syncNow()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func logout() {
        Keychain.deleteToken()
        token = nil
        auth = nil
        save()
    }

    func syncNow() async {
        guard let auth, let token, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let remoteBooks = try await sync.books(endpoint: auth.endpoint, token: token)
            if !remoteBooks.isEmpty {
                reconcileBooks(remoteBooks)
            } else if books.isEmpty {
                books = [LedgerBook(id: auth.bookUid, name: "我的账本", updatedAt: nowMillis())]
                selectedBookID = auth.bookUid
            }

            while !outbox.isEmpty {
                let batch = Array(outbox.prefix(100))
                _ = try await sync.push(endpoint: auth.endpoint, token: token, ops: batch)
                let submitted = Set(batch.map { $0.entityUid })
                outbox.removeFirst(batch.count)
                for i in records.indices where submitted.contains(records[i].id) {
                    records[i].pending = false
                }
                save()
            }

            // 新账本 / 改名 / 期初是刚推上去的，必须再读一次 /v1/books 才会出现。
            let refreshedBooks = try await sync.books(endpoint: auth.endpoint, token: token)
            if !refreshedBooks.isEmpty {
                reconcileBooks(refreshedBooks)
            }

            var hasMore = true
            var guardCount = 0
            while hasMore && guardCount < 200 {
                let page = try await sync.pull(endpoint: auth.endpoint, token: token, since: cursor)
                for op in page.ops {
                    apply(op)
                }
                cursor = page.cursor
                hasMore = page.hasMore
                guardCount += 1
                save()
            }

            lastSyncAt = Date()
            lastError = nil
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 安全账本对账：按云端 book_uid 合并元数据，不自动迁移本地记录。
    private func reconcileBooks(_ remote: [LedgerBook]) {
        let remoteIDs = Set(remote.map(\.id))
        for book in remote {
            if let taxonomy = book.taxonomy,
               !outbox.contains(where: { $0.entity == "book" && $0.bookUid == book.id }) {
                taxonomies[book.id] = taxonomy
            }
        }

        var localSurvivors: [LedgerBook] = []
        var toRemove: [String] = []
        for local in books where !remoteIDs.contains(local.id) {
            // 云端目录里已经没有这本：只保留还没推上去的新账本，
            // 其余视为其它设备删除，连同本机账目一起清掉。
            let pendingCreate = outbox.contains {
                $0.entity == "book" && $0.bookUid == local.id && $0.op == "book_upsert"
            }
            if pendingCreate { localSurvivors.append(local) }
            else { toRemove.append(local.id) }
        }
        for id in toRemove { removeLocalBook(id) }
        books = remote + localSurvivors
        if let selectedBookID, books.contains(where: { $0.id == selectedBookID }) {
            self.selectedBookID = selectedBookID
        } else {
            selectedBookID = books.first?.id
        }
    }

    private func apply(_ op: RemoteOp) {
        if op.entity == "book" {
            if op.op == "book_delete" || op.op == "delete" {
                removeLocalBook(op.bookUid)
            }
            return
        }
        guard op.entity == "record" else { return }
        if op.op == "delete" {
            records.removeAll { $0.id == op.entityUid && $0.bookUid == op.bookUid }
            return
        }
        guard let payload = op.payload else { return }
        let incoming = LedgerRecord.from(
            payload: payload,
            bookUid: op.bookUid,
            recordUid: op.entityUid,
            updatedAt: op.updatedAt,
            splitGroup: op.splitGroup
        )
        if let index = records.firstIndex(where: { $0.id == incoming.id && $0.bookUid == incoming.bookUid }) {
            if incoming.updatedAt >= records[index].updatedAt {
                records[index] = incoming
            }
        } else {
            records.append(incoming)
        }
    }

    func exportCSV() -> String {
        let header = "日期,方向,金额(元),分类,成员,备注,账户,账本"
        let rows = records
            .filter { $0.bookUid == writeBookID }
            .sorted { $0.date > $1.date }
            .map { record -> String in
                let fields = [
                    record.date,
                    record.direction.title,
                    String(format: "%.2f", record.amountYuan),
                    record.category,
                    record.member,
                    record.note,
                    record.account,
                    selectedBook?.name ?? "我的账本"
                ]
                return fields.map { field in
                    let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                    return "\"\(escaped)\""
                }.joined(separator: ",")
            }
        return ([header] + rows).joined(separator: "\n")
    }

    private func save() {
        let state = PersistedState(
            books: books,
            records: records,
            outbox: outbox,
            cursor: cursor,
            selectedBookID: selectedBookID,
            auth: auth,
            deviceID: deviceID,
            lastSyncAt: lastSyncAt,
            taxonomies: taxonomies,
            trash: trash,
            token: token
        )
        persistence.save(state)
    }
}
