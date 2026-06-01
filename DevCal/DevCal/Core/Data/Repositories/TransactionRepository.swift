//
//  TransactionRepository.swift
//  DevCal
//
//  The single write boundary for Transaction records. AddTransactionView used
//  to own all of this (form state + validation + create + platform-fee fork +
//  break-even stamp + recurring CategoryItem + scheduler trigger + save +
//  delete); now it owns just form state and intent, and dispatches to one of
//  the methods below.
//
//  The companion `TransactionUseCase` composes the higher-level flows
//  (one-time + optional platform fee, subscription + initial scheduler run)
//  on top of these atomic repository methods.
//

import Foundation
import SwiftData

@MainActor
final class TransactionRepository {
    private let context: ModelContext
    private let sync: SyncServicing

    init(context: ModelContext, sync: SyncServicing) {
        self.context = context
        self.sync = sync
    }

    // MARK: - Atomic writes

    /// Creates a one-time Transaction attached to `project` and stamps
    /// break-even on the project if this write tips it over. Returns the new
    /// row plus whether break-even was just reached for this write (used by
    /// the app-review prompter).
    struct CreateOutcome {
        let transaction: Transaction
        let reachedBreakEvenForThisWrite: Bool
    }

    @discardableResult
    func createOneTimeTransaction(
        project: Project,
        type: TransactionType,
        category: TransactionCategory,
        name: String,
        iconBrandKey: String?,
        iconFallbackName: String?,
        iconColorHex: String?,
        originalAmount: Double,
        originalCurrencyCode: String,
        note: String,
        date: Date,
        displayCurrency: String,
        fx: ExchangeRateService
    ) async throws -> CreateOutcome {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw DataLayerError.invalidInput("Transaction name cannot be empty.")
        }
        guard originalAmount > 0 else {
            throw DataLayerError.invalidInput("Amount must be greater than zero.")
        }

        let hadReachedBreakEven = project.breakevenReachedAt != nil
        let txn = Transaction(
            type: type,
            category: category,
            name: trimmed,
            iconBrandKey: iconBrandKey,
            iconFallbackName: iconFallbackName,
            iconColorHex: iconColorHex,
            originalAmount: originalAmount,
            originalCurrencyCode: originalCurrencyCode,
            note: note,
            date: date,
            project: project,
            sourceCategoryItemID: nil
        )
        context.insert(txn)
        project.stampBreakevenIfReached(in: displayCurrency, fx: fx, triggerDate: date)
        try save()
        try enqueueSync(for: txn)
        try enqueueSync(for: project)

        let reached = !hadReachedBreakEven && project.breakevenReachedAt != nil
        if reached {
            await LocalNotificationScheduler.postBreakeven(
                projectId: project.id,
                projectName: project.name
            )
        }
        return CreateOutcome(transaction: txn, reachedBreakEvenForThisWrite: reached)
    }

    /// Updates an existing transaction in place. The caller mutates by name —
    /// no field-by-field setters here because the form already has the values
    /// it wants to apply.
    @discardableResult
    func updateTransaction(
        _ transaction: Transaction,
        type: TransactionType,
        category: TransactionCategory,
        name: String,
        iconBrandKey: String?,
        iconFallbackName: String?,
        iconColorHex: String?,
        originalAmount: Double,
        originalCurrencyCode: String,
        note: String,
        date: Date,
        displayCurrency: String,
        fx: ExchangeRateService
    ) async throws -> CreateOutcome {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw DataLayerError.invalidInput("Transaction name cannot be empty.")
        }
        guard originalAmount > 0 else {
            throw DataLayerError.invalidInput("Amount must be greater than zero.")
        }
        guard let project = transaction.project else {
            throw DataLayerError.invalidInput("Transaction is missing a project.")
        }

        let hadReachedBreakEven = project.breakevenReachedAt != nil
        transaction.type = type
        transaction.category = category
        transaction.name = trimmed
        transaction.iconBrandKey = iconBrandKey
        transaction.iconFallbackName = iconFallbackName
        transaction.iconColorHex = iconColorHex
        transaction.originalAmount = originalAmount
        transaction.originalCurrencyCode = originalCurrencyCode
        transaction.note = note
        transaction.date = date
        transaction.updatedAt = Date()

        project.stampBreakevenIfReached(in: displayCurrency, fx: fx, triggerDate: date)
        try save()
        try enqueueSync(for: transaction)
        try enqueueSync(for: project)

        let reached = !hadReachedBreakEven && project.breakevenReachedAt != nil
        if reached {
            await LocalNotificationScheduler.postBreakeven(
                projectId: project.id,
                projectName: project.name
            )
        }
        return CreateOutcome(transaction: transaction, reachedBreakEvenForThisWrite: reached)
    }

    /// Creates a platform-fee expense Transaction (Apple / Google).
    @discardableResult
    func createPlatformFee(
        project: Project,
        sourceTransactionName: String,
        sourceCategory: TransactionCategory,
        amount: Double,
        currencyCode: String,
        date: Date,
        vendor: PlatformFeeVendor,
        percent: Double,
        displayCurrency: String,
        fx: ExchangeRateService
    ) async throws -> CreateOutcome {
        let feeAmount = (amount * percent).rounded()
        let noteSource = sourceTransactionName.isEmpty ? sourceCategory.rawValue : sourceTransactionName
        return try await createOneTimeTransaction(
            project: project,
            type: .expense,
            category: vendor.rawCategory,
            name: vendor.feeName,
            iconBrandKey: vendor.brandKey,
            iconFallbackName: nil,
            iconColorHex: nil,
            originalAmount: feeAmount,
            originalCurrencyCode: currencyCode,
            note: String(localized: "來自:\(noteSource)"),
            date: date,
            displayCurrency: displayCurrency,
            fx: fx
        )
    }

    func deleteTransaction(_ transaction: Transaction) async throws {
        let document = TransactionDocument(from: transaction).tombstoned
        context.delete(transaction)
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

    private func enqueueSync(for txn: Transaction) throws {
        let doc = TransactionDocument(from: txn)
        let op = try PendingSyncOperation.make(
            entityId: doc.id,
            kind: .transaction,
            document: doc
        )
        sync.enqueue(op)
    }

    private func enqueueSync(for project: Project) throws {
        let doc = ProjectDocument(from: project)
        let op = try PendingSyncOperation.make(
            entityId: doc.id,
            kind: .project,
            document: doc
        )
        sync.enqueue(op)
    }

    private func enqueueTombstone(_ document: TransactionDocument) throws {
        let op = try PendingSyncOperation.make(
            entityId: document.id,
            kind: .transaction,
            document: document
        )
        sync.enqueue(op)
    }
}

/// Mirrors the small enum that AddTransactionView used to own. Moved out so
/// the repository can drive the platform-fee flow without dragging the view
/// in as a dependency.
enum PlatformFeeVendor: Equatable, Sendable {
    case apple
    case google

    var rawCategory: TransactionCategory {
        switch self {
        case .apple: return .appStoreFee
        case .google: return .googlePlayFee
        }
    }

    var feeName: String {
        switch self {
        case .apple: return String(localized: "Apple 平台抽成")
        case .google: return String(localized: "Google 平台抽成")
        }
    }

    var brandKey: String {
        switch self {
        case .apple: return "apple"
        case .google: return "google"
        }
    }
}

private extension TransactionDocument {
    var tombstoned: TransactionDocument {
        var copy = self
        copy.isDeleted = true
        copy.updatedAt = Date()
        return copy
    }
}
