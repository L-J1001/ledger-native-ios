import Foundation

struct SyncFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class SyncService {
    static let shared = SyncService()
    static let defaultEndpoint = "https://ledger-sync-9eb2fc.pages.dev"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func login(endpoint: String, username: String, password: String,
               deviceID: String) async throws -> LoginResponse {
        let body: [String: Any] = [
            "username": username,
            "password": password,
            "device_id": deviceID,
            "device_name": "iPhone · 原生记账本",
        ]
        return try await request(
            base: endpoint,
            path: "/v1/login",
            method: "POST",
            token: nil,
            body: try JSONSerialization.data(withJSONObject: body)
        )
    }

    func books(endpoint: String, token: String) async throws -> [LedgerBook] {
        let response: BooksResponse = try await request(
            base: endpoint, path: "/v1/books", method: "GET", token: token, body: nil
        )
        return (response.books ?? []) + (response.orphanBooks ?? [])
    }

    func push(endpoint: String, token: String, ops: [OutboxOp]) async throws -> PushResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(ops)
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SyncFailure(message: "本地待同步数据格式异常")
        }
        let body: [String: Any] = ["ops": list]
        return try await request(
            base: endpoint,
            path: "/v1/push",
            method: "POST",
            token: token,
            body: try JSONSerialization.data(withJSONObject: body)
        )
    }

    func pull(endpoint: String, token: String, since: Int64) async throws -> PullResponse {
        return try await request(
            base: endpoint,
            path: "/v1/pull?since=\(since)&limit=500",
            method: "GET",
            token: token,
            body: nil
        )
    }

    func whoami(endpoint: String, token: String) async throws -> String {
        struct Who: Codable { var ownerId: String; enum CodingKeys: String, CodingKey { case ownerId = "owner_id" } }
        let who: Who = try await request(
            base: endpoint, path: "/v1/whoami", method: "GET", token: token, body: nil
        )
        return who.ownerId
    }

    private func request<T: Decodable>(base: String, path: String, method: String,
                                       token: String?, body: Data?) async throws -> T {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: trimmed + path) else {
            throw SyncFailure(message: "服务地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("LedgerNative/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SyncFailure(message: "网络返回异常")
        }
        if !(200..<300).contains(http.statusCode) {
            let errorCode: String? = {
                guard let object = try? JSONSerialization.jsonObject(with: data),
                      let dict = object as? [String: Any] else { return nil }
                return dict["error"] as? String
            }()
            let message: String
            switch http.statusCode {
            case 401:
                message = errorCode == "session_replaced"
                    ? "该账号设备数已达上限，这台 iPhone 被挤下线，请重新登录"
                    : "登录已失效，请重新登录"
            case 403:
                message = "账号无权执行此操作"
            case 429:
                message = "操作太频繁，请稍后再试"
            default:
                let suffix = errorCode.map { "：\($0)" } ?? ""
                message = "云端请求失败（\(http.statusCode)）\(suffix)"
            }
            throw SyncFailure(message: message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SyncFailure(message: "云端返回数据无法解析")
        }
    }
}
