//
//  Typography.swift
//  DevCal
//
//  Source of truth: Files/Design_Spec.md → Typography.
//
//  Primary face: Merriweather (Latin, digits, symbols) — 24pt optical static.
//  CJK fallback: Chiron Hei HK (繁體中文 / 漢字) — sans / 黑體.
//
//  Built on UIFontDescriptor `.cascadeList`, which renders each glyph in the
//  first font of the cascade that supports it — so a mixed string like
//  "Net profit 淨利" picks Merriweather for the Latin and Chiron for the CJK
//  without us having to splice runs manually.
//
//  Graceful fallback: if the font files aren't bundled yet, every call falls
//  back to `Font.system(_:)` so the app still renders.
//

import SwiftUI
import UIKit
import CoreText

enum Typography {

    // MARK: - Font mode
    //
    // Each script (Latin / CJK) can independently be set to either the
    // bundled brand face or the iOS system face. Persisted in UserDefaults
    // so it's readable from `App.init()` before any SwiftUI view exists.
    //
    // - Latin `.native` → SF / system serif fallback
    // - CJK `.native`   → PingFang TC / system 黑體 (iOS picks automatically)

    enum FontMode: String, CaseIterable, Identifiable {
        case branded
        case native
        var id: String { rawValue }
    }

    enum DefaultsKey {
        static let latinMode = "fontLatinMode"
        static let cjkMode = "fontCJKMode"
    }

