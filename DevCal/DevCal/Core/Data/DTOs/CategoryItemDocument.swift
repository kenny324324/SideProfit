//
//  CategoryItemDocument.swift
//  DevCal
//
//  Remote / sync representation of a CategoryItem. See ProjectDocument for
//  shared conventions.
//
//  Two intentional differences from the SwiftData model:
//  - `projectIds: [String]` replaces the SwiftData `projects` relationship so
//    the document is self-contained. Order is preserved as a stable canonical
//    list (used by the UI when displaying the allocation).
//  - `weightsByProjectId: [String: Double]?` replaces the legacy index-matched
//    `weights: [Double]?`. Keyed by project id so re-ordering or partial pulls
//    can't drift the weights.
//

import Foundation

struct CategoryItemDocument: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var categoryRaw: String
    var totalAmount: Double
    var originalCurrencyCode: String
    var billingTypeRaw: String
    var brandIconKey: String?
    var fallbackIconName: String?
    var iconColorHex: String?
    var nextDueDate: Date?
    var isActive: Bool
    var isShared: Bool
    var splitModeRaw: String
    var weightsByProjectId: [String: Double]?
    var projectIds: [String]
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

extension CategoryItemDocument {
    init(from item: CategoryItem) {
        self.id = item.id.uuidString
        self.name = item.name
        self.categoryRaw = item.categoryRaw
        self.totalAmount = item.totalAmount
        self.originalCurrencyCode = item.originalCurrencyCode
        self.billingTypeRaw = item.billingTypeRaw
        self.brandIconKey = item.brandIconKey
        self.fallbackIconName = item.fallbackIconName
        self.iconColorHex = item.iconColorHex
        self.nextDueDate = item.nextDueDate
        self.isActive = item.isActive
        self.isShared = item.isShared
        self.splitModeRaw = item.splitModeRaw
        self.weightsByProjectId = item.weightsByProjectId
        self.projectIds = (item.projects ?? []).map { $0.id.uuidString }
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
        self.isDeleted = false
    }

    /// Applies scalar fields. The sync layer is responsible for hydrating the
    /// `projects` relationship from `projectIds`.
    func apply(to item: CategoryItem) {
        item.name = name
        item.categoryRaw = categoryRaw
        item.totalAmount = totalAmount
        item.originalCurrencyCode = originalCurrencyCode
        item.billingTypeRaw = billingTypeRaw
        item.brandIconKey = brandIconKey
        item.fallbackIconName = fallbackIconName
        item.iconColorHex = iconColorHex
        item.nextDueDate = nextDueDate
        item.isActive = isActive
        item.isShared = isShared
        item.splitModeRaw = splitModeRaw
        item.weightsByProjectId = weightsByProjectId
        item.createdAt = createdAt
        item.updatedAt = updatedAt
    }

    func makeCategoryItem() -> CategoryItem {
        let item = CategoryItem()
        item.id = UUID(uuidString: id) ?? UUID()
        apply(to: item)
        return item
    }
}
