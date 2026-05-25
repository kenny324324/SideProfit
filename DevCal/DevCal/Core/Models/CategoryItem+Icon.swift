//
//  CategoryItem+Icon.swift
//  DevCal
//
//  Icon resolution for CategoryItem. Priority: registered brand icon →
//  user-picked Phosphor symbol → parent category's default glyph.
//

import SwiftUI
import PhosphorSymbols

extension CategoryItem {
    /// The icon to render anywhere a CategoryItem is shown. Falls back through
    /// brand asset → Phosphor symbol → parent category icon.
    @ViewBuilder
    var displayIcon: some View {
        if BrandIconRegistry.hasAsset(for: brandIconKey) {
            BrandIconRegistry.image(for: brandIconKey)
        } else if let phName = fallbackIconName, !phName.isEmpty {
            Image(ph: phName)
        } else {
            category.icon
        }
    }
}
