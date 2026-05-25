//
//  MetricTile.swift
//  DevCal
//
//  Editorial tile: label top-left, value bottom-right. Value is large but
//  scales down dynamically to fit the tile width — no ellipsis.
//

import SwiftUI

struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .appFont(.caption, weight: .medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            Text(value)
                .appFont(.title, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 76)
        .cardStyle(padding: 12)
    }
}
