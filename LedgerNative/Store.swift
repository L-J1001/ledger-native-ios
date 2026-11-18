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
    /// 每本账本的月预算（分）；0 表示未设置。
    @Published private(set) var budgets: [String: Int] = [:]
    /// 本机回收站；删除先进这里，可还原，彻底删除才移除。
    @Published private(set) var trash: [LedgerRecord] = []

    private let persistence = Persistence()
    private let sync = SyncService.shared
    private var cursor: Int64 = 0
    private var selectedBookID: String?
    private var deviceID: String = ""
    private var token: String?

    init() {
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
            budgets = saved.budgets ?? [:]
            trash = saved.trash ?? []
        }

        if books.isEmpty {
            let defaultBook = LedgerBook(id: "book-local", name: "我的账本")
            books = [defaultBook]
            selectedBookID = defaultBook.id
        }
        if deviceID.isEmpty {
            deviceID = "ios-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))
        }
        token = Keychain.readToken()
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

    var budgetCents: Int { budgets[writeBookID] ?? 0 }
    var monthBudgetRemaining: Int { max(0, budgetCents - monthExpenseCents) }

    func setBudget(_ cents: Int) {
        budgets[writeBookID] = max(0, cents)
        save()
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

    private static let defaultMembers = ["我", "家人", "共同"]
    private static let defaultExpenseCategories = ["餐饮", "交通", "购物", "居住", "娱乐", "医疗", "学习", "人情", "其他"]
    private static let defaultIncomeCategories = ["工资", "兼职", "理财", "红包", "报销", "其他"]
    private static let defaultAccounts = ["现金", "微信", "支付宝", "银行卡"]

    private func taxonomy(for bookID: String) -> BookTaxonomy {
        taxonomies[bookID] ?? BookTaxonomy()
    }

    func categories(for direction: Direction) -> [String] {
        let bookID = writeBookID
        let custom = taxonomy(for: bookID)
        let defaults = direction == .income ? Self.defaultIncomeCategories : Self.defaultExpenseCategories
        let used = records
            .filter { $0.bookUid == bookID && $0.direction == direction }
            .map(\.category)
            .filter { !$0.isEmpty && $0 != "未分类" }
        var seen = Set<String>()
        return (defaults + (direction == .income ? custom.incomeCategories : custom.expenseCategories) + used)
            .filter { seen.insert($0).inserted }
    }

    var memberOptions: [String] {
        let bookID = writeBookID
        let custom = taxonomy(for: bookID).members
        let used = records.filter { $0.bookUid == bookID }.map(\.member).filter { !$0.isEmpty }
        var seen = Set<String>()
        return (Self.defaultMembers + custom + used).filter { seen.insert($0).inserted }
    }

    var accountOptions: [String] {
        let bookID = writeBookID
        let custom = taxonomy(for: bookID).accounts
        let used = records.filter { $0.bookUid == bookID }.map(\.account).filter { !$0.isEmpty }
        var seen = Set<String>()
        return (Self.defaultAccounts + custom + used).filter { seen.insert($0).inserted }
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
            if !item.members.contains(value) { item.members.append(value) }
        case .accounts:
            if !item.accounts.contains(value) { item.accounts.append(value) }
        case .categories:
            if direction == .income {
                if !item.incomeCategories.contains(value) { item.incomeCategories.append(value) }
            } else {
                if !item.expenseCategories.contains(value) { item.expenseCategories.append(value) }
            }
        }
        taxonomies[bookID] = item
        save()
    }

    func removeTaxonomy(_ kind: TaxonomyKind, value: String,
                        direction: Direction = .expense) {
        let bookID = writeBookID
        var item = taxonomy(for: bookID)
        switch kind {
        case .members: item.members.removeAll { $0 == value }
        case .accounts: item.accounts.removeAll { $0 == value }
        case .categories:
            if direction == .income { item.incomeCategories.removeAll { $0 == value } }
            else { item.expenseCategories.removeAll { $0 == value } }
        }
        taxonomies[bookID] = item
        save()
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
            let key = record.splitGroup?.isEmpty == false ? "split:\(record.splitGroup!)" : "one:\(record.id)"
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
                              updatedAt: nowMillis())
        if let index = books.firstIndex(where: { $0.id == bookID }) {
            books[index] = book
        } else {
            books.append(book)
        }
        selectedBookID = bookID

        let metaUID = "bookmeta-\(bookID)"
        outbox.removeAll { $0.entity == "book" && $0.entityUid == metaUID }
        outbox.append(OutboxOp(
            id: ULID.generate(), bookUid: bookID, entity: "book",
            entityUid: metaUID, op: "book_upsert",
            payload: .book(name: name, openingCents: openingCents, color: colorHex),
            updatedAt: book.updatedAt, deviceId: deviceID, splitGroup: nil
        ))
        save()
        Task { await syncNow() }
        return nil
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
        for record in group.records {
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
            auth = newAuth
            Keychain.saveToken(response.token)
            token = response.token

            if let existing = books.first(where: { $0.id == response.bookUid }) {
                selectedBookID = existing.id
            } else {
                let book = LedgerBook(id: response.bookUid, name: "我的账本", updatedAt: nowMillis())
                books.insert(book, at: 0)
                selectedBookID = book.id
            }

            // 登录前在本地记的账，迁移到账号的真实 book_uid，避免推到一个云端不存在的账本。
            let localID = "book-local"
            for i in records.indices where records[i].bookUid == localID {
                records[i].bookUid = response.bookUid
            }
            for i in outbox.indices where outbox[i].bookUid == localID {
                outbox[i].bookUid = response.bookUid
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
                let remoteIDs = Set(remoteBooks.map(\.id))
                // 本机新建但云端还没收录 / 还没推成功的账本不能因为一次刷新就消失。
                let localPending = books.filter { !remoteIDs.contains($0.id) }
                books = remoteBooks + localPending
                if selectedBookID == nil || !books.contains(where: { $0.id == selectedBookID }) {
                    selectedBookID = books.first?.id
                }
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
                let remoteIDs = Set(refreshedBooks.map(\.id))
                let localPending = books.filter { !remoteIDs.contains($0.id) }
                books = refreshedBooks + localPending
                if selectedBookID == nil || !books.contains(where: { $0.id == selectedBookID }) {
                    selectedBookID = books.first?.id
                }
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

    private func apply(_ op: RemoteOp) {
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
            budgets: budgets,
            trash: trash
        )
        persistence.save(state)
    }
}
