//
//  TransactionUseCase.swift
//  DevCal
//
//  Coordinates the multi-step transaction flows that used to live inside
//  AddTransactionView:
//  - One-time write (+ optional platform-fee follow-up).
//  - Subscription write: creates a hidden CategoryItem and runs the scheduler
//    so back-dated subscriptions catch up immediately.
//
//  The view passes raw form values through `TransactionFormInput`; the use
//  case owns the orchestration and returns a small `TransactionSaveOutcome`
//  that captures everything the view still needs to do (show platform-fee
//  alerts, record app-review triggers).
//

import Foundation
import SwiftData

@MainActor
final class TransactionUseCase {
    let transactionRepository: TransactionRepository
    let categoryItemRepository: CategoryItemRepository
    private let context: ModelContext

    init(
        context: ModelContext,
        transactionRepository: TransactionRepository,
        categoryItemRepository: CategoryItemRepository
    ) {
        self.context = context
        self.transactionRepository = transactionRepository
        self.categoryItemRepository = categoryItemRepository
    }

    // MARK: - Inputs / outputs

    struct TransactionFormInput {
        var project: Project
        var type: TransactionType
        var category: TransactionCategory
        var name: String
        var iconBrandKey: String?
        var iconFallbackName: String?
        var iconColorHex: String?
        var originalAmount: Double
        var originalCurrencyCode: String
        var note: String
        var date: Date
        var billingType: BillingType
        var nextDueDate: Date
    }

    /// What the view should do once the save completes.
    struct TransactionSaveOutcome {
        /// `true` when the user just earned the break-even moment — view feeds
        /// this into the app-review prompter.
        let reachedBreakEvenForThisWrite: Bool
        /// `true` when the saved transaction is platform-fee-eligible income
        /// (appSales / subscriptions). View shows the vendor / percent alerts.
        let shouldOfferPlatformFee: Bool
    }

    // MARK: - Save flows

    /// Used when the form is creating a brand-new transaction.
    func save(_ input: TransactionFormInput, displayCurrency: String, fx: ExchangeRateService) async throws -> TransactionSaveOutcome {
        if input.billingType.isRecurring {
            return try await saveSubscription(input, displayCurrency: displayCurrency, fx: fx)
        }
        return try await saveOneTime(input, displayCurrency: displayCurrency, fx: fx)
    }

    /// Used when editing an existing transaction. Skips the billing fork (the
    /// view only allows editing one-time / non-billing fields) and never
    /// offers platform fees.
    func update(
        _ transaction: Transaction,
        with input: TransactionFormInput,
        displayCurrency: String,
        fx: ExchangeRateService
    ) async throws -> TransactionSaveOutcome {
        let outcome = try await transactionRepository.updateTransaction(
            transaction,
            type: input.type,
            category: input.category,
            name: input.name,
            iconBrandKey: input.iconBrandKey,
            iconFallbackName: input.iconFallbackName,
            iconColorHex: input.iconColorHex,
            originalAmount: input.originalAmount,
            originalCurrencyCode: input.originalCurrencyCode,
            note: input.note,
            date: input.date,
            displayCurrency: displayCurrency,
            fx: fx
        )
        return TransactionSaveOutcome(
            reachedBreakEvenForThisWrite: outcome.reachedBreakEvenForThisWrite,
            shouldOfferPlatformFee: false
        )
    }

    func delete(_ transaction: Transaction) async throws {
        try await transactionRepository.deleteTransaction(transaction)
    }

    /// Followup write the view kicks off after the platform-fee alert.
    /// Returns whether the fee write itself pushed the project over break-even
    /// (rare but possible if the original income alone wasn't enough).
    func createPlatformFee(
        for input: TransactionFormInput,
        vendor: PlatformFeeVendor,
        percent: Double,
        displayCurrency: String,
        fx: ExchangeRateService
    ) async throws -> Bool {
        let outcome = try await transactionRepository.createPlatformFee(
            project: input.project,
            sourceTransactionName: input.name,
            sourceCategory: input.category,
            amount: input.originalAmount,
            currencyCode: input.originalCurrencyCode,
            date: input.date,
            vendor: vendor,
            percent: percent,
            displayCurrency: displayCurrency,
            fx: fx
        )
        return outcome.reachedBreakEvenForThisWrite
    }

    // MARK: - Private flows

    private func saveOneTime(_ input: TransactionFormInput, displayCurrency: String, fx: ExchangeRateService) async throws -> TransactionSaveOutcome {
        let result = try await transactionRepository.createOneTimeTransaction(
            project: input.project,
            type: input.type,
            category: input.category,
            name: input.name,
            iconBrandKey: input.iconBrandKey,
            iconFallbackName: input.iconFallbackName,
            iconColorHex: input.iconColorHex,
            originalAmount: input.originalAmount,
            originalCurrencyCode: input.originalCurrencyCode,
            note: input.note,
            date: input.date,
            displayCurrency: displayCurrency,
            fx: fx
        )

        let offerFee = input.type == .income
            && (input.category == .appSales || input.category == .subscriptions)
        return TransactionSaveOutcome(
            reachedBreakEvenForThisWrite: result.reachedBreakEvenForThisWrite,
            shouldOfferPlatformFee: offerFee
        )
    }

    private func saveSubscription(_ input: TransactionFormInput, displayCurrency: String, fx: ExchangeRateService) async throws -> TransactionSaveOutcome {
        // Subscriptions don't go through TransactionRepository directly. The
        // hidden CategoryItem holds the recurring rule; the scheduler emits
        // the actual Transactions (including any past periods to catch up).
        let categoryItemInput = CategoryItemRepository.CategoryItemInput(
            name: input.name,
            category: input.category,
            totalAmount: input.originalAmount,
            originalCurrencyCode: input.originalCurrencyCode,
            billingType: input.billingType,
            brandIconKey: input.iconBrandKey,
            fallbackIconName: input.iconFallbackName,
            iconColorHex: input.iconColorHex,
            nextDueDate: input.nextDueDate,
            isActive: true,
            isShared: false,
            splitMode: .equal,
            weightsByProjectId: nil,
            projects: [input.project]
        )

        let hadReachedBreakEven = input.project.breakevenReachedAt != nil
        _ = try await categoryItemRepository.createCategoryItem(categoryItemInput)
        SubscriptionScheduler.runDueCheck(
            context: context,
            displayCurrency: displayCurrency,
            fx: fx
        )
        let reached = !hadReachedBreakEven && input.project.breakevenReachedAt != nil
        return TransactionSaveOutcome(
            reachedBreakEvenForThisWrite: reached,
            shouldOfferPlatformFee: false
        )
    }
}
