//
//  SettingsView.swift
//  DevCal
//
//  Editorial settings: page is the container, hairlines are the rhythm.
//  Email pill is the one intentional container — it answers "which account
//  am I on", which is the highest-value question on this screen.
//

import SwiftUI
import SwiftData
import UIKit
import StoreKit
import PhosphorSymbols

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(Entitlements.self) private var entitlements
    @Environment(ExchangeRateService.self) private var fx
    @Environment(\.modelContext) private var modelContext
    @Environment(\.projectRepository) private var projectRepository
    @Environment(\.transactionRepository) private var transactionRepository
    @Environment(\.timeLogRepository) private var timeLogRepository
    @Environment(\.categoryItemRepository) private var categoryItemRepository
    @AppStorage("needsOnboarding") private var needsOnboarding = false
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"
    @AppStorage("preferredAppearance") private var preferredAppearance: String = "system"
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled: Bool = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false

    @State private var showPaywall = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showManageSubscriptions = false
    @State private var authError: String? = nil
    @State private var showAuthErrorAlert = false
    @State private var isDeletingAccount = false

    private var currencyOptions: [String] { ExchangeRateService.supportedCodes }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let account = auth.account {
                    accountPill(account: account)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                }

                accountGroup
                groupDivider
                dataGroup
                groupDivider
                preferencesGroup
                groupDivider
                exchangeRateGroup
                groupDivider
                infoGroup

                #if DEBUG
                groupDivider
                developerGroup
                #endif

                groupDivider
                destructiveGroup

                Spacer(minLength: 48)
            }
        }
        .background(Theme.appBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .toolbarTitleDisplayMode(.inlineLarge)
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .systemAlert(
            "確定要登出 SideProfit？",
            isPresented: $showSignOutConfirm
        ) {
            Button("取消", role: .cancel) {}
            Button("登出", role: .destructive) { runSignOut() }
        }
        .systemAlert(
            "確定要刪除帳號？",
            isPresented: $showDeleteConfirm
        ) {
            Button("取消", role: .cancel) {}
            // Phase 1: deletes the Firebase Auth user + wipes local SwiftData
            // via the Phase 0 repositories (so tombstones queue for Phase 4).
            // Cloud Function cascade for Firestore lands in Phase 4.
            Button("刪除", role: .destructive) {
                Task { await runDeleteAccount() }
            }
        } message: {
            Text("登入帳號與本機資料都會永久移除，且無法復原。")
        }
        .systemAlert("發生錯誤", isPresented: $showAuthErrorAlert) {
            Button("OK", role: .cancel) { authError = nil }
        } message: {
            Text(authError ?? "")
        }
        .disabled(isDeletingAccount)
    }

    // MARK: - Auth actions

    private func runSignOut() {
        do {
            try auth.signOut()
        } catch {
            authError = error.localizedDescription
            showAuthErrorAlert = true
        }
    }

    private func runDeleteAccount() async {
        guard !isDeletingAccount else { return }
        guard let project = projectRepository,
              let transaction = transactionRepository,
              let timeLog = timeLogRepository,
              let categoryItem = categoryItemRepository else {
            authError = "Repositories missing — Phase 0 injection broken."
            showAuthErrorAlert = true
            return
        }
        let ctx = AuthService.AccountPurgeContext(
            modelContext: modelContext,
            project: project,
            transaction: transaction,
            timeLog: timeLog,
            categoryItem: categoryItem
        )
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await auth.deleteAccount(localPurge: ctx)
        } catch {
            authError = error.localizedDescription
            showAuthErrorAlert = true
        }
    }

    // MARK: - Account hero pill

    private func accountPill(account: AuthService.AccountSummary) -> some View {
        HStack(spacing: 0) {
            Text(account.email ?? account.displayName)
                .appFont(.body, weight: .semibold)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.primaryText.opacity(0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.primaryText.opacity(0.07), lineWidth: 1)
        }
    }

    // MARK: - Groups

    @ViewBuilder
    private var accountGroup: some View {
        VStack(spacing: 0) {
            if entitlements.isPro {
                SettingsRow(
                    icon: Image(ph: "seal-check", weight: .regular),
                    label: "Subscription",
                    value: entitlements.plan == .proYearly ? "Pro · Yearly" : "Pro · Monthly",
                    style: .chevron
                ) {
                    showManageSubscriptions = true
                }
            } else {
                SettingsRow(
                    icon: Image(ph: "sparkle", weight: .regular),
                    label: "Subscription",
                    value: "Free",
                    style: .chevron
                ) {
                    showPaywall = true
                }
            }
            SettingsRow(
                icon: Image(ph: "arrows-clockwise", weight: .regular),
                label: "Cloud sync",
                value: cloudSyncEnabled ? "On" : "Off",
                style: .chevron,
                destination: { CloudSyncSettingsView() }
            )
            SettingsRow(
                icon: Image(ph: "receipt", weight: .regular),
                label: "Restore purchases",
                style: .none
            ) {
                entitlements.restore()
            }
        }
    }

    @ViewBuilder
    private var dataGroup: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: Image(ph: "share-network", weight: .regular),
                label: "共用項目",
                style: .chevron,
                destination: { SharedExpensesView() }
            )
        }
    }

    @ViewBuilder
    private var preferencesGroup: some View {
        VStack(spacing: 0) {
            currencyRow
            appearanceRow
            SettingsRow(
                icon: Image(ph: "globe", weight: .regular),
                label: "Language",
                value: currentLanguageLabel,
                style: .external,
                url: URL(string: UIApplication.openSettingsURLString)
            )
            SettingsRow(
                icon: Image(ph: "bell", weight: .regular),
                label: "Notifications",
                value: notificationsEnabled ? "On" : "Off",
                style: .chevron,
                destination: { NotificationSettingsView() }
            )
        }
    }

    @ViewBuilder
    private var infoGroup: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: Image(ph: "shield-check", weight: .regular),
                label: "Privacy policy",
                style: .external,
                url: URL(string: "https://ripe-cereal-4f9.notion.site/Privacy-Policy-36c341fcbfde806e850dd81ac8b72b63")
            )
            SettingsRow(
                icon: Image(ph: "file-text", weight: .regular),
                label: "Terms of use",
                style: .external,
                url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
            )
            SettingsRow(
                icon: Image(ph: "envelope", weight: .regular),
                label: "Contact developer",
                style: .external,
                url: AppReviewPrompter.developerMailURL
            )
            SettingsRow(
                icon: Image(ph: "info", weight: .regular),
                label: "Version",
                value: versionString,
                style: .none
            )
        }
    }

    @ViewBuilder
    private var destructiveGroup: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: Image(ph: "sign-out", weight: .regular),
                label: "Sign out",
                style: .none,
                tone: .destructive
            ) {
                showSignOutConfirm = true
            }
            SettingsRow(
                icon: Image(ph: "trash", weight: .regular),
                label: "Delete account",
                style: .none,
                tone: .destructive
            ) {
                showDeleteConfirm = true
            }
        }
    }

    #if DEBUG
    @ViewBuilder
    private var developerGroup: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: Image(ph: "wrench", weight: .regular),
                label: "Developer options",
                style: .chevron,
                destination: {
                    DeveloperOptionsView(
                        entitlements: entitlements,
                        needsOnboarding: $needsOnboarding
                    )
                }
            )
        }
    }
    #endif

    // MARK: - Picker rows

    private var currencyRow: some View {
        Menu {
            // Text-only menu per [[feedback-no-icons-in-menus]].
            ForEach(currencyOptions, id: \.self) { code in
                Button(code) { defaultCurrency = code }
            }
        } label: {
            SettingsRowContent(
                icon: Image(ph: "currency-circle-dollar", weight: .regular),
                label: "顯示幣別",
                value: defaultCurrency,
                style: .menu,
                tone: .normal
            )
        }
    }

    // MARK: - Exchange rates

    @ViewBuilder
    private var exchangeRateGroup: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(ph: "arrows-clockwise", weight: .regular)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Theme.primaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("匯率")
                        .appFont(.body, weight: .medium)
                        .foregroundStyle(Theme.primaryText)
                    Text(fxStatusText)
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                    if let error = fx.lastError {
                        Text(error)
                            .appFont(.caption)
                            .foregroundStyle(Theme.expense)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    Task { await fx.refresh() }
                } label: {
                    if fx.isFetching {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("立即更新")
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(Theme.brand)
                    }
                }
                .buttonStyle(.plain)
                .disabled(fx.isFetching)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Text("所有金額會以顯示幣別呈現。每筆交易仍以原始幣別儲存,顯示時用今日匯率換算。匯率資料來源:Frankfurter (ECB)。")
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
    }

    private var fxStatusText: String {
        if let last = fx.lastUpdated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "上次更新 " + formatter.localizedString(for: last, relativeTo: Date())
        }
        return "尚未取得匯率"
    }

    private var appearanceRow: some View {
        Menu {
            Picker("Appearance", selection: $preferredAppearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
        } label: {
            SettingsRowContent(
                icon: Image(ph: "moon-stars", weight: .regular),
                label: "Appearance",
                value: appearanceLabel,
                style: .menu,
                tone: .normal
            )
        }
    }

    // MARK: - Divider

    private var groupDivider: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }

    // MARK: - Derived values

    private var appearanceLabel: String {
        switch preferredAppearance {
        case "light": "Light"
        case "dark": "Dark"
        default: "System"
        }
    }

    private var currentLanguageLabel: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code.uppercased()
    }

    private var versionString: String {
        let bundle = Bundle.main
        let v = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

}

