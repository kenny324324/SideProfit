//
//  SplashView.swift
//  DevCal
//
//  Custom splash that takes over after the native LaunchScreen.
//  The native LaunchScreen just paints `LaunchBackground` (matches
//  `Theme.appBackground`) so the handoff to this view is seamless —
//  the page background never flickers, only the icon fades in.
//

import SwiftUI

enum SplashIcon: String, CaseIterable, Identifiable {
    case plant
    case plantFill
    case dev
    case group53

    var id: String { rawValue }

    /// Asset catalog name.
    var assetName: String {
        switch self {
        case .plant:     return "Plant"
        case .plantFill: return "PlantFill"
        case .dev:       return "Dev"
        case .group53:   return "Group53"
        }
    }

    /// Single-color SVGs are template-rendered + tinted; multi-color SVGs
    /// keep their authored fills.
    var isTemplate: Bool {
        switch self {
        case .plant, .plantFill: return true
        case .dev, .group53:     return false
        }
    }

    var displayName: String {
        switch self {
        case .plant:     return "Plant"
        case .plantFill: return "Plant (fill)"
        case .dev:       return "Dev"
        case .group53:   return "Group 53"
        }
    }
}

enum SplashDefaults {
    static let iconKey = "splashIcon"
    static let iconSizeKey = "splashIconSize"
    static let appNameSizeKey = "splashAppNameSize"
    static let footerSizeKey = "splashFooterSize"
    static let iconNameSpacingKey = "splashIconNameSpacing"
    static let blockOffsetYKey = "splashBlockOffsetY"
    static let footerBottomKey = "splashFooterBottom"

    static let defaultIcon = SplashIcon.plantFill
    static let defaultIconSize: Int = 35
    static let defaultAppNameSize: Int = 35
    static let defaultFooterSize: Int = 18
    static let defaultIconNameSpacing: Int = 18
    static let defaultBlockOffsetY: Int = -60
    static let defaultFooterBottom: Int = 0

    /// Minimum on-screen time before the fade-out begins.
    static let minDisplayDuration: Duration = .seconds(1.0)
    static let fadeOutDuration: Double = 0.5
}

struct SplashView: View {
    @AppStorage(SplashDefaults.footerSizeKey) private var footerSize: Int = SplashDefaults.defaultFooterSize
    @AppStorage(SplashDefaults.blockOffsetYKey) private var blockOffsetY: Int = SplashDefaults.defaultBlockOffsetY
    @AppStorage(SplashDefaults.footerBottomKey) private var footerBottom: Int = SplashDefaults.defaultFooterBottom

    var body: some View {
        ZStack {
            Theme.appBackground
                .ignoresSafeArea()

            SplashBrandMark()
                .offset(y: CGFloat(blockOffsetY))

            VStack {
                Spacer()
                Text("KennyStudio")
                    .font(Typography.font(size: CGFloat(footerSize), weight: .regular))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.bottom, CGFloat(footerBottom))
            }
        }
    }
}

/// Icon + app-name lockup shown on the splash and carried into the auth screen
/// so the brand mark visually "stays put" across the splash → sign-in handoff.
/// Reads the same AppStorage knobs as the splash so design tweaks flow to both.
struct SplashBrandMark: View {
    @AppStorage(SplashDefaults.iconKey) private var iconRaw: String = SplashDefaults.defaultIcon.rawValue
    @AppStorage(SplashDefaults.iconSizeKey) private var iconSize: Int = SplashDefaults.defaultIconSize
    @AppStorage(SplashDefaults.appNameSizeKey) private var appNameSize: Int = SplashDefaults.defaultAppNameSize
    @AppStorage(SplashDefaults.iconNameSpacingKey) private var iconNameSpacing: Int = SplashDefaults.defaultIconNameSpacing

    private var icon: SplashIcon {
        SplashIcon(rawValue: iconRaw) ?? SplashDefaults.defaultIcon
    }

    private var appName: String {
        let bundle = Bundle.main
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "App"
    }

    var body: some View {
        HStack(spacing: CGFloat(iconNameSpacing)) {
            iconImage
            Text(appName)
                .font(Typography.font(size: CGFloat(appNameSize), weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var iconImage: some View {
        let side = CGFloat(iconSize)
        if icon.isTemplate {
            Image(icon.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .foregroundStyle(Theme.brand)
        } else {
            Image(icon.assetName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
        }
    }
}

#Preview {
    SplashView()
}
