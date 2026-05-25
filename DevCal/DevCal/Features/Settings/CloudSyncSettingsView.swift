//
//  CloudSyncSettingsView.swift
//  DevCal
//
//  Cloud sync preferences subpage. Per the product plan, cloud sync is a
//  Free-tier feature backed by Firebase. Firebase isn't integrated yet, so
//  this page wires the user-facing toggles and copy now; the actual sync
//  trigger / status fields will be hooked up alongside the SDK rollout.
//

import SwiftUI
import PhosphorSymbols

struct CloudSyncSettingsView: View {
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled: Bool = true
    @AppStorage("cloudSyncWifiOnly") private var cloudSyncWifiOnly: Bool = false
    @AppStorage("cloudSyncLastAt") private var cloudSyncLastAt: Double = 0

    @State private var isSyncing: Bool = false

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
                    .foregroundStyle(Theme.brand)
                Text("立即同步")
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(Theme.brand)
                Spacer(minLength: 8)
                if isSyncing {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSyncing)
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

    private var lastSyncedText: String {
        guard cloudSyncLastAt > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: cloudSyncLastAt)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Actions

    private func triggerSync() {
        // TODO(firebase): kick off a real Firestore sync once the SDK lands.
        isSyncing = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                cloudSyncLastAt = Date().timeIntervalSince1970
                isSyncing = false
            }
        }
    }
}

#Preview {
    NavigationStack { CloudSyncSettingsView() }
}
