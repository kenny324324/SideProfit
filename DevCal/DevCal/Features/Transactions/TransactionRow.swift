//
//  TransactionRow.swift
//  DevCal
//
//  每筆交易在列表的顯示。圖標 / 顏色 / 名稱全部從 Transaction 自帶欄位讀,
//  不再回頭查 CategoryItem——訂閱類在排程器產生時就 snapshot 過來了。
//
//  Row shows the amount converted to the user's display currency on the
//  trailing edge. When the transaction's original currency differs from the
//  display currency, a small "$20 USD" subtitle sits beneath the amount so
//  the user sees that day-to-day rate drift is FX-driven, not data-driven.
//

import SwiftUI
import PhosphorSymbols

struct TransactionRow: View {
    let transaction: Transaction
    var showProjectName: Bool = false

    @AppStorage("defaultCurrency") private var defaultCurrency: String = "USD"
    @Environment(ExchangeRateService.self) private var fx

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconBackgroundColor)
                    .frame(width: 36, height: 36)
                renderedIcon
                    .frame(width: 18, height: 18)
                    .foregroundStyle(iconForegroundColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLabel)
                    .appFont(.subheadline, weight: .medium)
                HStack(spacing: 6) {
                    Text(transaction.category.displayName)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.secondary).appFont(.caption)
                    Text(transaction.date, style: .date)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    if showProjectName, let projectName = transaction.project?.name {
                        Text("·").foregroundStyle(.secondary).appFont(.caption)
                        Text(projectName)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !transaction.note.isEmpty {
                        Text("·").foregroundStyle(.secondary).appFont(.caption)
                        Text(transaction.note)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedAmount)
                    .appFont(.callout, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(transaction.type.tint)
                if showsOriginalSubtitle {
                    Text(originalSubtitle)
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// 名稱:有打就用,沒打 fallback 到分類名稱(理論上 UI 強制必填,只是保險)。
    private var primaryLabel: String {
        if !transaction.name.isEmpty { return transaction.name }
        // category.displayName 是 LocalizedStringKey,需要解析成 String。
        // 在 v1 範圍內就直接吃 rawValue,通常 name 都會有值。
        return transaction.category.rawValue
    }

    @ViewBuilder
    private var renderedIcon: some View {
        if let key = transaction.iconBrandKey, BrandIconRegistry.hasAsset(for: key) {
            BrandIconRegistry.image(for: key)
        } else if let phName = transaction.iconFallbackName, !phName.isEmpty {
            Image(ph: phName)
                .resizable()
                .scaledToFit()
        } else {
            transaction.category.icon
        }
    }

    private var iconForegroundColor: Color {
        BrandIconRegistry.renderColor(
            brandKey: transaction.iconBrandKey,
            iconColorHex: transaction.iconColorHex
        )
    }

    /// 底色永遠跟 icon 同色,低透明度。包含純黑/白 brand 也走 primaryText 的
    /// adaptive 顏色,在深淺模式都有微微的色票感。
    private var iconBackgroundColor: Color {
        iconForegroundColor.opacity(0.12)
    }

    private var formattedAmount: String {
        let prefix = transaction.type == .income ? "+" : "-"
        if let value = fx.convert(transaction.originalAmount, from: transaction.originalCurrencyCode, to: defaultCurrency) {
            return prefix + value.asCurrency(defaultCurrency)
        }
        return prefix + "—"
    }

    private var showsOriginalSubtitle: Bool {
        transaction.originalCurrencyCode != defaultCurrency
    }

    private var originalSubtitle: String {
        transaction.originalAmount.asCurrency(transaction.originalCurrencyCode)
            + " " + transaction.originalCurrencyCode
    }
}
