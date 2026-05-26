//
//  AuthServiceTests.swift
//  DevCalTests
//
//  Phase 1 coverage for the static account-deletion pipeline. Exercises
//  `AuthService.purgeLocalData(_:)` directly so we can prove the tombstones
//  enqueued into Phase 4 sync are accurate, without needing FirebaseApp
//  configured in the test bundle.
//
//  TODO(phase-2+): wrap `Auth.auth()` calls in a protocol shim so the full
//  `signInWithApple()` / `signOut()` / `deleteAccount(localPurge:)` flow can
//  be tested with a fake. Phase 1 ships with the static-purge coverage only
//  because (a) Sign in with Apple needs a real Apple credential to exercise
//  end-to-end, and (b) instantiating `AuthService` from a test target
//  requires `FirebaseApp.configure()` — out of scope for this phase.
//

import Testing
import Foundation
import SwiftData
@testable import DevCal

@MainActor
struct AuthServiceTests {

    // MARK: - Helpers

    /// Builds an in-memory ModelContainer with every model the repos touch,
    /// plus the four Phase 0 repositories pre-wired against a fresh
    /// NoopSyncService so the test can inspect every enqueued operation.
    private struct Harness {
        let context: ModelContext
        let sync: NoopSyncService
        let project: ProjectRepository
        let transaction: TransactionRepository
        let timeLog: TimeLogRepository
        let categoryItem: CategoryItemRepository

        var purgeContext: AuthService.AccountPurgeContext {
            AuthService.AccountPurgeContext(
                modelContext: context,
                project: project,
                transaction: transaction,
                timeLog: timeLog,
                categoryItem: categoryItem
            )
        }
    }

    private func makeHarness() throws -> Harness {
        let schema = Schema([
            Project.self,
            Transaction.self,
            TimeLog.self,
            Milestone.self,
            CategoryItem.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let sync = NoopSyncService()
        return Harness(
            context: context,
            sync: sync,
            project: ProjectRepository(context: context, sync: sync),
            transaction: TransactionRepository(context: context, sync: sync),
            timeLog: TimeLogRepository(context: context, sync: sync),
            categoryItem: CategoryItemRepository(context: context, sync: sync)
        )
    }

    /// Seeds 2 projects, 3 transactions, 2 time logs, 1 category item. Returns
    /// the count of each entity so the assertions stay accurate even if the
    /// shape of this helper drifts.
    @discardableResult
    private func seed(_ h: Harness) throws -> (projects: Int, txns: Int, logs: Int, items: Int) {
        let alpha = Project(name: "Alpha")
        let beta = Project(name: "Beta")
        h.context.insert(alpha)
        h.context.insert(beta)

        let t1 = Transaction(
            type: .income,
            category: .appSales,
            name: "Sale",
            originalAmount: 100,
            originalCurrencyCode: "USD",
            date: Date(),
            project: alpha
        )
        let t2 = Transaction(
            type: .expense,
            category: .server,
            name: "Hosting",
            originalAmount: 9.99,
            originalCurrencyCode: "USD",
            date: Date(),
            project: alpha
        )
        let t3 = Transaction(
            type: .income,
            category: .appSales,
            name: "Sale2",
            originalAmount: 50,
            originalCurrencyCode: "USD",
            date: Date(),
            project: beta
        )
        h.context.insert(t1)
        h.context.insert(t2)
        h.context.insert(t3)

        let l1 = TimeLog(
            hours: 2,
            hourlyRate: 50,
            hourlyCurrencyCode: "USD",
            note: "design",
            date: Date(),
            project: alpha
        )
        let l2 = TimeLog(
            hours: 4,
            hourlyRate: 50,
            hourlyCurrencyCode: "USD",
            note: "code",
            date: Date(),
            project: beta
        )
        h.context.insert(l1)
        h.context.insert(l2)

        let item = CategoryItem(
            name: "ChatGPT",
            category: .aiTools,
            totalAmount: 20,
            originalCurrencyCode: "USD",
            billingType: .monthly,
            isShared: true,
            splitMode: .equal,
            projects: [alpha, beta]
        )
        h.context.insert(item)
        try h.context.save()

        return (projects: 2, txns: 3, logs: 2, items: 1)
    }

    // MARK: - Tests

    @Test("purgeLocalData wipes every local record")
    func purgeWipesEverything() async throws {
        let h = try makeHarness()
        _ = try seed(h)

        try await AuthService.purgeLocalData(h.purgeContext)

        #expect(try h.context.fetch(FetchDescriptor<Transaction>()).isEmpty)
        #expect(try h.context.fetch(FetchDescriptor<TimeLog>()).isEmpty)
        #expect(try h.context.fetch(FetchDescriptor<CategoryItem>()).isEmpty)
        #expect(try h.context.fetch(FetchDescriptor<Project>()).isEmpty)
    }

    @Test("purgeLocalData enqueues a tombstone op for every entity")
    func purgeEnqueuesTombstones() async throws {
        let h = try makeHarness()
        let counts = try seed(h)
        // Seed inserts go through `context.insert` directly, not through the
        // repos — so the sync queue is empty at this point. Anything we see
        // after the purge call came from the delete path.
        #expect(h.sync.recentlyEnqueued.isEmpty)

        try await AuthService.purgeLocalData(h.purgeContext)

        let expectedTotal = counts.projects + counts.txns + counts.logs + counts.items
        #expect(h.sync.recentlyEnqueued.count == expectedTotal)

        let projectOps = h.sync.recentlyEnqueued.filter { $0.kind == .project }
        let txnOps = h.sync.recentlyEnqueued.filter { $0.kind == .transaction }
        let logOps = h.sync.recentlyEnqueued.filter { $0.kind == .timeLog }
        let itemOps = h.sync.recentlyEnqueued.filter { $0.kind == .categoryItem }
        #expect(projectOps.count == counts.projects)
        #expect(txnOps.count == counts.txns)
        #expect(logOps.count == counts.logs)
        #expect(itemOps.count == counts.items)

        // Every payload must decode with isDeleted = true — that's the bit
        // Phase 4 sync will check before issuing a Firestore delete.
        for op in projectOps {
            let doc = try JSONDecoder.devcalSync.decode(ProjectDocument.self, from: op.payload)
            #expect(doc.isDeleted == true)
        }
        for op in txnOps {
            let doc = try JSONDecoder.devcalSync.decode(TransactionDocument.self, from: op.payload)
            #expect(doc.isDeleted == true)
        }
        for op in logOps {
            let doc = try JSONDecoder.devcalSync.decode(TimeLogDocument.self, from: op.payload)
            #expect(doc.isDeleted == true)
        }
        for op in itemOps {
            let doc = try JSONDecoder.devcalSync.decode(CategoryItemDocument.self, from: op.payload)
            #expect(doc.isDeleted == true)
        }
    }

    @Test("purgeLocalData is safe to run on an empty store")
    func purgeEmptyStore() async throws {
        let h = try makeHarness()

        try await AuthService.purgeLocalData(h.purgeContext)

        #expect(h.sync.recentlyEnqueued.isEmpty)
        #expect(try h.context.fetch(FetchDescriptor<Project>()).isEmpty)
    }
}
