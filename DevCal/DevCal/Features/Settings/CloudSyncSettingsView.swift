//
//  CloudSyncSettingsView.swift
//  DevCal
//
//  Cloud sync preferences subpage. Per the product plan, cloud sync is a
//  Free-tier feature backed by Firebase. The "立即同步" row drives the real
//  FirestoreSyncService.syncNow() — the auto-sync toggle is still a local
//  preference that Phase 4 doesn't read yet (Step 5 + Step 6 enforce it).
//

import SwiftUI
import PhosphorSymbols

struct CloudSyncSettingsView: View {
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled: Bool = true
    @AppStorage("cloudSyncWifiOnly") private var cloudSyncWifiOnly: Bool = false

    @Environment(\.syncService) private var syncService

    @State private var isSyncing: Bool = false
    @State private var lastErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                toggleRow(
                    icon: "arrows-clockwise",
                    label: "自動同步",
                    isOn: $cloudSyncEnabled.animation()
                )

                if cloudSyncEnabled {
                    hairline
                    toggleRow(
                        icon: "wifi-high",
                        label: "僅在 Wi-Fi 同步",
                        isOn: $cloudSyncWifiOnly
                    )
                    hairline
                    lastSyncRow
                    hairline
                    syncNowRow
                    if let lastErrorMessage {
                        hairline
                        errorRow(lastErrorMessage)
                    }
                }

                footer
            }
        }
        .background(Theme.appBackground.ignoresSafeArea())
        .navigationTitle("雲端同步")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Rows

    private func toggleRow(icon: String, label: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(ph: icon, weight: .regular)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.primaryText)
            Text(label)
                .appFont(.body, weight: .medium)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.brand)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var lastSyncRow: some View {
        HStack(spacing: 12) {
            Image(ph: "clock-counter-clockwise", weight: .regular)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.primaryText)
            Text("上次同步")
                .appFont(.body, weight: .medium)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            Text(lastSyncedText)
                .appFont(.subheadline)
                .foregroundStyle(Theme.primaryText.opacity(0.5))
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var syncNowRow: some View {
        Button {
            triggerSync()
        } label: {
            HStack(spacing: 12) {
                Image(ph: "cloud-arrow-up", weight: .regular)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(syncDisabled ? Theme.primaryText.opacity(0.35) : Theme.brand)
                Text("立即同步")
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(syncDisabled ? Theme.primaryText.opacity(0.35) : Theme.brand)
                Spacer(minLength: 8)
                if isSyncing {
                    ProgressView().controlSize(.small)
                } else if syncDisabled {
                    Text("請先登入")
                        .appFont(.subheadline)
                        .foregroundStyle(Theme.primaryText.opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSyncing || syncDisabled)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(ph: "warning", weight: .regular)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.expense)
            VStack(alignment: .leading, spacing: 2) {
                Text("同步失敗")
                    .appFont(.subheadline, weight: .medium)
                    .foregroundStyle(Theme.expense)
                Text(message)
                    .appFont(.caption)
                    .foregroundStyle(Theme.primaryText.opacity(0.6))
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Pieces

    private var footer: some View {
        Text("開啟後,專案、收支與時間紀錄會自動同步到你的帳號,在任何裝置登入都能取得最新資料。同步在背景進行,不會中斷你正在編輯的內容。")
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 54)
    }

    private var syncDisabled: Bool {
        guard let syncService else { return true }
        return syncService.status == .disabled
    }

    private var lastSyncedText: String {
        guard let date = syncService?.lastSyncedAt else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Actions

    private func triggerSync() {
        guard let syncService else { return }
        isSyncing = true
        lastErrorMessage = nil
        Task {
            do {
                try await syncService.syncNow()
                if case .failed(let message) = syncService.status {
                    lastErrorMessage = message
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
            isSyncing = false
        }
    }
}

#Preview {
    NavigationStack { CloudSyncSettingsView() }
}
