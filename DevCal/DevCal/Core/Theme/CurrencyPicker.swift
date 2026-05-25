//
//  CurrencyPicker.swift
//  DevCal
//
//  Small Menu-style currency selector reused across Add* forms. Keeps the
//  picker visually compact next to the amount field instead of stealing a
//  full Form row.
//

import SwiftUI

struct CurrencyMenuButton: View {
    @Binding var selection: String

    var body: some View {
        Menu {
            // Text-only buttons per [[feedback-no-icons-in-menus]].
            ForEach(ExchangeRateService.supportedCodes, id: \.self) { code in
                Button(code) { selection = code }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection)
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(Theme.primaryText)
                Image(systemName: "chevron.up.chevron.down")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(Theme.primaryText.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.primaryText.opacity(0.06))
            }
        }
    }
}

/// Vertical hairline used between the currency picker and the amount input
/// in Add* forms. Match height to the picker's text baseline.
struct AmountFieldDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.15))
            .frame(width: 1, height: 22)
    }
}
