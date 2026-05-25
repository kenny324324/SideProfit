//
//  IconColorPaletteView.swift
//  DevCal
//
//  Shared "pick a tint" row used by any picker that lets the user set an
//  icon color (project icon, category-item icon). Selection is stored as a
//  hex string and `nil` means "use the brand default" — so flipping the
//  brand color later retroactively updates everything still on default.
//

import SwiftUI
import PhosphorSymbols

struct IconColorPaletteView: View {
    /// Stored hex (e.g. "#E8704E"). `nil` = default (brand color for the
    /// surrounding context — Theme.brand when no brand icon is selected;
    /// the brand's own hex when one is).
    @Binding var selection: String?
    /// Optional override for what "default" looks like. When set (e.g. by
    /// IconPickerView when a brand icon is selected), the first swatch
    /// renders in this color so the user sees the brand's own color as
    /// the "default = no custom tint" position. nil → use Theme.iconPalette[0]
    /// (brand coral) as before.
    var defaultColor: Color? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            grid
        }
        .padding(.horizontal, 16)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("圖示顏色")
                .appFont(.body, weight: .medium)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            if selection != nil {
                Button {
                    withAnimation { selection = nil }
                } label: {
                    Text("回復預設")
                        .appFont(.footnote)
                        .foregroundStyle(Theme.primaryText.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(Theme.iconPalette.enumerated()), id: \.offset) { idx, hex in
                swatch(hex: hex, isDefault: idx == 0)
            }
        }
    }

    private func swatch(hex: String, isDefault: Bool) -> some View {
        // Default swatch is selected when `selection == nil`; others when their hex matches.
        let isSelected = isDefault ? (selection == nil) : (selection == hex)
        let fill: Color = (isDefault && defaultColor != nil) ? defaultColor! : Color(hex: hex)
        return Button {
            withAnimation { selection = isDefault ? nil : hex }
        } label: {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 36, height: 36)
                if isSelected {
                    Circle()
                        .stroke(Theme.primaryText, lineWidth: 2.5)
                        .frame(width: 44, height: 44)
                    Image(systemName: "checkmark")
                        .appFont(.footnote, weight: .bold)
                        .foregroundStyle(Theme.onTint)
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
