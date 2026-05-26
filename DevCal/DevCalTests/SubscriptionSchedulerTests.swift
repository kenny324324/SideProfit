//
//  SubscriptionSchedulerTests.swift
//  DevCalTests
//
//  Covers the recurring-billing generator: a single due fire, multi-period
//  catch-up, same-day idempotency, deterministic id stamping (with the
//  Firestore-required UTC day boundary), and the sync enqueue contract that
//  Phase 4 will rely on.
//

import Testing
import Foundation
import SwiftData
@testable import DevCal

@MainActor
struct SubscriptionSchedulerTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Project.self,
            Transaction.self,
            TimeLog.self,
            Milestone.self,
            CategoryItem.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    private func makeFX() -> ExchangeRateService { ExchangeRateService() }
    private func makeSync() -> NoopSyncService { NoopSyncService() }

    private func fetchTransactions(_ context: ModelContext) throws -> [Transaction] {
        try context.fetch(FetchDescriptor<Transaction>())
    }

    // MARK: - Basic firing

    @Test("Due monthly subscription produces one transaction per project")
    func firesOneTransaction() throws {
        let context = try makeContext()
        let fx = makeFX()
        let sync = makeSync()
        let project = Project(name: "A"); context.insert(project)

        let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        let item = CategoryItem(
            name: "ChatGPT",
            category: .aiTools,
            totalAmount: 500,
            billingType: .monthly,
            nextDueDate: dueDate,
            projects: [project]
        )
        context.insert(item)

        try SubscriptionScheduler.runDueCheck(
            context: context,
            sync: sync,
            displayCurrency: "TWD",
            fx: fx,
            now: dueDate.addingTimeInterval(60)
        )

        let txns = try fetchTransactions(context)
        #expect(txns.count == 1)
        #expect(txns.first?.sourceCategoryItemID == item.id)
        #expect(txns.first?.originalAmount == 500)
        #expect(txns.first?.deterministicID != nil)
    }

    @Test("Catch-up loop fires once per missed billing period")
    func catchesUpMultiplePeriods() throws {
        let context = try makeContext()
        let fx = makeFX()
        let sync = makeSync()
        let project = Project(name: "A"); context.insert(project)

        // Start date is 3 months ago. The scheduler should fire 4 times to
        // catch up to "now" (the original due + 1 per month past).
        let cal = Calendar.current
        let now = Date()
        guard let start = cal.date(byAdding: .month, value: -3, to: now) else {
            Issue.record("Unable to compute past date for test")
            return
        }
        let item = CategoryItem(
            name: "monthly",
            category: .aiTools,
            totalAmount: 100,
            billingType: .monthly,
            nextDueDate: start,
            projects: [project]
        )
        context.insert(item)

        try SubscriptionScheduler.runDueCheck(
            context: context,
            sync: sync,
            displayCurrency: "TWD",
            fx: fx,
            now: now
        )

        let txns = try fetchTransactions(context)
        // 4 fires expected: month -3, -2, -1, 0.
        #expect(txns.count == 4)
    }

    @Test("Re-running the scheduler on the same day does not duplicate")
    func idempotentSameDay() throws {
        let context = try makeContext()
        let fx = makeFX()
        let sync = makeSync()
        let project = Project(name: "A"); context.insert(project)

        let now = Date()
        let item = CategoryItem(
            name: "monthly",
            category: .aiTools,
            totalAmount: 100,
            billingType: .monthly,
            nextDueDate: now,
            projects: [project]
        )
        context.insert(item)

        try SubscriptionScheduler.runDueCheck(context: context, sync: sync, displayCurrency: "TWD", fx: fx, now: now)
        let firstCount = try fetchTransactions(context).count

        // Force the item's nextDueDate back to today so the loop would WANT
        // to fire again, then verify the existing-row check stops it.
        item.nextDueDate = now
        try SubscriptionScheduler.runDueCheck(context: context, sync: sync, displayCurrency: "TWD", fx: fx, now: now)
        let secondCount = try fetchTransactions(context).count

        #expect(firstCount == secondCount)
    }

    @Test("Break-even is stamped when a scheduler fire tips a project over")
    func schedulerStampsBreakEven() throws {
        let context = try makeContext()
        let fx = makeFX()
        let sync = makeSync()
        let project = Project(name: "A"); context.insert(project)

        // Pre-existing expenses so the next income tips it over.
        let expense = Transaction(
            type: .expense,
            category: .server,
            name: "AWS",
            originalAmount: 200,
            originalCurrencyCode: "TWD",
            date: Date().addingTimeInterval(-3600),
            project: project
        )
        context.insert(expense)

        let due = Date()
        let item = CategoryItem(
            name: "salesPlatform",
            category: .appSales,
            totalAmount: 1000,
            billingType: .monthly,
            nextDueDate: due,
            projects: [project]
        )
        context.insert(item)

        #expect(project.breakevenReachedAt == nil)
        try SubscriptionScheduler.runDueCheck(context: context, sync: sync, displayCurrency: "TWD", fx: fx, now: due)
        #expect(project.breakevenReachedAt != nil)
    }

    // MARK: - Sync enqueue contract

    @Test("A fired due check enqueues transaction + categoryItem + project ops")
    func enqueuesAcrossAllThreeEntityKinds() throws {
        let context = try makeContext()
        let fx = makeFX()
        let sync = makeSync()
        let project = Project(name: "A"); context.insert(project)

        let due = Date(timeIntervalSince1970: 1_700_000_000)
        let item = CategoryItem(
            name: "AI tools",
            category: .aiTools,
            totalAmount: 200,
            billingType: .monthly,
            nextDueDate: due,
            projects: [project]
        )
        context.insert(item)

        try SubscriptionScheduler.runDueCheck(
            context: context,
            sync: sync,
            displayCurrency: "TWD",
            fx: fx,
            now: due
        )

        let kinds = Set(sync.recentlyEnqueued.map(\.kind))
        #expect(kinds.contains(.transaction))
        #expect(kinds.contains(.categoryItem))
        #expect(kinds.contains(.project))
    }

    // MARK: - Deterministic id

    @Test("Deterministic id format is stable and same-day idempotent")
    func deterministicIDFormat() {
        let categoryId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let projectId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        // Use a stable calendar to avoid the host machine's tz drifting the day.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_700_006_400) // 2023-11-15 00:00 UTC

        let id = SubscriptionScheduler.deterministicTransactionID(
            categoryItemID: categoryId,
            projectID: projectId,
            date: date,
            calendar: cal
        )
        #expect(id == "\(categoryId.uuidString)_\(projectId.uuidString)_20231115")

        // A later instant on the same calendar day yields the same id.
        let sameDayLater = date.addingTimeInterval(3600)
        let id2 = SubscriptionScheduler.deterministicTransactionID(
            categoryItemID: categoryId,
            projectID: projectId,
            date: sameDayLater,
            calendar: cal
        )
        #expect(id == id2)
    }

}
