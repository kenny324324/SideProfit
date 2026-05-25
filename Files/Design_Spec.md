# DevCal / SideProfit — Design Spec

Single source of truth for visual design tokens. Update this file whenever the design language changes; code tokens live in `DevCal/DevCal/Core/Theme/Theme.swift` and the asset catalog.

Last updated: 2026-05-18 (typography wired, fonts bundled)

---

## 1. Color

### Brand
| Token | Hex | Notes |
|---|---|---|
| `brand` | `#E8704E` | App tint / accent. Used for primary buttons, active tab tint, key icons, focus rings. Also lives in `Assets.xcassets/AccentColor.colorset` so `Color.accentColor` resolves to it. |

### Light mode
| Token | Hex | Usage |
|---|---|---|
| `appBackground` | `#F8F8F6` | Page background for every screen. |
| `appBackgroundSecondary` | `#F4F4F0` | Section background, grouped containers behind cards. |
| `cardBackground` | `rgba(0,0,0,0.05)` (5% black overlay) | Cards, list rows, selected/pressed surfaces. Rendered as 5% black over the page background so cards always sit one step darker than their container. |
| `primaryText` | `#1F1F1E` | Body text, headings, primary icons. |

### Dark mode
| Token | Hex | Usage |
|---|---|---|
| `appBackground` | `#1F1F1E` | Page background for every screen. |
| `appBackgroundSecondary` | `#171717` | Section background, grouped containers behind cards. |
| `cardBackground` | `#121212` | Cards, list rows, selected/pressed surfaces. |
| `primaryText` | `#F8F8F6` | Body text, headings, primary icons. |

### Semantic palette
Kept from the original Theme so income/expense framing reads at a glance.

| Token | Light/Dark | Usage |
|---|---|---|
| `income` | `Color.green` | Revenue, positive deltas. |
| `expense` | `Color.red` | Expenses, negative deltas. |
| `neutral` | `Color.blue` | Informational accents. |
| `warning` | `Color.orange` | Time-cost / runway warnings. |

