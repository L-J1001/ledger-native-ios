import Foundation

enum Direction: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }
    var title: String { self == .expense ? "支出" : "收入" }
    var sign: String { self == .expense ? "-" : "+" }
}

struct LedgerBook: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var openingCents: Int
    var colorHex: String
    var updatedAt: Int64
    /// 桌面端随账本元数据一起推上来的成员/分类/账户；旧版云端没有这个字段。
    var taxonomy: BookTaxonomy?

    enum CodingKeys: String, CodingKey {
        case id = "book_uid"
        case name
        case openingCents = "opening_cents"
        case colorHex = "color"
        case updatedAt = "updated_at"
        case taxonomy
    }

    init(id: String, name: String, openingCents: Int = 0,
         colorHex: String = "#3F7CFF", updatedAt: Int64 = 0,
         taxonomy: BookTaxonomy? = nil) {
        self.id = id
        self.name = name
        self.openingCents = openingCents
        self.colorHex = colorHex
        self.updatedAt = updatedAt
        self.taxonomy = taxonomy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "我的账本"
        openingCents = try c.decodeIfPresent(Int.self, forKey: .openingCents) ?? 0
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#3F7CFF"
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
        taxonomy = try c.decodeIfPresent(BookTaxonomy.self, forKey: .taxonomy)
    }
}

struct RemotePayload: Codable {
    var schema: Int?
    var origin: String?
    var amount: Double?
    var amountCents: Int?
    var direction: String?
    var member: String?
    var date: String?
    var note: String?
    var category: String?
    var account: String?
    var groupNote: String?
    var splitGroup: String?
    var excludeTotal: Int?
    var localId: Int?
    // 账本元数据（entity == "book"）专用；记录 payload 里为空。
    var name: String? = nil
    var openingCents: Int? = nil
    var color: String? = nil
    var taxonomy: BookTaxonomy? = nil

    enum CodingKeys: String, CodingKey {
        case schema, origin, amount, direction, member, date, note, category, account, name, color, taxonomy
        case amountCents = "amount_cents"
        case groupNote = "group_note"
        case splitGroup = "split_group"
        case excludeTotal = "exclude_total"
        case localId = "local_id"
        case openingCents = "opening_cents"
    }

    static func book(name: String, openingCents: Int, color: String,
                     taxonomy: BookTaxonomy? = nil) -> RemotePayload {
        RemotePayload(schema: nil, origin: "ios", amount: nil, amountCents: nil,
                      direction: nil, member: nil, date: nil, note: nil,
                      category: nil, account: nil, groupNote: nil, splitGroup: nil,
                      excludeTotal: nil, localId: nil, name: name,
                      openingCents: max(0, openingCents), color: color,
                      taxonomy: taxonomy)
    }
}

struct LedgerRecord: Codable, Identifiable, Hashable {
    var id: String
    var bookUid: String
    var date: String
    var direction: Direction
    var amountCents: Int
    var category: String
    var note: String
    var member: String
    var account: String
    var groupNote: String
    var splitGroup: String?
    var excludeTotal: Bool
    var updatedAt: Int64
    var pending: Bool

    enum CodingKeys: String, CodingKey {
        case id = "record_uid"
        case bookUid = "book_uid"
        case date, direction, category, note, member, account, pending
        case amountCents = "amount_cents"
        case groupNote = "group_note"
        case splitGroup = "split_group"
        case excludeTotal = "exclude_total"
        case updatedAt = "updated_at"
    }

