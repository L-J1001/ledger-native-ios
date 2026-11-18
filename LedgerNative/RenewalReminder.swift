import Foundation
import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
final class RenewalReminder: ObservableObject {
    @Published var showAlert = false
    @Published var daysRemaining = 7
    @Published var expiryDate = Date().addingTimeInterval(7 * 86_400)

    private let startKey = "ledger.renewal.installDate"
    private let versionKey = "ledger.renewal.appVersion"
    private let alertDayKey = "ledger.renewal.lastAlertDay"

    func bootstrap() {
        let defaults = UserDefaults.standard
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let storedVersion = defaults.string(forKey: versionKey) ?? ""
        if defaults.double(forKey: startKey) <= 0 || storedVersion != version {
            defaults.set(Date().timeIntervalSince1970, forKey: startKey)
            defaults.set(version, forKey: versionKey)
        }
        refresh()
        requestAuthorization()
        scheduleNotifications()
        maybePresentLaunchAlert()
    }

    func refresh() {
        let defaults = UserDefaults.standard
        let start = defaults.double(forKey: startKey) > 0
            ? Date(timeIntervalSince1970: defaults.double(forKey: startKey))
            : Date()
        expiryDate = start.addingTimeInterval(7 * 86_400)
        let seconds = expiryDate.timeIntervalSinceNow
        daysRemaining = max(0, Int(ceil(seconds / 86_400)))
    }

    func markRenewed() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: startKey)
        refresh()
        scheduleNotifications()
        showAlert = false
    }

    private func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["renewal-5", "renewal-6", "renewal-7"])

        let calendar = Calendar.current
        let start = UserDefaults.standard.double(forKey: startKey) > 0
            ? Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: startKey))
            : Date()

        for day in 5...7 {
            guard let dayDate = calendar.date(byAdding: .day, value: day, to: start) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: dayDate)
            components.hour = 9
            components.minute = 0
            guard let fireDate = calendar.date(from: components) else { continue }
            let interval = max(5, fireDate.timeIntervalSinceNow)

            let content = UNMutableNotificationContent()
            content.title = "记账本需要续签"
            content.body = day == 7
                ? "免费签名今天到期，App 可能马上打不开。请打开电脑上的 Sideloadly 完成续签。"
                : "免费签名还有 \(7 - day) 天到期。请在电脑上打开 Sideloadly，手机和电脑保持同一 Wi‑Fi。"
            content.sound = .default
            content.badge = 1

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: "renewal-\(day)", content: content, trigger: trigger)
            center.add(request, withCompletionHandler: nil)
        }
    }

    private func maybePresentLaunchAlert() {
        guard daysRemaining <= 1 else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let defaults = UserDefaults.standard
        if defaults.string(forKey: alertDayKey) != today {
            defaults.set(today, forKey: alertDayKey)
            showAlert = true
        }
    }
}
