//
//  NotificationSettingsView.swift
//  DevCal
//
//  Notification preferences subpage. The master toggle controls whether we
//  schedule any local notifications at all; the per-category toggles let the
//  user trim what they get. System-level permission (the OS prompt) is owned
//  by Settings.app and surfaced via the "前往系統設定" link at the bottom.
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import PhosphorSymbols

struct NotificationSettingsView: View {
    @AppStorage(LocalNotificationScheduler.Toggle.master) private var notificationsEnabled: Bool = true
    @AppStorage(LocalNotificationScheduler.Toggle.breakeven) private var notifBreakeven: Bool = true
    @AppStorage(LocalNotificationScheduler.Toggle.subscription) private var notifSubscription: Bool = true
    @AppStorage(LocalNotificationScheduler.Toggle.dailyReminder) private var notifDailyReminder: Bool = true

    @Environment(\.modelContext) private var modelContext

    @State private var systemAuthorized: Bool = true
    @State private var showPermissionAlert: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                masterRow

                if notificationsEnabled {
                    sectionDivider
                    sectionHeader("提醒類型")
                    categoryRow(
                        icon: "trophy",
                        label: "達成回本提醒",
                        sublabel: "專案首次達成回本時通知",
                        isOn: $notifBreakeven
                    )
                    hairline
                    categoryRow(
                        icon: "calendar-dot",
                        label: "訂閱扣款提醒",
                        sublabel: "共用訂閱即將扣款時通知",
                        isOn: $notifSubscription
                    )
                    hairline
                    categoryRow(
                        icon: "chart-line",
                        label: "每日記錄提醒",
                        sublabel: "每天晚上 21:00 提醒你記下今天的支出與收入",
                        isOn: $notifDailyReminder
                    )
                }

                sectionDivider
                systemSettingsRow
                footer
            }
        }
        .background(Theme.appBackground.ignoresSafeArea())
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshSystemAuthorization() }
        .onChange(of: notificationsEnabled) { _, newValue in
            if newValue {
                Task {
                    await requestAuthorizationIfNeeded()
                    await rescheduleAll()
                }
            } else {
                LocalNotificationScheduler.cancelAll()
            }
        }
        .onChange(of: notifBreakeven) { _, _ in
            // Break-even is fired instantly on stamp — nothing to (de)schedule
            // up-front. The post call already gates on this toggle.
        }
        .onChange(of: notifSubscription) { _, _ in
            Task { await rescheduleSubscriptionAlerts() }
        }
        .onChange(of: notifDailyReminder) { _, _ in
            Task { await LocalNotificationScheduler.rescheduleDailyReminder() }
        }
        .systemAlert(
            "請在系統設定中開啟通知",
            isPresented: $showPermissionAlert
        ) {
            Button("取消", role: .cancel) { notificationsEnabled = false }
            Button("前往設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("SideProfit 沒有通知權限,提醒將無法送出。")
        }
    }

    // MARK: - Rows

    private var masterRow: some View {
        HStack(spacing: 12) {
            Image(ph: "bell", weight: .regular)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.primaryText)
            Text("啟用通知")
                .appFont(.body, weight: .medium)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            Toggle("", isOn: $notificationsEnabled.animation())
                .labelsHidden()
                .tint(Theme.brand)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func categoryRow(
        icon: String,
        label: LocalizedStringKey,
        sublabel: LocalizedStringKey,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(ph: icon, weight: .regular)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.primaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(Theme.primaryText)
                Text(sublabel)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.brand)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var systemSettingsRow: some View {
        Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
            HStack(spacing: 12) {
                Image(ph: "gear", weight: .regular)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Theme.primaryText)
                Text("系統通知權限")
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                Text(systemAuthorized ? "已開啟" : "未開啟")
                    .appFont(.subheadline)
                    .foregroundStyle(Theme.primaryText.opacity(0.5))
                Image(systemName: "arrow.up.right")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(Theme.primaryText.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pieces

    private func sectionHeader(_ text: LocalizedStringKey) -> some View {
        HStack {
            Text(text)
                .formSectionHeaderStyle()
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 54)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }

    private var footer: some View {
        Text("通知會在裝置本地排程,不需網路。若系統權限被關閉,即使這裡開啟也無法送出提醒。")
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
    }

    // MARK: - Authorization

    @MainActor
    private func refreshSystemAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        systemAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
    }

    @MainActor
    private func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            systemAuthorized = granted
            if !granted { notificationsEnabled = false }
        case .denied:
            systemAuthorized = false
            showPermissionAlert = true
        default:
            systemAuthorized = true
        }
    }

    @MainActor
    private func rescheduleAll() async {
        let items = (try? modelContext.fetch(FetchDescriptor<CategoryItem>())) ?? []
        await LocalNotificationScheduler.rescheduleAll(items: items)
    }

    @MainActor
    private func rescheduleSubscriptionAlerts() async {
        let items = (try? modelContext.fetch(FetchDescriptor<CategoryItem>())) ?? []
        await LocalNotificationScheduler.rescheduleSubscriptionAlerts(items: items)
    }
}

#Preview {
    NavigationStack { NotificationSettingsView() }
}
