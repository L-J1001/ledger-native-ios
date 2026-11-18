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
        monthRecords.filter { $0.direction == .income }.reduce(0) { $0 + $1.amountCents }
    }

    var monthExpenseCents: Int {
        monthRecords.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amountCents }
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
