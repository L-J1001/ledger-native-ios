import Foundation

/// 读取包内 `embedded.mobileprovision` 的真实签名到期日。
/// 免费 Apple ID 的 7 天有效期以描述文件为准，不能用“首次启动日期”推算。
enum SignatureInfo {
    static var expiration: Date? {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = FileManager.default.contents(atPath: path) else { return nil }

        // 描述文件外层是 CMS 签名，不能整段按 UTF-8 解码；
        // 先定位 plist 的 key，再只解码它后面一小段。
        let marker = Data("<key>ExpirationDate</key>".utf8)
        guard let range = data.range(of: marker) else { return nil }
        let tailEnd = min(data.count, range.upperBound + 240)
        let tailData = data.subdata(in: range.upperBound..<tailEnd)
        guard let tail = String(data: tailData, encoding: .utf8),
              let start = tail.range(of: "<date>"),
              let end = tail.range(of: "</date>") else { return nil }

        let raw = String(tail[start.upperBound..<end.lowerBound])
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw)
    }

    static var isExpired: Bool {
        guard let expiration else { return false }
        return expiration < Date()
    }

    /// 和 Sideloadly 维护工具一样显示到“天 + 小时”，避免只取整天数造成 6 天多/7 天的误读。
    static var remainingText: String {
        guard let expiration else { return "读取不到描述文件有效期" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let expiry = formatter.string(from: expiration)

        if expiration <= Date() { return "已过期 · \(expiry)" }

        let seconds = expiration.timeIntervalSinceNow
        let days = Int(seconds / 86400)
        if days > 0 {
            let hours = Int((seconds - Double(days) * 86400) / 3600)
            return hours > 0
                ? "剩余 \(days) 天 \(hours) 小时 · \(expiry) 到期"
                : "剩余 \(days) 天 · \(expiry) 到期"
        }

        let hours = Int(seconds / 3600)
        let minutes = max(1, Int((seconds - Double(hours) * 3600) / 60))
        return hours > 0
            ? "剩余 \(hours) 小时 \(minutes) 分 · \(expiry) 到期"
            : "剩余 \(minutes) 分钟 · \(expiry) 到期"
    }
}
