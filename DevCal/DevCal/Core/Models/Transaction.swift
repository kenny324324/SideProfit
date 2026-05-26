//
//  Transaction.swift
//  DevCal
//
//  每筆交易自帶顯示資料（名稱 + 圖標 + 顏色），不再透過 CategoryItem 拉取。
//  一次性支出 / 收入完全自包；訂閱類的也由排程器從 CategoryItem snapshot 過來，
//  之後修改 CategoryItem 不會回溯舊紀錄。
//

import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID = UUID()
    var typeRaw: String = TransactionType.expense.rawValue
    var categoryRaw: String = TransactionCategory.otherExpense.rawValue

    // MARK: - Display
    /// 使用者在新增頁打的名稱。e.g.「ChatGPT Plus」「Vercel Domain Renewal」。
    /// 一律必填（UI 強制）；查詢和分析會用這個當主要識別。
    var name: String = ""
    /// 品牌圖標 key（對應 BrandIconRegistry.knownKeys）。nil → 走 Phosphor fallback → 分類預設。
    var iconBrandKey: String? = nil
    /// Phosphor 符號名（當沒選品牌時可選的圖示）。nil → 走分類預設。
    var iconFallbackName: String? = nil
    /// 圖標 tint hex。nil → 走 BrandIconRegistry.renderColor 的 fallback。
    var iconColorHex: String? = nil

    // MARK: - Amount
    /// 使用者輸入時的原始金額，存在 originalCurrencyCode 下。
    /// 顯示時才透過 ExchangeRateService 轉成顯示幣別。
    var originalAmount: Double = 0
    /// ISO 4217 幣別 (e.g. "USD")。
    var originalCurrencyCode: String = "TWD"

    // MARK: - Other
    var note: String = ""
    var date: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// 訂閱排程器自動產生的交易會帶回來源 CategoryItem 的 UUID，方便日後做
    /// 「這筆是 ChatGPT 訂閱第 5 期」之類的追溯。手動新增的單次交易為 nil。
    var sourceCategoryItemID: UUID? = nil

    /// Scheduler-generated transactions stamp a stable string of
    /// `{categoryItemId}_{projectId}_{yyyyMMdd}` so two devices firing the
    /// scheduler for the same billing period converge on the same remote
    /// document instead of duplicating. Local-only idempotency is still
    /// enforced via `sourceCategoryItemID` + same-day check. Manual rows leave
    /// this nil.
    var deterministicID: String? = nil

    var project: Project?

    init(
        type: TransactionType = .expense,
        category: TransactionCategory = .otherExpense,
        name: String = "",
        iconBrandKey: String? = nil,
        iconFallbackName: String? = nil,
        iconColorHex: String? = nil,
        originalAmount: Double = 0,
        originalCurrencyCode: String = "TWD",
        note: String = "",
        date: Date = Date(),
        project: Project? = nil,
        sourceCategoryItemID: UUID? = nil,
        deterministicID: String? = nil
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.categoryRaw = category.rawValue
        self.name = name
        self.iconBrandKey = iconBrandKey
        self.iconFallbackName = iconFallbackName
        self.iconColorHex = iconColorHex
        self.originalAmount = originalAmount
        self.originalCurrencyCode = originalCurrencyCode
        self.note = note
        self.date = date
        self.project = project
        self.sourceCategoryItemID = sourceCategoryItemID
        self.deterministicID = deterministicID
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var category: TransactionCategory {
        get { TransactionCategory(rawValue: categoryRaw) ?? .otherExpense }
        set { categoryRaw = newValue.rawValue }
    }

    /// 對外顯示的名稱：name 有值就用，沒有 fallback 到分類名稱。
    /// 大部分情況 name 都會有值（UI 強制必填），這個 fallback 只是給舊資料或
    /// 排程器特殊情況使用。
    var displayName: String { name.isEmpty ? "" : name }

    /// Signed in the ORIGINAL currency. Use only when filtering by sign within a
    /// single currency (e.g. UI tint decisions). Aggregations across multiple
    /// originals must convert first via `signedConvertedAmount(to:fx:)`.
    var signedOriginalAmount: Double {
        type == .income ? originalAmount : -originalAmount
    }

    /// Amount converted to `displayCode` using today's FX. Returns 0 when FX is
    /// unavailable (the row UI shows a "—" instead via `convertedAmount(to:fx:)`).
    func convertedAmount(to displayCode: String, fx: ExchangeRateService) -> Double {
        fx.convert(originalAmount, from: originalCurrencyCode, to: displayCode) ?? 0
    }

    /// Signed converted amount. Income positive, expense negative.
    func signedConvertedAmount(to displayCode: String, fx: ExchangeRateService) -> Double {
        let value = convertedAmount(to: displayCode, fx: fx)
        return type == .income ? value : -value
    }
}
