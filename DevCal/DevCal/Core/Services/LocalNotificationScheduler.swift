//
//  LocalNotificationScheduler.swift
//  DevCal
//
//  Local notification scheduling for the 3 categories shown in
//  NotificationSettingsView. FCM server push is deferred to v1.1 — see
//  project memory project_devcal_v1_1_fcm.md.
//
//  Identifier scheme:
//    devcal.reminder.daily       - daily 21:00 nudge to come log
//    devcal.breakeven.{uuid}     - instant fire when a project hits break-even
//    devcal.subscription.{uuid}  - 09:00 the day before a recurring item bills
//
//  Gating order (cheap → expensive):
//    1. master toggle (UserDefaults notificationsEnabled, default on)
//    2. per-category toggle (default on)
//    3. system permission status (authorized / provisional / ephemeral)
//

import Foundation
import UserNotifications

@MainActor
enum LocalNotificationScheduler {

    enum ID {
        static let dailyReminder = "devcal.reminder.daily"
        static let breakevenPrefix = "devcal.breakeven."
        static let subscriptionPrefix = "devcal.subscription."
    }

    enum Toggle {
        static let master = "notificationsEnabled"
        static let breakeven = "notif.breakeven"
        static let subscription = "notif.subscription"
        static let dailyReminder = "notif.dailyReminder"
    }

    private static let dailyReminderHour = 21
    private static let subscriptionAlertHour = 9

    // MARK: - Gates

    static func isMasterAuthorized() async -> Bool {
        let master = UserDefaults.standard.object(forKey: Toggle.master) as? Bool ?? true
        guard master else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Requests system notification permission on launch when the master toggle
    /// is on (now the default) and the user hasn't answered yet. No-ops once
    /// they've decided, so it's safe to call on every launch. Without this the
    /// "notifications default on" toggle would schedule nothing silently because
    /// iOS still needs an explicit permission grant.
    @MainActor
    static func requestAuthorizationIfNeededOnLaunch() async {
        let master = UserDefaults.standard.object(forKey: Toggle.master) as? Bool ?? true
        guard master else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func isCategoryEnabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    // MARK: - Break-even (instant)

    static func postBreakeven(projectId: UUID, projectName: String) async {
        guard await isMasterAuthorized(), isCategoryEnabled(Toggle.breakeven) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "達成回本")
        content.body = String(localized: "\(projectName) 已經回本，恭喜！")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: ID.breakevenPrefix + projectId.uuidString,
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Subscription billing (day-before alert)

    /// Cancels existing subscription notifications and re-schedules a single
    /// 09:00 alert per active recurring CategoryItem, one day before
    /// `nextDueDate`. CategoryItem edits within a session only re-apply on
    /// the next launch / scenePhase active — acceptable for v1.0.0.
    static func rescheduleSubscriptionAlerts(items: [CategoryItem]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let stale = pending
            .map { $0.identifier }
            .filter { $0.hasPrefix(ID.subscriptionPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard await isMasterAuthorized(), isCategoryEnabled(Toggle.subscription) else { return }

        let calendar = Calendar.current
        for item in items where item.isActive {
            guard item.billingType.isRecurring,
                  let due = item.nextDueDate,
                  let dayBefore = calendar.date(byAdding: .day, value: -1, to: due)
            else { continue }

            var fire = calendar.dateComponents([.year, .month, .day], from: dayBefore)
            fire.hour = subscriptionAlertHour
            fire.minute = 0
            guard let fireDate = calendar.date(from: fire), fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "明日扣款提醒")
            content.body = String(localized: "\(item.name) 明天會自動扣款。")
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: fire, repeats: false)
            let request = UNNotificationRequest(
                identifier: ID.subscriptionPrefix + item.id.uuidString,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    // MARK: - Daily reminder

    /// Re-schedule the repeating daily 21:00 nudge. Idempotent — removes the
    /// existing one before re-adding. Toggled off → just cancels.
    static func rescheduleDailyReminder() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [ID.dailyReminder])

        guard await isMasterAuthorized(), isCategoryEnabled(Toggle.dailyReminder) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "記下今天的進度")
        content.body = String(localized: "花一分鐘把今天的支出與收入記下來。")
        content.sound = .default

        var components = DateComponents()
        components.hour = dailyReminderHour
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: ID.dailyReminder,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    // MARK: - Master cancel + rebuild

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Convenience: bring all repeating notifications into line with the
    /// current toggle + system state. Used on launch + scenePhase active +
    /// after a master toggle flip.
    static func rescheduleAll(items: [CategoryItem]) async {
        await rescheduleDailyReminder()
        await rescheduleSubscriptionAlerts(items: items)
    }
}