// MARK: - Row primitives

private enum SettingsRowStyle {
    case chevron       // navigates to a sub-page
    case menu          // opens an inline picker (uses ↕ chevron)
    case external      // opens an external URL (uses ↗)
    case none          // pure action or read-only value
}

private enum SettingsRowTone {
    case normal
    case destructive
}

private struct SettingsRowContent: View {
    let icon: Image
    let label: LocalizedStringKey
    var value: String? = nil
    let style: SettingsRowStyle
    let tone: SettingsRowTone

    var body: some View {
        HStack(spacing: 12) {
            icon
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundStyle(labelColor)
            Text(label)
                .appFont(.body, weight: .medium)
                .foregroundStyle(labelColor)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .appFont(.subheadline)
                    .foregroundStyle(Theme.primaryText.opacity(0.5))
                    .lineLimit(1)
            }
            trailingGlyph
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private var labelColor: Color {
        switch tone {
        case .normal: Theme.primaryText
        case .destructive: Color.red
        }
    }

    @ViewBuilder
    private var trailingGlyph: some View {
        switch style {
        case .chevron:
            Image(systemName: "chevron.right")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(Theme.primaryText.opacity(0.3))
        case .menu:
            Image(systemName: "chevron.up.chevron.down")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(Theme.primaryText.opacity(0.3))
        case .external:
            Image(systemName: "arrow.up.right")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(Theme.primaryText.opacity(0.3))
        case .none:
            EmptyView()
        }
    }
}

private struct SettingsRow<Destination: View>: View {
    let icon: Image
    let label: LocalizedStringKey
    var value: String? = nil
    let style: SettingsRowStyle
    var tone: SettingsRowTone = .normal
    var url: URL? = nil
    var destination: (() -> Destination)? = nil
    var action: (() -> Void)? = nil

