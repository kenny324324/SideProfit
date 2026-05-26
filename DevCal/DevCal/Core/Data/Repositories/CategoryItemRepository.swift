//
//  CategoryItemRepository.swift
//  DevCal
//
//  Write boundary for CategoryItem records. Covers both:
//  - The hidden CategoryItem created from AddTransactionView when the user
//    picks monthly/yearly billing for a one-off project.
//  - The user-visible shared CategoryItem created from SharedExpenseEditView
//    with multi-project allocation.
//

import Foundation
import SwiftData

@MainActor
final class CategoryItemRepository {
    private let context: ModelContext
    private let sync: SyncServicing

    init(context: ModelContext, sync: SyncServicing) {
        self.context = context
        self.sync = sync
    }

    /// Lightweight value type the views pass to the repo. Keeps the method
    /// signature compact and gives the view a single struct to mutate.
    struct CategoryItemInput {
        var name: String
        var category: TransactionCategory
        var totalAmount: Double
        var originalCurrencyCode: String
        var billingType: BillingType
        var brandIconKey: String?
        var fallbackIconName: String?
        var iconColorHex: String?
        var nextDueDate: Date?
        var isActive: Bool
        var isShared: Bool
        var splitMode: SplitMode
        /// Keyed by project id string. `nil` → equal split.
        var weightsByProjectId: [String: Double]?
        var projects: [Project]
    }

    @discardableResult
    func createCategoryItem(_ input: CategoryItemInput) async throws -> CategoryItem {
        let trimmed = input.name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw DataLayerError.invalidInput("Item name cannot be empty.")
        }
        guard input.totalAmount > 0 else {
            throw DataLayerError.invalidInput("Amount must be greater than zero.")
        }
        guard !input.projects.isEmpty else {
            throw DataLayerError.invalidInput("Pick at least one project.")
        }

        let item = CategoryItem(
            name: trimmed,
            category: input.category,
            totalAmount: input.totalAmount,
            originalCurrencyCode: input.originalCurrencyCode,
            billingType: input.billingType,
            brandIconKey: input.brandIconKey,
            fallbackIconName: input.fallbackIconName,
            iconColorHex: input.iconColorHex,
            nextDueDate: input.billingType.isRecurring ? input.nextDueDate : nil,
            isActive: input.isActive,
            isShared: input.isShared,
            splitMode: input.splitMode,
            weightsByProjectId: input.splitMode == .weighted ? input.weightsByProjectId : nil,
            projects: input.projects
        )
        context.insert(item)
        try save()
        try enqueueSync(for: item)
        return item
    }

    func updateCategoryItem(_ item: CategoryItem, _ input: CategoryItemInput) async throws {
        let trimmed = input.name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw DataLayerError.invalidInput("Item name cannot be empty.")
        }
        guard input.totalAmount > 0 else {
            throw DataLayerError.invalidInput("Amount must be greater than zero.")
        }
        guard !input.projects.isEmpty else {
            throw DataLayerError.invalidInput("Pick at least one project.")
        }

        item.name = trimmed
        item.category = input.category
        item.totalAmount = input.totalAmount
        item.originalCurrencyCode = input.originalCurrencyCode
        item.billingType = input.billingType
        item.nextDueDate = input.billingType.isRecurring ? input.nextDueDate : nil
        item.brandIconKey = input.brandIconKey
        item.fallbackIconName = input.fallbackIconName
        item.iconColorHex = input.iconColorHex
        item.isActive = input.isActive
        item.isShared = input.isShared
        item.splitMode = input.splitMode
        item.weightsByProjectId = input.splitMode == .weighted ? input.weightsByProjectId : nil
        item.projects = input.projects
        item.updatedAt = Date()
        try save()
        try enqueueSync(for: item)
    }

    func deleteCategoryItem(_ item: CategoryItem) async throws {
        let document = CategoryItemDocument(from: item).tombstoned
        context.delete(item)
        try save()
        try enqueueTombstone(document)
    }

    // MARK: - Internals

    private func save() throws {
        do {
            try context.save()
        } catch {
            throw DataLayerError.localSaveFailed(underlying: error)
        }
    }

    private func enqueueSync(for item: CategoryItem) throws {
        let doc = CategoryItemDocument(from: item)
        let op = try PendingSyncOperation.make(
            entityId: doc.id,
            kind: .categoryItem,
            document: doc
        )
        sync.enqueue(op)
    }

    private func enqueueTombstone(_ document: CategoryItemDocument) throws {
        let op = try PendingSyncOperation.make(
            entityId: document.id,
            kind: .categoryItem,
            document: document
        )
        sync.enqueue(op)
    }
}

private extension CategoryItemDocument {
    var tombstoned: CategoryItemDocument {
        var copy = self
        copy.isDeleted = true
        copy.updatedAt = Date()
        return copy
    }
}