    static var latinMode: FontMode {
        FontMode(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.latinMode) ?? "")
            ?? .branded
    }

    static var cjkMode: FontMode {
        FontMode(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.cjkMode) ?? "")
            ?? .native
    }

    // MARK: - PostScript names
    //
    // These are the PostScript names embedded in the font files, NOT the
    // filenames. Verify with Font Book → Show Font Info after installing.

    enum PostScript {
        // Merriweather 24pt optical (designed for body / UI text sizes).
        static let merriweatherRegular = "Merriweather24pt-Regular"
        static let merriweatherMedium = "Merriweather24pt-Medium"
        static let merriweatherSemiBold = "Merriweather24pt-SemiBold"
        static let merriweatherBold = "Merriweather24pt-Bold"
        static let merriweatherItalic = "Merriweather24pt-Italic"

        static let chironRegular = "ChironHeiHK-Regular"
        static let chironMedium = "ChironHeiHK-Medium"
        static let chironSemiBold = "ChironHeiHK-SemiBold"
        static let chironBold = "ChironHeiHK-Bold"
    }

    // MARK: - Public API

    /// Returns a Dynamic-Type-aware `Font` that uses the selected Latin face
    /// (Merriweather or system) and cascades to the selected CJK face
    /// (Chiron Hei HK or system) for glyphs the primary lacks.
    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let uiStyle = style.uiKit
        let baseSize = UIFont.preferredFont(forTextStyle: uiStyle).pointSize
        let cascaded = makeUIFont(size: baseSize, weight: weight)
        let scaled = UIFontMetrics(forTextStyle: uiStyle).scaledFont(for: cascaded)
        return Font(scaled)
    }

    /// Custom point size variant for one-off display sizes (e.g. hero headlines).
    static func font(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let cascaded = makeUIFont(size: size, weight: weight)
        let scaled = UIFontMetrics(forTextStyle: style.uiKit).scaledFont(for: cascaded)
        return Font(scaled)
    }

    // MARK: - Weight mapping
    //
    // Both families ship Regular / Medium / SemiBold / Bold in the bundle,
    // so SwiftUI weight requests map 1:1. Anything heavier (.heavy/.black)
    // falls onto Bold; lighter requests fall onto Regular.
    //
    // Returning `nil` means "use the system face for this script".

    private static func latinPostScript(for weight: Font.Weight) -> String? {
        guard latinMode == .branded else { return nil }
        switch weight {
        case .black, .heavy, .bold: return PostScript.merriweatherBold
        case .semibold:             return PostScript.merriweatherSemiBold
        case .medium:               return PostScript.merriweatherMedium
        default:                    return PostScript.merriweatherRegular
        }
    }

    private static func cjkPostScript(for weight: Font.Weight) -> String? {
        guard cjkMode == .branded else { return nil }
        switch weight {
        case .black, .heavy, .bold: return PostScript.chironBold
        case .semibold:             return PostScript.chironSemiBold
        case .medium:               return PostScript.chironMedium
        default:                    return PostScript.chironRegular
        }
    }

    /// Single source of cascade-list construction used by both SwiftUI and
    /// UIKit entry points. Falls back to the system face for either script
    /// when the mode is `.native` or when the branded file fails to load.
    private static func makeUIFont(size: CGFloat, weight: Font.Weight) -> UIFont {
        let primary: UIFont = {
            if let name = latinPostScript(for: weight),
               let f = UIFont(name: name, size: size) {
                return f
            }
            return UIFont.systemFont(ofSize: size, weight: weight.uiKit)
        }()

        guard let cjkName = cjkPostScript(for: weight),
              let cjkFont = UIFont(name: cjkName, size: size) else {
            return primary
        }
        let descriptor = primary.fontDescriptor.addingAttributes(
            [.cascadeList: [cjkFont.fontDescriptor]]
        )
        return UIFont(descriptor: descriptor, size: size)
    }

    // MARK: - UIKit bridge
    //
    // SwiftUI's `.navigationTitle()` is rendered by UINavigationBar, which
    // ignores `.font(...)` modifiers — it reads `titleTextAttributes` /
    // `largeTitleTextAttributes` off the UINavigationBarAppearance. Call
    // `applyUIKitAppearance()` once at app launch to wire those up.

    /// Returns a UIFont using the currently selected Latin face with the
    /// selected CJK face as a cascade fallback, at a fixed point size. Wrap
    /// with `UIFontMetrics` at the call site if Dynamic Type scaling is desired.
    static func uiFont(weight: Font.Weight, size: CGFloat) -> UIFont {
        makeUIFont(size: size, weight: weight)
    }

    /// Registers all bundled `.ttf` files with CoreText at app launch.
    ///
    /// We rely on this instead of `Info.plist`'s `UIAppFonts` because Xcode 26's
    /// `GENERATE_INFOPLIST_FILE` flow does not honor `INFOPLIST_KEY_UIAppFonts`
    /// — the build setting is accepted but never written into the generated
    /// Info.plist, so iOS never registers the fonts. Doing the registration
    /// at process scope via CoreText is independent of Info.plist entirely.
    static func registerBundledFonts() {
        let fileNames = [
            "Merriweather_24pt-Regular",
            "Merriweather_24pt-Medium",
            "Merriweather_24pt-SemiBold",
            "Merriweather_24pt-Bold",
            "Merriweather_24pt-Italic",
            "ChironHeiHK-Regular",
            "ChironHeiHK-Medium",
            "ChironHeiHK-SemiBold",
            "ChironHeiHK-Bold",
        ]
        for name in fileNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                #if DEBUG
                print("⚠️  Font file not found in bundle: \(name).ttf")
                #endif
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            // Errors here are typically "already registered" — benign.
        }
    }

    /// Diagnostic: prints whether each expected PostScript font registered.
    /// Call from `App.init()` during bring-up; remove once verified.
    static func logFontRegistrationStatus() {
        #if DEBUG
        let expected = [
            PostScript.merriweatherRegular,
            PostScript.merriweatherMedium,
            PostScript.merriweatherSemiBold,
            PostScript.merriweatherBold,
            PostScript.merriweatherItalic,
            PostScript.chironRegular,
            PostScript.chironMedium,
            PostScript.chironSemiBold,
            PostScript.chironBold,
        ]
        print("=== DevCal font registration ===")
        for name in expected {
            let ok = UIFont(name: name, size: 12) != nil
            print("  [\(ok ? "✓" : "✗")] \(name)")
        }
        let related = UIFont.familyNames.filter {
            $0.lowercased().contains("merri") || $0.lowercased().contains("chiron")
        }
        if related.isEmpty {
            print("  ⚠️  No Merriweather or Chiron family registered.")
            print("     Check INFOPLIST_KEY_UIAppFonts and that .ttf files are in the app bundle.")
        } else {
            for family in related {
                print("  family \(family) →", UIFont.fontNames(forFamilyName: family))
            }
        }
        print("===============================")
        #endif
    }

    /// Wires DevCal's typography into UIKit-rendered chrome (navigation bars).
    /// Safe to call multiple times. Call from `App.init()` so the appearance
    /// is set before any nav bar gets rendered.
    static func applyUIKitAppearance() {
        registerBundledFonts()

        let largeTitle = UIFontMetrics(forTextStyle: .largeTitle)
            .scaledFont(for: uiFont(weight: .bold, size: 34))
        let inlineTitle = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: uiFont(weight: .semibold, size: 17))

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes = [.font: largeTitle]
        appearance.titleTextAttributes = [.font: inlineTitle]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(Theme.brand)
        segmented.setTitleTextAttributes(
            [.foregroundColor: UIColor(Theme.appBackground)],
            for: .selected
        )
        segmented.setTitleTextAttributes(
            [.foregroundColor: UIColor(Theme.primaryText)],
            for: .normal
        )
    }
}

private extension Font.Weight {
    var uiKit: UIFont.Weight {
        switch self {
        case .black:        return .black
        case .heavy:        return .heavy
        case .bold:         return .bold
        case .semibold:     return .semibold
        case .medium:       return .medium
        case .light:        return .light
        case .thin:         return .thin
        case .ultraLight:   return .ultraLight
        default:            return .regular
        }
    }
}

private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}

// MARK: - View modifier
//
// Drop-in replacement for SwiftUI's `.font(.body.weight(.semibold))` etc.
// Usage:
//   .appFont(.body)                  // body, regular
//   .appFont(.title3, weight: .semibold)
//   .appFont(size: 56, weight: .bold)

extension View {
    func appFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        font(Typography.font(style, weight: weight))
    }

    func appFont(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> some View {
        font(Typography.font(size: size, weight: weight, relativeTo: style))
    }
}
