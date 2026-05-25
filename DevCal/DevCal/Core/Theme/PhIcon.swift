//
//  PhIcon.swift
//  DevCal
//
//  Glue for using Phosphor icons exposed by the local PhosphorSymbols package.
//  Phosphor icons are now custom SF Symbols, so callers can simply use
//  `Image(ph: "name")` or pass an Image straight into Label/.tabItem/etc.
//
//  This file keeps a single convenience init so `model.icon` values (already
//  typed as `Image`) plug into a Label without writing the closure form.
//

import SwiftUI
import PhosphorSymbols

extension Label where Title == Text, Icon == Image {
    init(_ titleKey: LocalizedStringKey, phosphor: Image) {
        self.init {
            Text(titleKey)
        } icon: {
            phosphor
        }
    }
}
