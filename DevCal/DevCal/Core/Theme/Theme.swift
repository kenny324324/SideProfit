//
//  Theme.swift
//  DevCal
//
//  Shared color tokens, project-color palette, and view modifiers used across screens.
//  Source of truth: Files/Design_Spec.md.
//

import SwiftUI
import UIKit

enum Theme {

    // MARK: - Brand

    /// App tint / accent. Mirrors Assets.xcassets/AccentColor.colorset so `Color.accentColor` resolves to the same value.
    static let brand = Color(hex: "#E8704E")

    // MARK: - Semantic colors
    //
    // Greens and reds are warm-shifted to harmonize with the brand coral.
    // Anything that would conventionally be orange (e.g. "Building") should
    // use `brand` directly rather than a separate warning color.

    static let income = Color(hex: "#5C9866")   // warm sage green
    static let expense = Color(hex: "#C24E3A")  // warm brick red
    static let neutral = Color.blue
    static let warning = brand

    // MARK: - Surfaces
    //
    // Light: F8F8F6 page / F4F4F0 section / 5% black cards.
    // Dark:  1F1F1E page / 171717 section / 121212 cards.

    static let appBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: 0x1F1F1E)
            : UIColor(hex: 0xF8F8F6)
    })

    static let appBackgroundSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: 0x171717)
            : UIColor(hex: 0xF4F4F0)
    })

    /// Cards, list rows, selected/pressed surfaces.
    /// Light mode renders as 5% black so cards always sit one step darker than whatever they're layered on.
    static let cardBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: 0x121212)
            : UIColor.black.withAlphaComponent(0.05)
    })

    /// Legacy alias — prefer `cardBackground` in new code.
    static let listRowBackground = cardBackground

    // MARK: - Text

    static let primaryText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: 0xF8F8F6)
            : UIColor(hex: 0x1F1F1E)
    })

    /// Fixed-white text/icon color for foregrounds layered on top of brand
    /// or semantic-color fills (brand orange, income green, expense red).
    /// Stays pure white in both light and dark mode so contrast doesn't flip.
    static let onTint = Color.white

    // MARK: - Icon palette
    //
    // Used by project / category icon pickers. Index 0 is the brand and acts
    // as the "default" — stored as nil on the model so a future brand-color
    // change retroactively updates everything that hasn't been customized.
    // The other nine sit at roughly the same saturation / lightness as the
    // brand so the palette reads as one coherent set.

    static let iconPalette: [String] = [
        "#E8704E", // brand coral (default)
        "#E84E4E", // red
        "#E89F4E", // orange
        "#E8C44E", // amber
        "#6FBE4E", // green
        "#4EBFA8", // teal
        "#4E8FE8", // blue
        "#6A4EE8", // indigo
        "#B14EE8", // violet
        "#E84EAA"  // pink
    ]

    /// Resolves a stored icon color: nil → brand. Use everywhere a project /
    /// category icon is tinted so swatch + render stay in sync.
    static func iconColor(_ hex: String?) -> Color {
        guard let hex, !hex.isEmpty else { return brand }
        return Color(hex: hex)
    }
}

extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&rgb)
        let r, g, b: Double
        if trimmed.count == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
        } else {
            r = 0; g = 0; b = 0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

extension UIColor {
    fileprivate convenience init(hex: UInt32) {
        let r = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hex & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(hex & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - Card style

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.cardBackground)
            }
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

// MARK: - Banner style
//
// Used for fixed-top overlays (upgrade banner, project break-even hero).
// iOS 26+ gets native Liquid Glass; older systems fall back to the themed card surface.

struct BannerBackgroundModifier: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular.tint(Theme.appBackground.opacity(0.3)),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
                .background(
                    Theme.cardBackground,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .background(
                    Theme.appBackground.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        }
    }
}

extension View {
    /// Fixed-top banner surface — iOS 26 glass / fallback themed card.
    func bannerStyle(cornerRadius: CGFloat = 16) -> some View {
        modifier(BannerBackgroundModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Toolbar action button styles
//
// Sheet toolbars throughout the app split into two roles:
//   - Cancel / Close → primary text color, never tinted.
//   - Save / Done / Confirm → brand-tinted Liquid Glass pill on iOS 26.
// Adaptive tokens are used so light/dark inverts naturally.

extension View {
    /// Cancel / Close / dismiss style — plain primary-text label. Also
    /// overrides `.tint` because iOS 26 Liquid Glass toolbar buttons pick up
    /// the inherited tint (brand) on their glyph regardless of foregroundStyle.
    func cancelActionStyle() -> some View {
        foregroundStyle(Theme.primaryText)
            .tint(Theme.primaryText)
    }

    /// Save / Done / Confirm style — brand-tinted prominent pill with adaptive
    /// white label (`Theme.appBackground`) on iOS 26+.
    func confirmActionStyle() -> some View {
        buttonStyle(.borderedProminent)
            .tint(Theme.brand)
            .foregroundStyle(Theme.appBackground)
    }

    /// Form Section header — footnote secondary. Override for our custom
    /// Merriweather cascade which otherwise renders Form headers at body size.
    func formSectionHeaderStyle() -> some View {
        appFont(.footnote).foregroundStyle(.secondary)
    }

    /// Alert with Theme.primaryText for Cancel + red for destructive — isolates
    /// the alert from the app's brand tint so buttons never render in Theme.brand
    /// or system blue. Use this instead of `.alert` unless brand color is
    /// explicitly desired.
    func systemAlert<A: View>(
        _ title: LocalizedStringKey,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> A
    ) -> some View {
        background {
            Color.clear
                .alert(title, isPresented: isPresented, actions: actions)
                .tint(Theme.primaryText)
        }
    }

    func systemAlert<A: View, M: View>(
        _ title: LocalizedStringKey,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> A,
        @ViewBuilder message: () -> M
    ) -> some View {
        background {
            Color.clear
                .alert(title, isPresented: isPresented, actions: actions, message: message)
                .tint(Theme.primaryText)
        }
    }
}