### Project picker palette
The 10 Apple-style hues users can tag a project with — defined in `Theme.projectColors` and not part of the global theme. Brand color `#E8704E` is intentionally not in this list (it is reserved as the app's tint).

---

## 2. Development rules

**Every view explicitly applies typography and background.** Do not rely on inheritance from `RootView` — SwiftUI environments break across modal boundaries (`.sheet`, `.fullScreenCover`, `.popover`) and several container styles (`Form`, grouped `List`) override the inherited font/background entirely. If a developer skips the modifiers, the view silently falls back to system font + system background and we lose the design language piecemeal.

For every new view, the body must include:

```swift
.appFont(.body)                          // or whatever style the screen uses as its baseline
.background(Theme.appBackground)         // even if the view sits inside a NavigationStack already wrapped with one
```

For `Form` / scrollable `List` screens, additionally:

```swift
.scrollContentBackground(.hidden)        // hides the system grouped background so ours shows through
.background(Theme.appBackground)
.listRowBackground(Theme.cardBackground) // applied per row, on rows that should look like cards
```

For every `Text` / `Label`, prefer `.appFont(...)` over SwiftUI's `.font(.body)`. The latter resolves to system font; `.appFont` goes through `Typography.font` and produces the Merriweather + Chiron Hei cascade.

Other conventions:

- Always render the page background via `Theme.appBackground` — never `UIColor.systemGroupedBackground` or `Color(.systemBackground)`. The two diverge in dark mode and on iPad.
- The 5% black overlay in light mode for `Theme.cardBackground` is deliberate: it stays consistent with whatever the page background is, so cards never look washed out if the background tone shifts.
- Pure `Color.black` / `Color.white` should only appear inside vendor-branded controls (e.g. the Apple Sign In button). Elsewhere use `Theme.primaryText` so dark mode flips correctly.
- For iOS 26+ "filled / glass-tinted" toolbar buttons that should read as primary actions, wrap the Button with `.buttonStyle(.borderedProminent).tint(Theme.brand)` inside an `if #available(iOS 26.0, *)` branch — the bordered prominent style picks up Liquid Glass material and tints to brand. Keep older iOS as the plain icon button.

---

## 3. Typography

Editorial / typographic direction — pairs a Latin serif with a CJK serif so the whole app reads like a book, not a Settings panel.

### Families
| Role | Family | Notes |
|---|---|---|
| Latin / digits / symbols | **Merriweather** (24pt optical static) | Serif tuned for on-screen reading. Open-source (SIL OFL). The `_24pt` files are the optical variant designed for small-text rendering (≤ 24pt) — that's the right pick for body and UI labels. |
| 繁體中文 / 漢字 (CJK fallback) | **Chiron Hei HK** | 港式黑體 (sans), open-source (SIL OFL) from [chiron-fonts/chiron-hei-hk](https://github.com/chiron-fonts/chiron-hei-hk). The serif-Latin × sans-CJK pairing is deliberate — pulls the editorial weight toward English/numbers and keeps Chinese clean and legible at small sizes. |
| Monospaced data | `Font.system(.body, design: .monospaced)` | Reserved for receipt-like numeric tables (e.g. Settings build info). Don't replace these with Merriweather. |

Mixed strings — `"Net profit 淨利 $12,340"` — render each glyph from the first font in the cascade that supports it: Latin/digits → Merriweather, CJK → Chiron Hei HK. No per-Text language switching needed.

### Weight strategy
| SwiftUI request | Merriweather (24pt) | Chiron Hei HK |
|---|---|---|
| `.regular` | Regular | Regular |
| `.medium` | Medium | Medium |
| `.semibold` | SemiBold | SemiBold |
| `.bold` / `.heavy` / `.black` | Bold | Bold |

Both families ship a matched four-weight ramp in the bundle, so SwiftUI weight requests map 1:1.

### Code usage
- Use `.appFont(_:weight:)` instead of SwiftUI's `.font(_:)` for any text content. It wraps `Typography.font(_:weight:)` and produces the cascaded `UIFont` under the hood.
- For one-off display sizes (hero numbers etc.) use `.appFont(size: 56, weight: .bold)`.
- The root `RootView` already sets `.font(Typography.font(.body))` as the inherited default — `Text` nodes without an explicit font will pick up Merriweather + Chiron.
- `Font.system(..., design: .rounded | .monospaced)` is left alone where it already exists; that's a deliberate signal that the value is numeric/tabular, not editorial.

### Navigation bars (UIKit-rendered)
SwiftUI's `.navigationTitle()` is drawn by UIKit's `UINavigationBar`, which **ignores** `.font(...)`. We wire the custom font in globally via `Typography.applyUIKitAppearance()`, called from `DevCalApp.init()`. It sets:

- **Large title**: Merriweather Bold @ 34pt (scaled via `UIFontMetrics(forTextStyle: .largeTitle)` so it honors Dynamic Type), cascaded to Chiron Hei HK Bold for CJK glyphs.
- **Inline title**: Merriweather SemiBold @ 17pt scaled via `.headline` metrics, cascaded to Chiron Hei SemiBold.

Applied to all four appearance slots (`standardAppearance`, `compactAppearance`, `scrollEdgeAppearance`, `compactScrollEdgeAppearance`) so the title stays in our font whether the navigation bar is opaque, compact, or large-title-with-scroll-edge.

Currently *not* customized — add to `applyUIKitAppearance()` if needed:
- `.navigationSubtitle()` (iOS 26) — uses a separate `UINavigationItem` attributed-subtitle attribute, not a global appearance key. We're not using subtitles yet.
- `UITabBar.appearance()` — tab labels still use system font.
- `UIBarButtonItem.appearance()` — toolbar button text still uses system font.

### Bundled font files

Live at `DevCal/DevCal/Resources/Fonts/` and auto-included in the target via the synchronized `DevCal/` group.

**Registration is runtime, not Info.plist.** Xcode 26's `GENERATE_INFOPLIST_FILE` flow does **not** honor `INFOPLIST_KEY_UIAppFonts` — the build setting is accepted but never written into the generated Info.plist (verified: `PlistBuddy -c "Print :UIAppFonts" .../DevCal.app/Info.plist` → `Entry does not exist`). Instead, `Typography.registerBundledFonts()` calls `CTFontManagerRegisterFontsForURL` for each `.ttf` at app launch (called from `DevCalApp.init()`). Add a font: drop it in `Resources/Fonts/`, append its name (without extension) to the array in `Typography.registerBundledFonts()`, and its PostScript name to `Typography.PostScript`.

| Filename | PostScript name |
|---|---|
| `Merriweather_24pt-Regular.ttf` | `Merriweather24pt-Regular` |
| `Merriweather_24pt-Medium.ttf` | `Merriweather24pt-Medium` |
| `Merriweather_24pt-SemiBold.ttf` | `Merriweather24pt-SemiBold` |
| `Merriweather_24pt-Bold.ttf` | `Merriweather24pt-Bold` |
| `Merriweather_24pt-Italic.ttf` | `Merriweather24pt-Italic` |
| `ChironHeiHK-Regular.ttf` | `ChironHeiHK-Regular` |
| `ChironHeiHK-Medium.ttf` | `ChironHeiHK-Medium` |
| `ChironHeiHK-SemiBold.ttf` | `ChironHeiHK-SemiBold` |
| `ChironHeiHK-Bold.ttf` | `ChironHeiHK-Bold` |

Sources:
- Merriweather → [Google Fonts](https://fonts.google.com/specimen/Merriweather) (download the full ZIP — the `static/` folder includes the optical sizes; we use the `_24pt` set only)
- Chiron Hei HK → [github.com/chiron-fonts/chiron-hei-hk](https://github.com/chiron-fonts/chiron-hei-hk) (static TTFs)

The full Google Fonts Merriweather drop contains 130+ files (multiple optical sizes plus SemiCondensed variants); only the `_24pt` non-condensed set is in the bundle. The originals at the repo root (`Merriweather/`, `Chiron_Hei_HK/`) are not bundled — they can stay as a vendor archive or be removed.

The cascade gracefully degrades: if a PostScript name is missing or mistyped, that style falls back to `Font.system(_:)` so the app still renders. If you swap optical sizes (e.g. switch to `_36pt`) update [Typography.swift](../DevCal/DevCal/Core/Theme/Typography.swift)'s `PostScript` enum to match.

---

## 4. Open items

Sections to add as decisions are made:
- Spacing / radius tokens (carry the "no rounded cards" stance — see feedback memory `design-taste`)
- Shadow / elevation rules
- Iconography conventions (Phosphor vs SF Symbols)
- Motion / haptics guidelines
- Layout patterns: editorial / typographic / table-style references (Linear, Things, Cron, Stripe)
