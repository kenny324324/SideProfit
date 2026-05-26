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
//  - Every mutation it commits — generated transaction, advanced category
//    item, break-even stamp on a project — is enqueued through SyncServicing
//    so Phase 4 sync mirrors recurring-billing state, not just user writes.
//

import Foundation
import SwiftData

enum SubscriptionScheduler {
    /// Calendar pinned to UTC Gregorian for deterministic-id day math. Two
    /// devices in different regions firing the scheduler for the same due
    /// date must converge on the same id, otherwise Firestore dedupes
    /// nothing and the same recurring charge ends up duplicated remotely.
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    /// Format the deterministic Transaction id stamped on every
    /// scheduler-generated row. Day boundary is computed in UTC so devices
    /// across timezones produce the same id for the same due date.
    static func deterministicTransactionID(
        categoryItemID: UUID,
        projectID: UUID,
        date: Date,
        calendar: Calendar = utcCalendar
    ) -> String {
        let day = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let y = components.year ?? 0
        let m = components.month ?? 0
        let d = components.day ?? 0
        let dayString = String(format: "%04d%02d%02d", y, m, d)
        return "\(categoryItemID.uuidString)_\(projectID.uuidString)_\(dayString)"
    }

    /// Idempotency guard: a Transaction is considered "already created for
    /// this due date" if it carries the same `sourceCategoryItemID` and its
    /// `date` falls on the same calendar day as the due date for that project.
    /// Prevents duplicate fires if the scheduler runs twice on the same day.
    @MainActor
    static func runDueCheck(
        context: ModelContext,
        sync: SyncServicing,
        displayCurrency: String,
        fx: ExchangeRateService,
        now: Date = Date()
    ) throws {
        let descriptor = FetchDescriptor<CategoryItem>(
            predicate: #Predicate<CategoryItem> { item in
                item.isActive && item.nextDueDate != nil
            }
        )
        let items: [CategoryItem]
        do {
            items = try context.fetch(descriptor)
        } catch {
            throw DataLayerError.localSaveFailed(underlying: error)
        }

        var generatedTransactions: [Transaction] = []
        var touchedItems: [UUID: CategoryItem] = [:]
        var touchedProjects: [UUID: Project] = [:]
        // Idempotency check inside the catch-up loop reads back what we just
        // inserted in earlier iterations, so the local-day boundary still
        // uses the device's calendar — that's a per-device concern.
        let cal = Calendar.current

        for item in items {
            guard item.billingType.isRecurring else { continue }
            // Catch-up loop: fire as many times as needed to reach today.
            while let due = item.nextDueDate, due <= now {
                let result = generateTransactions(
                    for: item,
                    on: due,
                    context: context,
                    calendar: cal,
                    displayCurrency: displayCurrency,
                    fx: fx
                )
                generatedTransactions.append(contentsOf: result.transactions)
                for project in result.touchedProjects {
                    touchedProjects[project.id] = project
                }
                if !result.transactions.isEmpty {
                    touchedItems[item.id] = item
                }
                item.advanceDueDate()
                // Safety: bail if the model never advances (e.g. corrupted enum).
                if item.nextDueDate == due { break }
            }
        }

        let didMutate = !generatedTransactions.isEmpty
            || !touchedItems.isEmpty
            || !touchedProjects.isEmpty
        guard didMutate else { return }

        do {
            try context.save()
        } catch {
            throw DataLayerError.localSaveFailed(underlying: error)
        }

        // Snapshot AFTER save so DTOs reflect the persisted state. Errors here
        // mean the local write succeeded but the sync queue didn't get the
        // mirror — caller still surfaces it, but Phase 4 sync can also recover
        // by diffing against the remote on the next pass.
        for txn in generatedTransactions {
            try enqueueTransaction(txn, sync: sync)
        }
        for item in touchedItems.values {
            try enqueueCategoryItem(item, sync: sync)
        }
        for project in touchedProjects.values {
            try enqueueProject(project, sync: sync)
        }
    }

    private struct FireResult {
        let transactions: [Transaction]
        let touchedProjects: [Project]
    }

    @MainActor
    private static func generateTransactions(
        for item: CategoryItem,
        on date: Date,
        context: ModelContext,
        calendar: Calendar,
        displayCurrency: String,
        fx: ExchangeRateService
    ) -> FireResult {
        let allocation = item.projects ?? []
        guard !allocation.isEmpty else { return FireResult(transactions: [], touchedProjects: []) }

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
        if !existing.isEmpty { return FireResult(transactions: [], touchedProjects: []) }

        let type = item.transactionType
        let category = item.category
        let name = item.name
        let currency = item.originalCurrencyCode
        let brandKey = item.brandIconKey
        let fallbackIcon = item.fallbackIconName
        let colorHex = item.iconColorHex

        var generated: [Transaction] = []
        var touched: [Project] = []
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
                sourceCategoryItemID: item.id,
                deterministicID: deterministicTransactionID(
                    categoryItemID: item.id,
                    projectID: project.id,
                    date: date
                )
            )
            context.insert(txn)
            let hadReachedBefore = project.breakevenReachedAt != nil
            project.stampBreakevenIfReached(in: displayCurrency, fx: fx, triggerDate: date)
            generated.append(txn)
            // A project counts as "touched" both when a generated transaction
            // is attached to it AND when its break-even stamp flipped. Either
            // way the remote document needs a new push.
            if !touched.contains(where: { $0.id == project.id }) {
                touched.append(project)
            }
            _ = hadReachedBefore
        }
        return FireResult(transactions: generated, touchedProjects: touched)
    }

    @MainActor
    private static func enqueueTransaction(_ transaction: Transaction, sync: SyncServicing) throws {
        let doc = TransactionDocument(from: transaction)
        let op = try PendingSyncOperation.make(
            entityId: doc.id,
            kind: .transaction,
            document: doc
        )
        sync.enqueue(op)
    }

    @MainActor
    private static func enqueueCategoryItem(_ item: CategoryItem, sync: SyncServicing) throws {
        let doc = CategoryItemDocument(from: item)
        let op = try PendingSyncOperation.make(
            entityId: doc.id,
            kind: .categoryItem,
            document: doc
        )
        sync.enqueue(op)
    }

    @MainActor
    private static func enqueueProject(_ project: Project, sync: SyncServicing) throws {
        let doc = ProjectDocument(from: project)
        let op = try PendingSyncOperation.make(
            entityId: doc.id,
            kind: .project,
            document: doc
        )
        sync.enqueue(op)
    }
}
