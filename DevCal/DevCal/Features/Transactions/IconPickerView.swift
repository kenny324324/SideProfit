//
//  IconPickerView.swift
//  DevCal
//
//  Two-section icon picker used by CategoryItem forms:
//  1. Brand icons — every key in `BrandIconRegistry.knownKeys` with a bundled
//     asset. Each tile renders in the brand's official color (via
//     `BrandIconRegistry.brandIconColor(for:)`, which folds pure-black /
//     pure-white into adaptive `Theme.primaryText`). The selected tile is
//     marked by a hairline border, never by a color swap.
//  2. Phosphor symbols — a curated set covering common dev/SaaS subscriptions
//     for one-off items that don't deserve a brand logo. Phosphor tiles
//     respect `iconColorHex` so the user can recolor them.
//  Selecting from either section is mutually exclusive: brand clears Phosphor
//  and vice versa. A search field filters both sections (display names for
//  brand rows, symbol names for Phosphor).
//
//  Color palette visibility:
//  - Hidden when a brand is selected (brand color is the brand color).
//  - Shown when no icon is picked (default) or a Phosphor symbol is selected,
//    so the user can customize the tint of generic icons.
//

import SwiftUI
import PhosphorSymbols

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let category: TransactionCategory
    @Binding var brandIconKey: String?
    @Binding var fallbackIconName: String?
    @Binding var iconColorHex: String?
    /// Optional callback invoked when the user taps 完成. When provided, the
    /// caller usually finalizes parent state (e.g. records the category in
    /// AddTransactionView) and dismisses the whole sheet stack — this view
    /// just calls it, no extra dismiss.
    var onDone: (() -> Void)? = nil

    @State private var searchText: String = ""

    private let phosphorOptions: [String] = [
        "hard-drives", "cloud", "network", "globe", "lightning",
        "credit-card", "currency-circle-dollar", "receipt",
        "paint-brush", "wrench", "code", "terminal-window",
        "megaphone", "speaker-high", "users", "user",
        "devices", "device-mobile", "monitor", "package",
        "lightbulb", "sparkle", "star", "heart",
        "shopping-bag", "shopping-cart", "key", "lock",
        "chart-line-up", "trend-up", "graph", "database",
        "app-window", "browsers", "translate", "headphones",
        "video-camera", "microphone", "camera", "image-square",
        "envelope", "chat-circle", "bell", "rocket"
    ]

    private let columns = [GridItem(.adaptive(minimum: 56, maximum: 80), spacing: 12)]

    /// Default brand list is filtered to the current category — only the
    /// logos that make sense under, say, AI Tools or Server. Search overrides
    /// the filter and matches across every key in `knownKeys` so a user who
    /// knows what they want can still find an off-category brand.
    private var categoryRelevantKeys: [String] {
        BrandIconRegistry.brandKeys(for: category).filter { BrandIconRegistry.hasAsset(for: $0) }
    }

    private var allKnownAssetKeys: [String] {
        BrandIconRegistry.knownKeys.filter { BrandIconRegistry.hasAsset(for: $0) }
    }

    private var filteredBrandKeys: [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty { return categoryRelevantKeys }
        return allKnownAssetKeys.filter { key in
            key.lowercased().contains(trimmed)
                || BrandIconRegistry.displayName(for: key).lowercased().contains(trimmed)
        }
    }

    private var filteredPhosphorKeys: [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return phosphorOptions }
        return phosphorOptions.filter { $0.lowercased().contains(trimmed) }
    }

    /// What the "回復預設" swatch in the color palette should render as. When
    /// a brand is selected, default = the brand's own color. Otherwise the
    /// shared component falls back to `Theme.iconPalette[0]`.
    private var paletteDefaultColor: Color? {
        guard let brandIconKey, BrandIconRegistry.hasAsset(for: brandIconKey) else { return nil }
        return BrandIconRegistry.brandIconColor(for: brandIconKey)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                defaultRow
                IconColorPaletteView(
                    selection: $iconColorHex,
                    defaultColor: paletteDefaultColor
                )

                if !filteredBrandKeys.isEmpty {
                    sectionHeader("品牌")
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredBrandKeys, id: \.self) { key in
                            brandTile(key)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if !filteredPhosphorKeys.isEmpty {
                    sectionHeader("圖示")
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredPhosphorKeys, id: \.self) { name in
                            symbolTile(name)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if filteredBrandKeys.isEmpty && filteredPhosphorKeys.isEmpty {
                    Text("找不到符合的圖示")
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Theme.appBackground)
        .navigationTitle("選擇圖標")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: Text("搜尋品牌或圖示"))
        .toolbar {
            // IconPickerView 是被 push 進 NavigationStack 的子頁,系統會自動
            // 給返回箭頭。額外的 xmark 會跟返回鍵重複,所以只保留右上「完成」。
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    if let onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
                .confirmActionStyle()
            }
        }
    }

    private var defaultRow: some View {
        Button {
            brandIconKey = nil
            fallbackIconName = nil
        } label: {
            HStack(spacing: 12) {
                category.icon
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Theme.primaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("分類預設")
                        .appFont(.body, weight: .medium)
                        .foregroundStyle(Theme.primaryText)
                    Text(category.displayName)
                        .appFont(.footnote)
                        .foregroundStyle(Theme.primaryText.opacity(0.5))
                }
                Spacer()
                if brandIconKey == nil && (fallbackIconName ?? "").isEmpty {
                    Image(systemName: "checkmark")
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(Theme.brand)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .formSectionHeaderStyle()
            .padding(.horizontal, 20)
    }

    /// Brand tile: same gray treatment as the Phosphor section for unselected
    /// state so the two sections read as one grid. Selected brand "lights up"
    /// — defaults to the brand's own color, but if the user has picked a tint
    /// from the palette that tint wins (`renderColor` enforces the rule).
    private func brandTile(_ key: String) -> some View {
        let isSelected = brandIconKey == key
        return Button {
            brandIconKey = key
            fallbackIconName = nil
        } label: {
            VStack(spacing: 6) {
                BrandIconRegistry.image(for: key)
                    .frame(width: 30, height: 30)
                    .foregroundStyle(
                        isSelected
                            ? BrandIconRegistry.renderColor(brandKey: key, iconColorHex: iconColorHex)
                            : Theme.primaryText.opacity(0.5)
                    )
                    .frame(width: 52, height: 52)
                Text(BrandIconRegistry.displayName(for: key))
                    .appFont(.caption)
                    .foregroundStyle(Theme.primaryText.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func symbolTile(_ name: String) -> some View {
        let isSelected = fallbackIconName == name
        return Button {
            fallbackIconName = name
            brandIconKey = nil
        } label: {
            Image(ph: name, weight: isSelected ? .fill : .bold)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundStyle(
                    isSelected ? Theme.iconColor(iconColorHex) : Theme.primaryText.opacity(0.5)
                )
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
