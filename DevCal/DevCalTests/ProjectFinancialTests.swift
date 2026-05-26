//
//  ProjectFinancialTests.swift
//  DevCalTests
//
//  Locks down the Project aggregation + two-stage progress math so Phase 4
//  Firestore mirroring can't quietly drift the numbers users see.
//

import Testing
import Foundation
import SwiftData
@testable import DevCal

@MainActor
struct ProjectFinancialTests {

    // MARK: - Helpers

    /// Builds an in-memory ModelContainer with all five SwiftData models.
    /// Each test gets its own fresh container so they can't pollute each other.
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

    private func makeFX() -> ExchangeRateService {
        // Baseline rates are pre-seeded in the init; we don't hit the network
        // during tests.
        ExchangeRateService()
    }

    private func addTxn(
        to project: Project,
        type: TransactionType,
        amount: Double,
        currency: String = "TWD",
        date: Date = Date(),
        in context: ModelContext
    ) {
        let txn = Transaction(
            type: type,
            category: type == .income ? .appSales : .server,
            name: "test",
            originalAmount: amount,
            originalCurrencyCode: currency,
            date: date,
            project: project
        )
        context.insert(txn)
    }

    // MARK: - Totals

    @Test("totalIncome / totalExpenses / netProfit aggregate single-currency rows")
    func singleCurrencyTotals() throws {
        let context = try makeContext()
        let fx = makeFX()
        let project = Project(name: "A")
        context.insert(project)

        addTxn(to: project, type: .income, amount: 1000, in: context)
        addTxn(to: project, type: .income, amount: 500, in: context)
        addTxn(to: project, type: .expense, amount: 300, in: context)
        addTxn(to: project, type: .expense, amount: 200, in: context)

        #expect(project.totalIncome(in: "TWD", fx: fx) == 1500)
        #expect(project.totalExpenses(in: "TWD", fx: fx) == 500)
        #expect(project.netProfit(in: "TWD", fx: fx) == 1000)
    }

    @Test("Totals convert mixed currencies into the display currency")
    func multiCurrencyTotals() throws {
        let context = try makeContext()
        let fx = makeFX()
        let project = Project(name: "B")
        context.insert(project)

        // 1000 TWD income, and 10 USD income. The actual rate depends on the
        // ExchangeRateService cache, so compute the expected value via the
        // same fx to assert aggregation calls convert correctly without
        // hardcoding a specific rate.
        addTxn(to: project, type: .income, amount: 1000, currency: "TWD", in: context)
        addTxn(to: project, type: .income, amount: 10, currency: "USD", in: context)

        let usdInTwd = fx.convert(10, from: "USD", to: "TWD") ?? 0
        let total = project.totalIncome(in: "TWD", fx: fx)
        #expect(abs(total - (1000 + usdInTwd)) < 1e-6)
        #expect(usdInTwd > 0) // sanity: fx returned a real number
    }

    // MARK: - Progress + break-even stamping

    @Test("Stage 1 progress = income / expenses, capped 0...1")
    func stageOneProgressClamps() throws {
        let context = try makeContext()
        let fx = makeFX()
        let project = Project(name: "C")
        context.insert(project)

        addTxn(to: project, type: .expense, amount: 1000, in: context)
        addTxn(to: project, type: .income, amount: 250, in: context)

        #expect(project.stage == .stageOne)
        #expect(abs(project.progress(in: "TWD", fx: fx) - 0.25) < 1e-9)
    }

    @Test("Just-reached stage shows full progress without a goal")
    func justReachedProgress() throws {
        let context = try makeContext()
        let fx = makeFX()
        let project = Project(name: "D")
        context.insert(project)

        addTxn(to: project, type: .expense, amount: 100, in: context)
        addTxn(to: project, type: .income, amount: 100, in: context)
        project.stampBreakevenIfReached(in: "TWD", fx: fx)

        #expect(project.breakevenReachedAt != nil)
        #expect(project.stage == .justReached)
        #expect(project.progress(in: "TWD", fx: fx) == 1)
    }

    @Test("Stage 2 progress = income / goal once a goal is set")
    func stageTwoProgress() throws {
        let context = try makeContext()
        let fx = makeFX()
        let project = Project(name: "E")
        context.insert(project)

        addTxn(to: project, type: .expense, amount: 100, in: context)
        addTxn(to: project, type: .income, amount: 600, in: context)
        project.stampBreakevenIfReached(in: "TWD", fx: fx)
        project.goalAmount = 1000
        project.goalCurrencyCode = "TWD"

        #expect(project.stage == .stageTwo)
        #expect(abs(project.progress(in: "TWD", fx: fx) - 0.6) < 1e-9)
    }

    @Test("Break-even stamp fires only on first crossing and is never cleared")
    func breakevenStampIsOneShot() throws {
        let context = try makeContext()
        let fx = makeFX()
        let project = Project(name: "F")
        context.insert(project)

        // Below threshold — no stamp.
        addTxn(to: project, type: .expense, amount: 100, in: context)
        addTxn(to: project, type: .income, amount: 50, in: context)
        project.stampBreakevenIfReached(in: "TWD", fx: fx)
        #expect(project.breakevenReachedAt == nil)

        // Tip over — stamp now happens.
        addTxn(to: project, type: .income, amount: 75, in: context)
        let firstStampTrigger = Date(timeIntervalSince1970: 100_000)
        project.stampBreakevenIfReached(in: "TWD", fx: fx, triggerDate: firstStampTrigger)
        #expect(project.breakevenReachedAt == firstStampTrigger)

        // Further writes don't move the stamp.
        addTxn(to: project, type: .income, amount: 9999, in: context)
        let secondStampTrigger = Date(timeIntervalSince1970: 200_000)
        project.stampBreakevenIfReached(in: "TWD", fx: fx, triggerDate: secondStampTrigger)
        #expect(project.breakevenReachedAt == firstStampTrigger)

        // Even if expenses later overtake income again, the stamp stays.
        addTxn(to: project, type: .expense, amount: 100_000, in: context)
        project.stampBreakevenIfReached(in: "TWD", fx: fx)
        #expect(project.breakevenReachedAt == firstStampTrigger)
    }
}
