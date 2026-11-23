import Foundation
import UIKit
import UserNotifications

/// 自签名 IPA 的到期提醒。
///
/// 时间基准必须是包内描述文件的真实到期日，而不是“首次启动日期”。
/// Sideloadly 每次重签后描述文件会换新，App 下次启动时按新的到期日重排，
/// 这样设置页、维护工具和通知文案不会各说各的天数。
enum RenewalReminder {
    private static let identifiers = ["ledger.renew.2d", "ledger.renew.1d", "ledger.renew.final"]
    private static let versionKey = "renewal_anchor_version"
    private static let anchorKey = "renewal_anchor_date"

    static func markRead() {
        let center = UNUserNotificationCenter.current()
        // 旧版本的通知标识不一定和新版一致；打开 App 时清空本应用所有已送达通知，
        // 既清红点，也把历史遗留的“还剩 2 天”提醒从通知中心移走。
        center.removeAllDeliveredNotifications()
        center.setBadgeCount(0, withCompletionHandler: nil)
        // 老系统/异常状态下 setBadgeCount 可能不刷新桌面图标，补一次旧 API。
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    static func configure() {
        let defaults = UserDefaults.standard
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let anchorVersion = "\(version)#\(build)"

        if defaults.string(forKey: versionKey) != anchorVersion
            || defaults.object(forKey: anchorKey) == nil {
            defaults.set(anchorVersion, forKey: versionKey)
            defaults.set(Date(), forKey: anchorKey)
        }

        // 有描述文件时用真实到期日；没有时退回“首次启动 + 7 天”的旧逻辑，
        // 只作为读不到描述文件时的兜底。
        let installAnchor = defaults.object(forKey: anchorKey) as? Date ?? Date()
        let expiry = SignatureInfo.expiration
            ?? installAnchor.addingTimeInterval(7 * 86400)

        let center = UNUserNotificationCenter.current()
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }

            // 旧版本可能排过“首次启动 + 5/6/7 天”的提醒；重排前先清空本应用
            // 所有待发通知，避免旧的三条和新到期日同时触发。
            center.removeAllPendingNotificationRequests()

            let calendar = Calendar.current
            let reminders: [(offset: TimeInterval, daysLeft: Int, title: String, body: String)] = [
                (
                    -2 * 86400,
                    2,
                    "该续签记账本了",
                    "记账本签名还剩约 2 天。请打开电脑上的 Sideloadly，用数据线连接 iPhone 完成自动续签。"
                ),
                (
                    -1 * 86400,
                    1,
                    "该续签记账本了",
                    "记账本签名只剩约 1 天。今晚记得打开 Sideloadly 连接 iPhone 续签，避免明天打不开。"
                ),
                (
                    -2 * 3600,
                    0,
                    "签名即将到期",
                    "记账本签名将在 2 小时内到期。请尽快用 Sideloadly 连接 iPhone 续签，否则 App 将无法打开。"
                ),
            ]

            for reminder in reminders {
                var fireDate = expiry.addingTimeInterval(reminder.offset)

                // 前两天/前一天的通知仍放在上午 10 点，避免半夜打扰；
                // 最后一条按真实到期时间倒推 2 小时，不再固定到上午 10 点。
                if reminder.daysLeft > 0 {
                    fireDate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: fireDate) ?? fireDate
                } else {
                    fireDate = max(fireDate, Date().addingTimeInterval(60))
                }

                guard fireDate > Date(), fireDate < expiry else { continue }

                let components = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                )

                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default
                content.badge = 1
                content.userInfo = [
                    "daysLeft": reminder.daysLeft,
                    "expiration": ISO8601DateFormatter().string(from: expiry),
                ]

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: identifiers[reminder.daysLeft == 2 ? 0 : reminder.daysLeft == 1 ? 1 : 2],
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            }
        }
    }
}
