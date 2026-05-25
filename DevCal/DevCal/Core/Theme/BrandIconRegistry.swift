//
//  BrandIconRegistry.swift
//  DevCal
//
//  Maps a stable `brandIconKey` (stored on CategoryItem) to a brand asset in
//  the Assets catalog. Centralizes the brand list so adding a new icon is a
//  one-line change here + dropping the SVG into Assets.xcassets.
//
//  Asset naming convention: "Brand_<KeyFirstUpper>" (e.g. "Brand_Stripe",
//  "Brand_Github"). The fetch script (/tmp/fetch_brand_icons.py) follows
//  this rule so SVGs auto-resolve via aliases() with no per-brand special-case.
//
//  Where the SVGs come from:
//    - simpleicons.org (CC0) for the bulk of the list — fetched via their CDN
//    - Font Awesome Free (CC BY 4.0 — requires attribution) for openai / aws /
//      amazon / linode / adobe / linkedin, which simpleicons dropped for
//      trademark reasons.
//
//  Each registered key is paired with its official brand hex in
//  `brandColor(for:)`. The picker and any "brand icon selected" surface
//  renders the SVG tinted with this hex via `brandIconColor(_:)`, which
//  swaps pure black / pure white for `Theme.primaryText` so adaptive contrast
//  is preserved across light/dark mode.
//

import SwiftUI
import UIKit

enum BrandIconRegistry {
    /// Stable, lowercase keys used by `CategoryItem.brandIconKey`. Order here
    /// is the order shown in the picker grid (loosely grouped by category).
    /// Only keys with bundled assets — the picker filters via `hasAsset(for:)`.
    static let knownKeys: [String] = [
        // Core / AI
        "openai", "claude", "cursor", "windsurf", "perplexity",
        "suno", "elevenlabs", "mistral", "replicate",
        // Dev platforms
        "github", "gitlab", "vercel", "supabase", "firebase", "cloudflare",
        "sentry", "posthog", "mixpanel", "revenuecat",
        // Cloud / infra
        "aws", "amazon", "digitalocean", "vultr", "hetzner", "linode",
        "flydotio", "railway", "render", "netlify",
        // Payments / Stores
        "apple", "google", "stripe", "gumroad", "lemonsqueezy", "paddle",
        "patreon", "kofi", "buymeacoffee", "substack", "opencollective",
        // APIs / services
        "resend", "mapbox", "algolia",
        // Software / Productivity
        "notion", "linear", "raycast", "1password", "obsidian", "setapp",
        "dropbox", "ticktick",
        // Design
        "figma", "framer", "adobe", "sketch",
        // Advertising / Social
        "meta", "x", "reddit", "tiktok", "linkedin",
        "admob", "unity",
        // Domains
        "namecheap", "porkbun", "godaddy",
        // Outsourcing
        "upwork", "fiverr", "toptal",
        // Devices / Testing
        "ios", "macos", "android", "windows", "microsoft",
        "linux", "samsung", "huawei", "xiaomi"
    ]

    /// Human-readable display name shown next to the icon in the picker.
    static func displayName(for key: String) -> String {
        switch key {
        // Core / AI
        case "openai": return "OpenAI"
        case "claude": return "Claude"
        case "cursor": return "Cursor"
        case "windsurf": return "Windsurf"
        case "perplexity": return "Perplexity"
        case "suno": return "Suno"
        case "elevenlabs": return "ElevenLabs"
        case "mistral": return "Mistral"
        case "replicate": return "Replicate"
        // Dev
        case "github": return "GitHub"
        case "gitlab": return "GitLab"
        case "vercel": return "Vercel"
        case "supabase": return "Supabase"
        case "firebase": return "Firebase"
        case "cloudflare": return "Cloudflare"
        case "sentry": return "Sentry"
        case "posthog": return "PostHog"
        case "mixpanel": return "Mixpanel"
        case "revenuecat": return "RevenueCat"
        // Cloud
        case "aws": return "AWS"
        case "amazon": return "Amazon"
        case "digitalocean": return "DigitalOcean"
        case "vultr": return "Vultr"
        case "hetzner": return "Hetzner"
        case "linode": return "Linode"
        case "flydotio": return "Fly.io"
        case "railway": return "Railway"
        case "render": return "Render"
        case "netlify": return "Netlify"
        // Payments / Stores
        case "apple": return "Apple"
        case "google": return "Google Play"
        case "stripe": return "Stripe"
        case "gumroad": return "Gumroad"
        case "lemonsqueezy": return "Lemon Squeezy"
        case "paddle": return "Paddle"
        case "patreon": return "Patreon"
        case "kofi": return "Ko-fi"
        case "buymeacoffee": return "Buy Me a Coffee"
        case "substack": return "Substack"
        case "opencollective": return "Open Collective"
        // APIs
        case "resend": return "Resend"
        case "mapbox": return "Mapbox"
        case "algolia": return "Algolia"
        // Software
        case "notion": return "Notion"
        case "linear": return "Linear"
        case "raycast": return "Raycast"
        case "1password": return "1Password"
        case "obsidian": return "Obsidian"
        case "setapp": return "Setapp"
        case "dropbox": return "Dropbox"
        case "ticktick": return "TickTick"
        // Design
        case "figma": return "Figma"
        case "framer": return "Framer"
        case "adobe": return "Adobe"
        case "sketch": return "Sketch"
        // Ads / Social
        case "meta": return "Meta"
        case "x": return "X"
        case "reddit": return "Reddit"
        case "tiktok": return "TikTok"
        case "linkedin": return "LinkedIn"
        case "admob": return "AdMob"
        case "unity": return "Unity"
        // Domains
        case "namecheap": return "Namecheap"
        case "porkbun": return "Porkbun"
        case "godaddy": return "GoDaddy"
        // Outsourcing
        case "upwork": return "Upwork"
        case "fiverr": return "Fiverr"
        case "toptal": return "Toptal"
        // Devices
        case "ios": return "iOS"
        case "macos": return "macOS"
        case "android": return "Android"
        case "windows": return "Windows"
        case "microsoft": return "Microsoft"
        case "linux": return "Linux"
        case "samsung": return "Samsung"
        case "huawei": return "Huawei"
        case "xiaomi": return "Xiaomi"
        default: return key.capitalized
        }
    }