    init(
        icon: Image,
        label: LocalizedStringKey,
        value: String? = nil,
        style: SettingsRowStyle,
        tone: SettingsRowTone = .normal,
        url: URL? = nil,
        destination: (() -> Destination)? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.label = label
        self.value = value
        self.style = style
        self.tone = tone
        self.url = url
        self.destination = destination
        self.action = action
    }

    var body: some View {
        let content = SettingsRowContent(
            icon: icon, label: label, value: value, style: style, tone: tone
        )

        if let destination {
            NavigationLink { destination() } label: { content }
                .buttonStyle(.plain)
        } else if let url {
            Link(destination: url) { content }
                .buttonStyle(.plain)
        } else {
            Button(action: { action?() }) { content }
                .buttonStyle(.plain)
        }
    }
}

extension SettingsRow where Destination == EmptyView {
    init(
        icon: Image,
        label: LocalizedStringKey,
        value: String? = nil,
        style: SettingsRowStyle,
        tone: SettingsRowTone = .normal,
        url: URL? = nil,
        action: (() -> Void)? = nil
    ) {
        self.init(
            icon: icon,
            label: label,
            value: value,
            style: style,
            tone: tone,
            url: url,
            destination: nil,
            action: action
        )
    }
}

// MARK: - Developer options

#if DEBUG
private struct DeveloperOptionsView: View {
    let entitlements: Entitlements
    @Binding var needsOnboarding: Bool
    @AppStorage(Typography.DefaultsKey.latinMode) private var latinMode: String = Typography.FontMode.branded.rawValue
    @AppStorage(Typography.DefaultsKey.cjkMode) private var cjkMode: String = Typography.FontMode.native.rawValue
    @AppStorage("splashPreviewTrigger") private var splashPreviewTrigger: Int = 0
    @AppStorage(SplashDefaults.iconKey) private var splashIcon: String = SplashDefaults.defaultIcon.rawValue
    @AppStorage(SplashDefaults.iconSizeKey) private var splashIconSize: Int = SplashDefaults.defaultIconSize
    @AppStorage(SplashDefaults.appNameSizeKey) private var splashAppNameSize: Int = SplashDefaults.defaultAppNameSize
    @AppStorage(SplashDefaults.footerSizeKey) private var splashFooterSize: Int = SplashDefaults.defaultFooterSize
    @AppStorage(SplashDefaults.iconNameSpacingKey) private var splashIconNameSpacing: Int = SplashDefaults.defaultIconNameSpacing
    @AppStorage(SplashDefaults.blockOffsetYKey) private var splashBlockOffsetY: Int = SplashDefaults.defaultBlockOffsetY
    @AppStorage(SplashDefaults.footerBottomKey) private var splashFooterBottom: Int = SplashDefaults.defaultFooterBottom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Build-only switches for testing entitlements, onboarding, and other flows. Hidden in release builds.")
                    .appFont(.subheadline)
                    .foregroundStyle(Theme.primaryText.opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                VStack(spacing: 0) {
                    SettingsRow(
                        icon: Image(ph: "flag", weight: .regular),
                        label: "Pro plan",
                        value: entitlements.isPro ? "On" : "Off",
                        style: .none
                    ) {
                        let next = !entitlements.isPro
                        entitlements.upgrade(to: next ? .proYearly : .free)
                        if !next { entitlements.reset() }
                    }
                    SettingsRow(
                        icon: Image(ph: "monitor-play", weight: .regular),
                        label: "Preview onboarding",
                        style: .none
                    ) {
                        needsOnboarding = true
                    }
                    SettingsRow(
                        icon: Image(ph: "monitor-play", weight: .regular),
                        label: "Preview splash",
                        style: .none
                    ) {
                        splashPreviewTrigger &+= 1
                    }
                    splashIconRow
                    splashStepperRow(label: "Icon size", iconName: "ruler", value: $splashIconSize, range: 20...240, step: 5, unit: "pt")
                    splashStepperRow(label: "App name size", iconName: "text-aa", value: $splashAppNameSize, range: 10...80, step: 1, unit: "pt")
                    splashStepperRow(label: "Icon ↔ name spacing", iconName: "arrows-horizontal", value: $splashIconNameSpacing, range: 0...80, step: 1, unit: "pt")
                    splashStepperRow(label: "Block vertical offset", iconName: "arrows-vertical", value: $splashBlockOffsetY, range: -300...300, step: 5, unit: "pt")
                    splashStepperRow(label: "Footer text size", iconName: "text-t", value: $splashFooterSize, range: 8...40, step: 1, unit: "pt")
                    splashStepperRow(label: "Footer bottom padding", iconName: "arrow-down", value: $splashFooterBottom, range: 0...200, step: 4, unit: "pt")
                    fontModeRow(
                        label: "拉丁字體",
                        iconName: "text-aa",
                        selection: $latinMode
                    )
                    fontModeRow(
                        label: "中日韓字體",
                        iconName: "translate",
                        selection: $cjkMode
                    )
                }
            }
        }
        .background(Theme.appBackground.ignoresSafeArea())
        .navigationTitle("Developer options")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fontModeRow(label: LocalizedStringKey, iconName: String, selection: Binding<String>) -> some View {
        Menu {
            Picker(label, selection: selection) {
                Text("品牌字體").tag(Typography.FontMode.branded.rawValue)
                Text("系統字體").tag(Typography.FontMode.native.rawValue)
            }
        } label: {
            SettingsRowContent(
                icon: Image(ph: iconName, weight: .regular),
                label: label,
                value: selection.wrappedValue == Typography.FontMode.branded.rawValue ? "品牌" : "系統",
                style: .menu,
                tone: .normal
            )
        }
    }

    private var splashIconRow: some View {
        Menu {
            Picker("Splash icon", selection: $splashIcon) {
                ForEach(SplashIcon.allCases) { icon in
                    Text(icon.displayName).tag(icon.rawValue)
                }
            }
        } label: {
            SettingsRowContent(
                icon: Image(ph: "image-square", weight: .regular),
                label: "Splash icon",
                value: SplashIcon(rawValue: splashIcon)?.displayName ?? splashIcon,
                style: .menu,
                tone: .normal
            )
        }
    }

    private func splashStepperRow(
        label: LocalizedStringKey,
        iconName: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        unit: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(ph: iconName, weight: .regular)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.primaryText)
            Text(label)
                .appFont(.body, weight: .medium)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(value.wrappedValue)\(unit)")
                .appFont(.subheadline)
                .foregroundStyle(Theme.primaryText.opacity(0.5))
                .monospacedDigit()
            Stepper(label, value: value, in: range, step: step)
                .labelsHidden()
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
#endif
