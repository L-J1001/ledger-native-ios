import Foundation
import Combine

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var books: [LedgerBook] = []
    @Published private(set) var records: [LedgerRecord] = []
    @Published private(set) var outbox: [OutboxOp] = []
    @Published private(set) var auth: AuthState?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncAt: Date?

    @Published var customMembers: [String] = []
    @Published var customCategories: [String] = []
    @Published var customAccounts: [String] = []
    @Published var monthlyBudgetCents: Int = 0

    private let persistence = Persistence()
    private let sync = SyncService.shared
    private let defaults = UserDefaults.standard
    private var cursor: Int64 = 0
    private var selectedBookID: String?
    private var deviceID: String = ""
    private var token: String?

    private let membersKey = "ledger.preferences.members"
    private let categoriesKey = "ledger.preferences.categories"
    private let accountsKey = "ledger.preferences.accounts"
    private let budgetKey = "ledger.preferences.budgetCents"

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
        }

        customMembers = defaults.stringArray(forKey: membersKey) ?? ["我", "家人", "共同"]
        customCategories = defaults.stringArray(forKey: categoriesKey) ?? []
        customAccounts = defaults.stringArray(forKey: accountsKey) ?? ["现金", "微信", "支付宝", "银行卡"]
        monthlyBudgetCents = defaults.integer(forKey: budgetKey)

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
        monthRecords.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
    }

    var monthExpenseCents: Int {
        monthRecords.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents }
    }

    var monthBudgetRemainingCents: Int {
        max(0, monthlyBudgetCents - monthExpenseCents)
    }

    var monthBudgetRatio: Double {
        guard monthlyBudgetCents > 0 else { return 0 }
        return min(1.5, Double(monthExpenseCents) / Double(monthlyBudgetCents))
    }

    var recentRecords: [LedgerRecord] {
        records.filter { $0.bookUid == writeBookID }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.updatedAt > rhs.updatedAt }
                return lhs.date > rhs.date
            }
    }

    var allMembers: [String] {
        let used = records.map { $0.member }.filter { !$0.isEmpty }
        return Array(Set(customMembers + used + ["我"])).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    var allAccounts: [String] {
        let used = records.map { $0.account }.filter { !$0.isEmpty }
        return Array(Set(customAccounts + used)).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    func categories(for direction: Direction) -> [String] {
        let used = records.filter { $0.direction == direction }.map { $0.category }.filter { !$0.isEmpty }
        let base = direction == .expense
            ? ["餐饮", "交通", "购物", "居住", "娱乐", "医疗", "学习", "人情", "其他"]
            : ["工资", "兼职", "理财", "红包", "报销", "其他"]
        let custom = customCategories
        return Array(Set(base + custom + used)).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    func records(for bookID: String) -> [LedgerRecord] {
        records.filter { $0.bookUid == bookID }.sorted { $0.date > $1.date }
    }

    func records(inMonth monthKey: String, bookID: String? = nil) -> [LedgerRecord] {
        records.filter { $0.bookUid == (bookID ?? writeBookID) && $0.monthKey == monthKey }
            .sorted { $0.date > $1.date }
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

    func setBudget(_ cents: Int) {
        monthlyBudgetCents = max(0, cents)
        defaults.set(monthlyBudgetCents, forKey: budgetKey)
    }

    func addMember(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customMembers.contains(trimmed) else { return }
        customMembers.append(trimmed)
        savePreferences()
    }

    func removeMember(_ value: String) {
        customMembers.removeAll { $0 == value }
        savePreferences()
    }

    func addCategory(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customCategories.contains(trimmed) else { return }
        customCategories.append(trimmed)
        savePreferences()
    }

    func removeCategory(_ value: String) {
        customCategories.removeAll { $0 == value }
        savePreferences()
    }

    func addAccount(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customAccounts.contains(trimmed) else { return }
        customAccounts.append(trimmed)
        savePreferences()
    }

    func removeAccount(_ value: String) {
        customAccounts.removeAll { $0 == value }
        savePreferences()
    }

    func upsert(_ record: LedgerRecord) {
        var rec = record
        rec.pending = true
        if let index = records.firstIndex(where: { $0.id == rec.id && $0.bookUid == rec.bookUid }) {
            records[index] = rec
        } else {
            records.append(rec)
        }

        outbox.removeAll { $0.entityUid == rec.id }
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
        save()
        Task { await syncNow() }
    }

    func delete(_ record: LedgerRecord) {
        records.removeAll { $0.id == record.id && $0.bookUid == record.bookUid }
        outbox.removeAll { $0.entityUid == record.id }
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
        save()
        Task { await syncNow() }
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
                books = remoteBooks
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

    private func savePreferences() {
        defaults.set(customMembers, forKey: membersKey)
        defaults.set(customCategories, forKey: categoriesKey)
        defaults.set(customAccounts, forKey: accountsKey)
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
            lastSyncAt: lastSyncAt
        )
        persistence.save(state)
    }
}
