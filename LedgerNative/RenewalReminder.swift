import Foundation
import UserNotifications

/// 自签名 IPA 7 天到期提醒。
///
/// Sideloadly 负责实际续签；App 只负责在到期前第 5/6/7 天各发一条本地通知，
/// 提醒打开电脑上的 Sideloadly。每次覆盖安装后的首次启动会以当前版本为锚点
/// 重新排期，避免同一条提醒在多次升级后反复堆积。
enum RenewalReminder {
    private static let identifiers = ["ledger.renew.5", "ledger.renew.6", "ledger.renew.7"]

    static func configure() {
        let defaults = UserDefaults.standard
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let versionKey = "renewal_anchor_version"
        let anchorKey = "renewal_anchor_date"

        if defaults.string(forKey: versionKey) != version
            || defaults.object(forKey: anchorKey) == nil {
            defaults.set(version, forKey: versionKey)
            defaults.set(Date(), forKey: anchorKey)
        }
        let anchor = defaults.object(forKey: anchorKey) as? Date ?? Date()

        let center = UNUserNotificationCenter.current()
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }

            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)

            let calendar = Calendar.current
            for (index, offset) in [5, 6, 7].enumerated() {
                guard let day = calendar.date(byAdding: .day, value: offset, to: anchor) else { continue }
                let daysLeft = 7 - offset
                let body: String
                switch daysLeft {
                case 2:
                    body = "记账本签名还剩 2 天。请打开电脑上的 Sideloadly，用数据线连接 iPhone 完成自动续签。"
                case 1:
                    body = "记账本签名只剩 1 天。今晚记得打开 Sideloadly 连接 iPhone 续签，避免明天打不开。"
                default:
                    body = "记账本签名今天到期。请尽快用 Sideloadly 连接 iPhone 续签，否则 App 将无法打开。"
                }

                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = 10
                components.minute = 0
                guard let fireDate = calendar.date(from: components), fireDate > Date() else { continue }

                let content = UNMutableNotificationContent()
                content.title = daysLeft == 0 ? "签名今天到期" : "该续签记账本了"
                content.body = body
                content.sound = .default
                content.userInfo = ["daysLeft": daysLeft]

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: identifiers[index], content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
    }
}