    /// Official brand hex (no `#`). Returned as a raw string so callers can
    /// decide whether to fall back to `Theme.primaryText` (the rule lives in
    /// `brandIconColor(_:)`). All values derive from the SVG `fill="#…"`
    /// attribute simpleicons ships in each icon body; the FA six are hand
    /// transcribed from each company's public brand kit.
    static func brandColor(for key: String) -> String? {
        switch key {
        case "claude": return "D97757"
        case "cursor": return "000000"
        case "windsurf": return "0B100F"
        case "perplexity": return "1FB8CD"
        case "suno": return "000000"
        case "elevenlabs": return "000000"
        case "replicate": return "000000"
        case "github": return "181717"
        case "gitlab": return "FC6D26"
        case "vercel": return "000000"
        case "supabase": return "3FCF8E"
        case "firebase": return "DD2C00"
        case "cloudflare": return "F38020"
        case "sentry": return "362D59"
        case "posthog": return "000000"
        case "mixpanel": return "7856FF"
        case "revenuecat": return "F2545B"
        case "digitalocean": return "0080FF"
        case "vultr": return "007BFC"
        case "hetzner": return "D50C2D"
        case "flydotio": return "24175B"
        case "railway": return "0B0D0E"
        case "render": return "000000"
        case "netlify": return "00C7B7"
        case "stripe": return "635BFF"
        case "gumroad": return "FF90E8"
        case "lemonsqueezy": return "FFC233"
        case "paddle": return "FDDD35"
        case "patreon": return "000000"
        case "kofi": return "FF6433"
        case "buymeacoffee": return "FFDD00"
        case "substack": return "FF6719"
        case "opencollective": return "7FADF2"
        case "resend": return "000000"
        case "mapbox": return "000000"
        case "algolia": return "003DFF"
        case "notion": return "000000"
        case "linear": return "5E6AD2"
        case "raycast": return "FF6363"
        case "1password": return "145FE4"
        case "obsidian": return "7C3AED"
        case "setapp": return "E6C3A5"
        case "dropbox": return "0061FF"
        case "ticktick": return "4772FA"
        case "figma": return "F24E1E"
        case "framer": return "0055FF"
        case "sketch": return "F7B500"
        case "meta": return "0467DF"
        case "x": return "000000"
        case "reddit": return "FF4500"
        case "tiktok": return "000000"
        case "unity": return "FFFFFF"
        case "namecheap": return "DE3723"
        case "porkbun": return "EF7878"
        case "godaddy": return "1BDBDB"
        case "upwork": return "6FDA44"
        case "fiverr": return "1DBF73"
        case "toptal": return "3863A0"
        case "android": return "3DDC84"
        case "ios": return "000000"
        case "macos": return "000000"
        case "windows": return "0078D4"
        case "microsoft": return "737373"
        case "linux": return "FCC624"
        case "samsung": return "1428A0"
        case "huawei": return "FF0000"
        case "xiaomi": return "FF6900"
        case "mistral": return "FA520F"
        case "admob": return "EA4335"
        case "apple": return "000000"
        case "google": return "414141"
        case "openai": return "000000"
        case "aws": return "FF9900"
        case "amazon": return "FF9900"
        case "linode": return "00A95C"
        case "adobe": return "FA0F00"
        case "linkedin": return "0A66C2"
        default: return nil
        }
    }

