//
//  CategoryItem.swift
//  DevCal
//
//  A user-defined sub-item under a TransactionCategory (e.g. "ChatGPT Plus"
//  under .aiTools). Carries billing metadata so subscription items can auto-
//  generate Transactions on their due dates. Can be project-scoped or shared
//  across multiple projects with an allocation policy.
//

import Foundation
import SwiftData

// MARK: - Supporting enums

enum BillingType: String, CaseIterable, Codable, Identifiable {
    case oneTime
    case monthly
    case yearly

    var id: String { rawValue }

    var isRecurring: Bool { self != .oneTime }
}

enum SplitMode: String, CaseIterable, Codable, Identifiable {
    case equal
    case weighted

    var id: String { rawValue }
}

// MARK: - Model

@Model
final class CategoryItem {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = TransactionCategory.otherExpense.rawValue
    /// Always stores the full (un-split) amount. Per-project share is computed.
    var totalAmount: Double = 0
    /// ISO 4217 currency the user picked when creating this item. The scheduler
    /// stamps generated Transactions with this same code so subscriptions stay
    /// in their original currency regardless of later display-currency changes.
    var originalCurrencyCode: String = "USD"
    var billingTypeRaw: String = BillingType.oneTime.rawValue
    /// Lookup key for `BrandIconRegistry` (e.g. "openai"). nil → fall back to
    /// `fallbackIconName` (a Phosphor symbol picked at create time) or the
    /// big-category default icon.
    var brandIconKey: String? = nil
    /// Phosphor symbol name (e.g. "hard-drives") chosen by the user when no
    /// brand icon is set. nil → fall back to the big-category default.
    var fallbackIconName: String? = nil
    /// Hex string for the icon tint. nil → use `Theme.brand`.
    var iconColorHex: String? = nil
    /// Next due date for recurring billing. nil for one-time items, or after a
    /// recurring item is disabled/exhausted.
    var nextDueDate: Date? = nil
    var isActive: Bool = true
    /// false → project-scoped (`projects` has exactly 1 entry).
    /// true  → shared across multiple projects with `splitMode`/`weights`.
    var isShared: Bool = false
    var splitModeRaw: String = SplitMode.equal.rawValue
    /// Per-project share weights keyed by project id (UUID.uuidString) when
    /// `splitModeRaw == .weighted`. Keyed rather than index-matched so the
    /// weights survive Firestore round-trips and any reordering of `projects`.
    /// nil → fall back to equal split.
    var weightsByProjectId: [String: Double]? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(inverse: \Project.categoryItems)
    var projects: [Project]? = []

    init(
        name: String = "",
        category: TransactionCategory = .otherExpense,
        totalAmount: Double = 0,
        originalCurrencyCode: String = "USD",
        billingType: BillingType = .oneTime,
        brandIconKey: String? = nil,
        fallbackIconName: String? = nil,
        iconColorHex: String? = nil,
        nextDueDate: Date? = nil,
        isActive: Bool = true,
        isShared: Bool = false,
        splitMode: SplitMode = .equal,
        weightsByProjectId: [String: Double]? = nil,
        projects: [Project] = []
    ) {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.totalAmount = totalAmount
        self.originalCurrencyCode = originalCurrencyCode
        self.billingTypeRaw = billingType.rawValue
        self.brandIconKey = brandIconKey
        self.fallbackIconName = fallbackIconName
        self.iconColorHex = iconColorHex
        self.nextDueDate = nextDueDate
        self.isActive = isActive
        self.isShared = isShared
        self.splitModeRaw = splitMode.rawValue
        self.weightsByProjectId = weightsByProjectId
        self.projects = projects
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    // MARK: - Enum accessors

    var category: TransactionCategory {
        get { TransactionCategory(rawValue: categoryRaw) ?? .otherExpense }
        set { categoryRaw = newValue.rawValue }
    }

    var billingType: BillingType {
        get { BillingType(rawValue: billingTypeRaw) ?? .oneTime }
        set { billingTypeRaw = newValue.rawValue }
    }

    var splitMode: SplitMode {
        get { SplitMode(rawValue: splitModeRaw) ?? .equal }
        set { splitModeRaw = newValue.rawValue }
    }

    var transactionType: TransactionType { category.type }

    // MARK: - Split

    /// The amount that should be charged to `project` when this item fires.
    /// For dedicated items, returns the full amount. For shared items, applies
    /// the split policy. Returns 0 if `project` isn't in the allocation list.
    func amount(for project: Project) -> Double {
        let list = projects ?? []
        guard !list.isEmpty else { return totalAmount }
        if !isShared || list.count == 1 {
            return totalAmount
        }
        // Project not in the allocation → 0, regardless of mode.
        guard list.contains(where: { $0.id == project.id }) else { return 0 }
        switch splitMode {
        case .equal:
            return totalAmount / Double(list.count)
        case .weighted:
            guard let weightsByProjectId else {
                return totalAmount / Double(list.count)
            }
            // Total over the *currently allocated* projects only — stale keys
            // for removed projects shouldn't dilute the active split.
            let active = list.map { weightsByProjectId[$0.id.uuidString] ?? 0 }
            let total = active.reduce(0, +)
            guard total > 0 else { return totalAmount / Double(list.count) }
            let myWeight = weightsByProjectId[project.id.uuidString] ?? 0
            return totalAmount * (myWeight / total)
        }
    }

    // MARK: - Recurring schedule

    /// Advance `nextDueDate` by one billing period. For one-time items, clears
    /// it. Called after the scheduler creates Transactions for the current due
    /// date.
    func advanceDueDate() {
        guard let current = nextDueDate else { return }
        switch billingType {
        case .oneTime:
            nextDueDate = nil
        case .monthly:
            nextDueDate = Calendar.current.date(byAdding: .month, value: 1, to: current)
        case .yearly:
            nextDueDate = Calendar.current.date(byAdding: .year, value: 1, to: current)
        }
    }
}
