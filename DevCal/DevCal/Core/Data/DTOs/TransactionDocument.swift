//
//  TransactionDocument.swift
//  DevCal
//
//  Remote / sync representation of a Transaction. See ProjectDocument for
//  the shared conventions used by every *Document.
//
//  Note on `deterministicID`: subscription-scheduler-generated transactions
//  carry a stable string of `{categoryItemId}_{projectId}_{yyyyMMdd}`. Lets
//  multiple devices converge on the same row without duplicating when both
//  fire the scheduler for the same period. nil for manually-created rows.
//

import Foundation

struct TransactionDocument: Codable, Equatable, Sendable {
    var id: String
    /// String form of the parent project's UUID. Optional because a transaction
    /// could theoretically lose its project locally; the sync layer treats nil
    /// as orphaned.
    var projectId: String?
    var typeRaw: String
    var categoryRaw: String
    var name: String
    var iconBrandKey: String?
    var iconFallbackName: String?
    var iconColorHex: String?
    var originalAmount: Double
    var originalCurrencyCode: String
    var note: String
    var date: Date
    var createdAt: Date
    var updatedAt: Date
    var sourceCategoryItemId: String?
    var deterministicId: String?
    var isDeleted: Bool
}

extension TransactionDocument {
    init(from txn: Transaction) {
        self.id = txn.id.uuidString
        self.projectId = txn.project?.id.uuidString
        self.typeRaw = txn.typeRaw
        self.categoryRaw = txn.categoryRaw
        self.name = txn.name
        self.iconBrandKey = txn.iconBrandKey
        self.iconFallbackName = txn.iconFallbackName
        self.iconColorHex = txn.iconColorHex
        self.originalAmount = txn.originalAmount
        self.originalCurrencyCode = txn.originalCurrencyCode
        self.note = txn.note
        self.date = txn.date
        self.createdAt = txn.createdAt
        self.updatedAt = txn.updatedAt
        self.sourceCategoryItemId = txn.sourceCategoryItemID?.uuidString
        self.deterministicId = txn.deterministicID
        self.isDeleted = false
    }

    func apply(to txn: Transaction) {
        txn.typeRaw = typeRaw
        txn.categoryRaw = categoryRaw
        txn.name = name
        txn.iconBrandKey = iconBrandKey
        txn.iconFallbackName = iconFallbackName
        txn.iconColorHex = iconColorHex
        txn.originalAmount = originalAmount
        txn.originalCurrencyCode = originalCurrencyCode
        txn.note = note
        txn.date = date
        txn.createdAt = createdAt
        txn.updatedAt = updatedAt
        txn.sourceCategoryItemID = sourceCategoryItemId.flatMap(UUID.init(uuidString:))
        txn.deterministicID = deterministicId
    }

    /// Builds a detached Transaction. The sync layer hydrates the `project`
    /// relationship separately by looking up `projectId`.
    func makeTransaction() -> Transaction {
        let txn = Transaction()
        txn.id = UUID(uuidString: id) ?? UUID()
        apply(to: txn)
        return txn
    }
}