    /// Resolves a brand key to a render color. Pure black (`000000`) and pure
    /// white (`FFFFFF`) collapse to `Theme.primaryText` so they invert in
    /// dark mode — that's the brand intent (Vercel/Notion ship a "black on
    /// light, white on dark" mark, Unity ships the inverse). All other hexes
    /// render as-is so each logo carries its real brand color.
    static func brandIconColor(for key: String?) -> Color {
        guard let key, let hex = brandColor(for: key) else { return Theme.primaryText }
        let normalized = hex.uppercased()
        if normalized == "000000" || normalized == "FFFFFF" {
            return Theme.primaryText
        }
        return Color(hex: hex)
    }

    /// One-shot color resolver matching the picker's rules. Use everywhere a
    /// CategoryItem icon is rendered so the picker and the live UI never drift:
    /// - User-picked tint set → that color (overrides brand, lets users
    ///   recolor a logo if they want to).
    /// - Brand asset present and no user tint → brand's own color (with
    ///   adaptive pure black/white).
    /// - No brand, no user tint → `Theme.brand` (legacy default).
    static func renderColor(brandKey: String?, iconColorHex: String?) -> Color {
        if let iconColorHex, !iconColorHex.isEmpty {
            return Color(hex: iconColorHex)
        }
        if hasAsset(for: brandKey) {
            return brandIconColor(for: brandKey)
        }
        return Theme.brand
    }

    /// Brand keys relevant to a given transaction category. The picker uses
    /// this to default-filter its brand grid so the user isn't scrolling past
    /// 70 unrelated logos. Order within each list is the preferred display
    /// order. Search overrides this filter and matches across `knownKeys`.
    static func brandKeys(for category: TransactionCategory) -> [String] {
        switch category {
        // ----- Income -----
        case .appSales:
            return ["apple", "google", "stripe", "paddle"]
        case .subscriptions:
            return ["apple", "google", "stripe", "paddle", "lemonsqueezy", "revenuecat"]
        case .adRevenue:
            return ["meta", "x", "reddit", "tiktok", "admob", "unity"]
        case .sponsorship:
            return ["patreon", "kofi", "buymeacoffee", "substack", "opencollective", "github", "gumroad"]
        case .otherIncome:
            return []
        // ----- Expense -----
        case .server:
            return ["aws", "amazon", "digitalocean", "vultr", "hetzner", "linode", "flydotio", "railway", "render", "netlify", "cloudflare", "supabase", "firebase"]
        case .api:
            // AI API 串接 (OpenAI / Anthropic / Mistral 等) 跟一般 SaaS API
            // 都會落在這個分類,所以兩種一起列。AI 放前面因為 indie 用得多。
            return ["openai", "claude", "mistral", "replicate", "perplexity", "elevenlabs",
                    "resend", "mapbox", "algolia", "stripe", "cloudflare", "supabase", "firebase"]
        case .appStoreFee:
            return ["apple"]
        case .googlePlayFee:
            return ["google"]
        case .domain:
            return ["namecheap", "porkbun", "godaddy", "cloudflare"]
        case .design:
            return ["figma", "framer", "adobe", "sketch"]
        case .advertising:
            return ["meta", "x", "reddit", "tiktok", "linkedin", "admob", "unity"]
        case .outsourcing:
            return ["upwork", "fiverr", "toptal"]
        case .software:
            return ["notion", "linear", "raycast", "1password", "obsidian", "setapp", "dropbox", "ticktick"]
        case .aiTools:
            return ["openai", "claude", "cursor", "windsurf", "perplexity", "suno", "elevenlabs", "mistral", "replicate", "github"]
        case .testingDevices:
            return ["ios", "macos", "android", "windows", "microsoft",
                    "linux", "samsung", "huawei", "xiaomi"]
        case .devTools:
            return ["github", "gitlab", "vercel", "supabase", "firebase", "sentry", "posthog", "mixpanel", "revenuecat"]
        case .otherExpense:
            return []
        }
    }

    /// Returns the asset name in `Assets.xcassets` for a given key, or nil
    /// if no asset has been added yet (caller should fall back).
    static func assetName(for key: String?) -> String? {
        guard let key else { return nil }
        let name = derivedAssetName(for: key)
        return UIImage(named: name) != nil ? name : nil
    }

    /// Returns a template-rendered brand image for the given key, or an empty
    /// view if the asset hasn't been added yet. Renders at the caller's
    /// `.frame()` size with no extra scaling — simpleicons SVGs have tight
    /// viewBoxes (24x24, no padding), so 1:1 is the right baseline.
    @ViewBuilder
    static func image(for key: String?) -> some View {
        if let name = assetName(for: key) {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        } else {
            EmptyView()
        }
    }

    /// True when an asset has been registered for this key.
    static func hasAsset(for key: String?) -> Bool {
        assetName(for: key) != nil
    }

    /// Default asset-name rule: `Brand_<KeyFirstUpper>`. Every key in
    /// `knownKeys` ships an asset with this exact name (the fetch script
    /// enforces the convention), so no per-key alias table is needed.
    private static func derivedAssetName(for key: String) -> String {
        let first = key.prefix(1).uppercased()
        return "Brand_\(first)\(key.dropFirst())"
    }
}
