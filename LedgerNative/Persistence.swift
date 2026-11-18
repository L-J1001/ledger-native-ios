import Foundation

struct PersistedState: Codable {
    var books: [LedgerBook]
    var records: [LedgerRecord]
    var outbox: [OutboxOp]
    var cursor: Int64
    var selectedBookID: String?
    var auth: AuthState?
    var deviceID: String
    var lastSyncAt: Date?
    /// 旧版本状态文件没有这个字段；用可选值保证升级后仍能读。
    var taxonomies: [String: BookTaxonomy]?
    var budgets: [String: Int]?
    var trash: [LedgerRecord]?
}

final class Persistence {
    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("LedgerNative", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("state.json")
    }

    func load() -> PersistedState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return nil
        }
    }

    func save(_ state: PersistedState) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            let tmp = fileURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try? FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: tmp, to: fileURL)
        } catch {
            // Local persistence is best-effort; the app keeps running with in-memory state.
        }
    }
}