    init(id: String, bookUid: String, date: String, direction: Direction,
         amountCents: Int, category: String, note: String, member: String,
         account: String, groupNote: String = "", splitGroup: String? = nil,
         excludeTotal: Bool = false, updatedAt: Int64 = nowMillis(),
         pending: Bool = false) {
        self.id = id
        self.bookUid = bookUid
        self.date = date
        self.direction = direction
        self.amountCents = amountCents
        self.category = category
        self.note = note
        self.member = member
        self.account = account
        self.groupNote = groupNote
        self.splitGroup = splitGroup
        self.excludeTotal = excludeTotal
        self.updatedAt = updatedAt
        self.pending = pending
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        bookUid = try c.decodeIfPresent(String.self, forKey: .bookUid) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? todayString()
        direction = Direction(rawValue: try c.decodeIfPresent(String.self, forKey: .direction) ?? "expense") ?? .expense
        amountCents = try c.decodeIfPresent(Int.self, forKey: .amountCents) ?? 0
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "未分类"
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        member = try c.decodeIfPresent(String.self, forKey: .member) ?? ""
        account = try c.decodeIfPresent(String.self, forKey: .account) ?? ""
        groupNote = try c.decodeIfPresent(String.self, forKey: .groupNote) ?? ""
        splitGroup = try c.decodeIfPresent(String.self, forKey: .splitGroup)
        excludeTotal = try c.decodeIfPresent(Bool.self, forKey: .excludeTotal) ?? false
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
        pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
    }

    static func from(payload: RemotePayload, bookUid: String, recordUid: String,
                      updatedAt: Int64, splitGroup: String?) -> LedgerRecord {
        let cents = payload.amountCents ?? Int(round((payload.amount ?? 0) * 100))
        return LedgerRecord(
            id: recordUid,
            bookUid: bookUid,
            date: payload.date ?? todayString(),
            direction: Direction(rawValue: payload.direction ?? "expense") ?? .expense,
            amountCents: max(0, cents),
            category: payload.category?.isEmpty == false ? payload.category! : "未分类",
            note: payload.note ?? "",
            member: payload.member?.isEmpty == false ? payload.member! : "",
            account: payload.account ?? "",
            groupNote: payload.groupNote ?? "",
            splitGroup: splitGroup ?? payload.splitGroup,
            excludeTotal: (payload.excludeTotal ?? 0) != 0,
            updatedAt: updatedAt,
            pending: false
        )
    }

    var payload: RemotePayload {
        RemotePayload(
            schema: 1,
            origin: "ios",
            amount: Double(amountCents) / 100.0,
            amountCents: amountCents,
            direction: direction.rawValue,
            member: member,
            date: date,
            note: note,
            category: category,
            account: account,
            groupNote: groupNote,
            splitGroup: splitGroup,
            excludeTotal: excludeTotal ? 1 : 0,
            localId: nil
        )
    }

    var amountYuan: Double { Double(amountCents) / 100.0 }
    var dateValue: Date { parseDate(date) ?? Date() }
    var monthKey: String { String(date.prefix(7)) }
}

struct OutboxOp: Codable, Identifiable {
    var id: String
    var bookUid: String
    var entity: String
    var entityUid: String
    var op: String
    var payload: RemotePayload?
    var updatedAt: Int64
    var deviceId: String
    var splitGroup: String?

    enum CodingKeys: String, CodingKey {
        case id = "op_id"
        case bookUid = "book_uid"
        case entity
        case entityUid = "entity_uid"
        case op
        case payload
        case updatedAt = "updated_at"
        case deviceId = "device_id"
        case splitGroup = "split_group"
    }
}

struct RemoteOp: Codable {
    var seq: Int64?
    var opId: String
    var bookUid: String
    var entity: String
    var entityUid: String
    var op: String
    var payload: RemotePayload?
    var updatedAt: Int64
    var deviceId: String
    var splitGroup: String?

    enum CodingKeys: String, CodingKey {
        case seq
        case opId = "op_id"
        case bookUid = "book_uid"
        case entity
        case entityUid = "entity_uid"
        case op
        case payload
        case updatedAt = "updated_at"
        case deviceId = "device_id"
        case splitGroup = "split_group"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decodeIfPresent(Int64.self, forKey: .seq)
        opId = try c.decodeIfPresent(String.self, forKey: .opId) ?? ""
        bookUid = try c.decodeIfPresent(String.self, forKey: .bookUid) ?? ""
        entity = try c.decodeIfPresent(String.self, forKey: .entity) ?? ""
        entityUid = try c.decodeIfPresent(String.self, forKey: .entityUid) ?? ""
        op = try c.decodeIfPresent(String.self, forKey: .op) ?? ""
        payload = try c.decodeIfPresent(RemotePayload.self, forKey: .payload)
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
        deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        splitGroup = try c.decodeIfPresent(String.self, forKey: .splitGroup)
    }
}

