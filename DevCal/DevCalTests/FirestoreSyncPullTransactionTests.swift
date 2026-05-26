//
//  FirestoreSyncPullTransactionTests.swift
//  DevCalTests
//
//  Step 4 pull coverage for the `Transaction` entity kind. Beyond the
//  shape-matched LWW + tombstone cases, this file proves that a pulled
//  Transaction hydrates its `project` relationship via the projectId
//  lookup — both when the parent Project already exists locally and when
//  it doesn't yet (orphaned case, nil relationship).
//

import Testing
import Foundation
import SwiftData
@testable import DevCal

@MainActor
struct FirestoreSyncPullTransactionTests {

    // MARK: - Helpers

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

    private func makeTempQueueURL() -> URL {
        let dir = URL.temporaryDirectory.appendingPathComponent(
            "FirestoreSyncPullTransactionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-queue.json", isDirectory: false)
    }

    private func makeTransactionDoc(
        id: UUID = UUID(),
        projectId: String? = nil,
        name: String = "Cursor Pro",
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_500),
        isDeleted: Bool = false
    ) -> TransactionDocument {
        TransactionDocument(
            id: id.uuidString,
            projectId: projectId,
            typeRaw: "expense",
            categoryRaw: "subscription",
            name: name,
            iconBrandKey: nil,
            iconFallbackName: nil,
            iconColorHex: nil,
            originalAmount: 199,
            originalCurrencyCode: "USD",
            note: "",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: updatedAt,
            sourceCategoryItemId: nil,
            deterministicId: nil,
            isDeleted: isDeleted
        )
    }

    private func makeService(
        context: ModelContext,
        reader: MockRemoteReader
    ) -> FirestoreSyncService {
        FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: MockRemoteWriter(),
            reader: reader,
            modelContext: context
        )
    }

    // MARK: - upsert: hydrates project relationship

    @Test("upsertTransaction sets the project relationship when parent exists locally")
    func upsertHydratesProjectRelationship() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())

        let projectId = UUID()
        let project = Project(name: "Parent")
        project.id = projectId
        context.insert(project)
        try context.save()

        let doc = makeTransactionDoc(projectId: projectId.uuidString)

        try service.upsertTransaction(doc, context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        #expect(all.first?.project?.id == projectId)
    }

    @Test("upsertTransaction leaves project nil when parent is missing")
    func upsertOrphanedTransactionHasNilProject() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())

        let doc = makeTransactionDoc(projectId: UUID().uuidString)

        try service.upsertTransaction(doc, context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1)
        #expect(all.first?.project == nil)
    }

    // MARK: - upsert: LWW

    @Test("upsertTransaction applies remote when remote.updatedAt is newer")
    func upsertAppliesNewerRemote() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = Transaction(name: "Local name")
        local.id = id
        local.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(local)
        try context.save()

        let doc = makeTransactionDoc(
            id: id,
            name: "Remote name",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )

        try service.upsertTransaction(doc, context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        #expect(all.first?.name == "Remote name")
    }

    @Test("upsertTransaction keeps local when local.updatedAt is newer")
    func upsertKeepsNewerLocal() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = Transaction(name: "Local wins")
        local.id = id
        local.updatedAt = Date(timeIntervalSince1970: 1_700_000_500)
        context.insert(local)
        try context.save()

        let doc = makeTransactionDoc(
            id: id,
            name: "Older remote",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try service.upsertTransaction(doc, context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        #expect(all.first?.name == "Local wins")
    }

    // MARK: - upsert: tombstone

    @Test("upsertTransaction deletes local row when remote is tombstoned")
    func upsertDeletesOnTombstone() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = Transaction(name: "doomed")
        local.id = id
        context.insert(local)
        try context.save()

        let tombstone = makeTransactionDoc(id: id, isDeleted: true)

        try service.upsertTransaction(tombstone, context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        #expect(all.isEmpty)
    }

    // MARK: - End-to-end syncNow pull

    @Test("syncNow pulls Transactions and reconciles them into SwiftData")
    func syncNowPullsTransactions() async throws {
        let context = try makeContext()
        let reader = MockRemoteReader()
        reader.transactions = [
            makeTransactionDoc(name: "Cloud A"),
            makeTransactionDoc(name: "Cloud B")
        ]

        let service = makeService(context: context, reader: reader)

        try await service.syncNow()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        #expect(Set(all.map(\.name)) == Set(["Cloud A", "Cloud B"]))
    }
}
