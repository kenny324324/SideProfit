//
//  SubscriptionScheduler.swift
//  DevCal
//
//  Generates Transactions for recurring CategoryItems whose `nextDueDate` has
//  arrived. Runs on app launch and on every scenePhase → .active transition.
//
//  Behavior:
//  - Skips one-time items (their nextDueDate is set to nil after first fire).
//  - For each due recurring item, may need to fire multiple times if the app
//    has been closed for several billing periods (catch-up loop).
//  - For shared items, produces N transactions — one per project in the
//    allocation list — at each project's split share.
//  - For dedicated items, produces 1 transaction for the single project.
//  - Each generated Transaction snapshots the CategoryItem's `name`, brand /
//    icon / color, and currency at fire time. Editing the CategoryItem later
//    won't retroactively change past transactions — that's intentional.
//

import Foundation
import SwiftData

enum SubscriptionScheduler {
    /// Idempotency guard: a Transaction is considered "already created for
    /// this due date" if it carries the same `sourceCategoryItemID` and its
    /// `date` falls on the same calendar day as the due date for that project.
    /// Prevents duplicate fires if the scheduler runs twice on the same day.
    @MainActor
    static func runDueCheck(
        context: ModelContext,
        displayCurrency: String,
        fx: ExchangeRateService,
        now: Date = Date()
    ) {
        let descriptor = FetchDescriptor<CategoryItem>(
            predicate: #Predicate<CategoryItem> { item in
                item.isActive && item.nextDueDate != nil
            }
        )
        guard let items = try? context.fetch(descriptor) else { return }

        var didMutate = false
        let cal = Calendar.current

        for item in items {
            guard item.billingType.isRecurring else { continue }
            // Catch-up loop: fire as many times as needed to reach today.
            while let due = item.nextDueDate, due <= now {
                generateTransactions(
                    for: item,
                    on: due,
                    context: context,
                    calendar: cal,
                    displayCurrency: displayCurrency,
                    fx: fx
                )
                item.advanceDueDate()
                didMutate = true
                // Safety: bail if the model never advances (e.g. corrupted enum).
                if item.nextDueDate == due { break }
            }
        }

        if didMutate {
            try? context.save()
        }
    }

    @MainActor
    private static func generateTransactions(
        for item: CategoryItem,
        on date: Date,
        context: ModelContext,
        calendar: Calendar,
        displayCurrency: String,
        fx: ExchangeRateService
    ) {
        let allocation = item.projects ?? []
        guard !allocation.isEmpty else { return }

        let itemID = item.id
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        // Check for any existing transaction sourced from this item on this
        // calendar day. If found, the scheduler already ran for this period.
        let existing = (try? context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { txn in
                txn.sourceCategoryItemID == itemID
                    && txn.date >= dayStart
                    && txn.date < dayEnd
            }
        ))) ?? []
        if !existing.isEmpty { return }

        let type = item.transactionType
        let category = item.category
        let name = item.name
        let currency = item.originalCurrencyCode
        let brandKey = item.brandIconKey
        let fallbackIcon = item.fallbackIconName
        let colorHex = item.iconColorHex

        for project in allocation {
            let amount = item.amount(for: project)
            guard amount > 0 else { continue }
            let txn = Transaction(
                type: type,
                category: category,
                name: name,
                iconBrandKey: brandKey,
                iconFallbackName: fallbackIcon,
                iconColorHex: colorHex,
                originalAmount: amount,
                originalCurrencyCode: currency,
                note: "",
                date: date,
                project: project,
                sourceCategoryItemID: item.id
            )
            context.insert(txn)
            project.stampBreakevenIfReached(in: displayCurrency, fx: fx, triggerDate: date)
        }
    }
}