struct AuthState: Codable {
    var username: String
    var displayName: String
    var ownerId: String
    var bookUid: String
    var pairCode: String
    var endpoint: String
}

/// 每本账本自己的成员 / 分类 / 账户选项。只影响当前账本，切换账本不会串。
struct BookTaxonomy: Codable, Hashable {
    var members: [String] = []
    var expenseCategories: [String] = []
    var incomeCategories: [String] = []
    var accounts: [String] = []
}

enum TaxonomyKind: String, CaseIterable, Identifiable {
    case members
    case categories
    case accounts

    var id: String { rawValue }
    var title: String {
        switch self {
        case .members: return "成员"
        case .categories: return "分类"
        case .accounts: return "账户"
        }
    }
}

/// 明细列表 / 首页的一行：单笔记账是一行，同 split_group 的多条明细折叠成一笔。
struct RecordGroup: Identifiable, Hashable {
    let id: String
    let records: [LedgerRecord]

    var first: LedgerRecord { records[0] }
    var isSplit: Bool { records.count > 1 || records[0].splitGroup != nil }
    var direction: Direction { first.direction }
    var date: String { first.date }
    var amountCents: Int {
        records.filter { !$0.excludeTotal }.reduce(0) { $0 + $1.amountCents }
    }
    var title: String {
        if !isSplit { return first.category.isEmpty ? "未分类" : first.category }
        let note = first.groupNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        // 桌面端把同一次拆分折叠成「一笔」，主行显示记账人；
        // 手机端沿用同一口径，不再把每一行明细铺成独立流水。
        let member = first.member.trimmingCharacters(in: .whitespacesAndNewlines)
        return member.isEmpty ? "拆分 \(records.count) 笔" : "\(member) · \(records.count) 笔"
    }
    var subtitle: String {
        let member = first.member.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSplit {
            let cats = records.map(\.category).filter { !$0.isEmpty }
            let joined = cats.prefix(3).joined(separator: " · ")
            var parts: [String] = []
            if !member.isEmpty { parts.append(member) }
            parts.append("拆分 \(records.count) 笔")
            if !joined.isEmpty { parts.append(joined) }
            if cats.count > 3 { parts.append("等 \(cats.count) 类") }
            return parts.joined(separator: " · ")
        }
        // 单笔同样显示记账人：桌面端明细里每笔都带人名，手机端不能只在拆分时才显示。
        var parts: [String] = []
        if !member.isEmpty { parts.append(member) }
        let note = first.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

struct LoginResponse: Codable {
    var ok: Bool
    var token: String
    var owner: String
    var bookUid: String
    var pairCode: String
    var endpoint: String
    var username: String
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case ok, token, owner, endpoint, username
        case bookUid = "book_uid"
        case pairCode = "pair_code"
        case displayName = "display_name"
    }
}

struct BooksResponse: Codable {
    var books: [LedgerBook]?
    var orphanBooks: [LedgerBook]?

    enum CodingKeys: String, CodingKey {
        case books
        case orphanBooks = "orphan_books"
    }
}

struct PushResponse: Codable {
    var accepted: Int
    var duplicates: Int?
    var cursor: Int64?
}

struct PullResponse: Codable {
    var ops: [RemoteOp]
    var cursor: Int64
    var hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case ops, cursor
        case hasMore = "has_more"
    }
}

enum ULID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func generate() -> String {
        var time = UInt64(Date().timeIntervalSince1970 * 1000)
        var timePart = ""
        for _ in 0..<10 {
            timePart = String(alphabet[Int(time % 32)]) + timePart
            time /= 32
        }
        let randomPart = (0..<16).map { _ in String(alphabet[Int.random(in: 0..<32)]) }.joined()
        return timePart + randomPart
    }
}

func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}

func todayString() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

func parseDate(_ text: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: text)
}

func dateString(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}

func money(_ cents: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencySymbol = "¥"
    f.locale = Locale(identifier: "zh_CN")
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "¥0.00"
}

func shortDate(_ text: String) -> String {
    guard let d = parseDate(text) else { return text }
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "M月d日"
    return f.string(from: d)
}
