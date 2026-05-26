//
//  FirestoreSyncPullProjectTests.swift
//  DevCalTests
//
//  Step 4 pull coverage for the `Project` entity kind. Uses an in-memory
//  ModelContainer and a MockRemoteReader so the tests never touch Firestore.
//

import Testing
import Foundation
import SwiftData
@testable import DevCal

@MainActor
final class MockRemoteReader: RemoteReading {
    var projects: [ProjectDocument] = []
    var transactions: [TransactionDocument] = []
    var timeLogs: [TimeLogDocument] = []
    var categoryItems: [CategoryItemDocument] = []
    var milestones: [MilestoneDocument] = []
    var errorToThrow: Error?

    func fetchProjects(ownerUid: String, limit: Int) async throws -> [ProjectDocument] {
        if let err = errorToThrow { throw err }
        return projects
    }
    func fetchTransactions(ownerUid: String, limit: Int) async throws -> [TransactionDocument] {
        if let err = errorToThrow { throw err }
        return transactions
    }
    func fetchTimeLogs(ownerUid: String, limit: Int) async throws -> [TimeLogDocument] {
        if let err = errorToThrow { throw err }
        return timeLogs
    }
    func fetchCategoryItems(ownerUid: String, limit: Int) async throws -> [CategoryItemDocument] {
        if let err = errorToThrow { throw err }
        return categoryItems
    }
    func fetchMilestones(ownerUid: String, limit: Int) async throws -> [MilestoneDocument] {
        if let err = errorToThrow { throw err }
        return milestones
    }
}

@MainActor
struct FirestoreSyncPullProjectTests {

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
            "FirestoreSyncPullProjectTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-queue.json", isDirectory: false)
    }

    private func makeProjectDocument(
        id: UUID = UUID(),
        name: String = "Pulled",
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_500),
        isDeleted: Bool = false
    ) -> ProjectDocument {
        ProjectDocument(
            id: id.uuidString,
            name: name,
            projectDescription: "",
            statusRaw: "live",
            kindRaw: "app",
            iconImageData: nil,
            iconPhName: nil,
            iconColorHex: nil,
            launchDate: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: updatedAt,
            archivedAt: nil,
            sortIndex: 0,
            breakevenReachedAt: nil,
            goalAmount: nil,
            goalCurrencyCode: nil,
            goalDeadline: nil,
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

    // MARK: - upsert: new doc

    @Test("upsertProject inserts a brand-new Project when local store is empty")
    func upsertInsertsNewProject() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let doc = makeProjectDocument(name: "Cloud Project")

        try service.upsertProject(doc, context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Project>())
        #expect(all.count == 1)
        #expect(all.first?.name == "Cloud Project")
    }

    // MARK: - upsert: LWW

    @Test("upsertProject applies remote when remote.updatedAt is newer")
    func upsertAppliesNewerRemote() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = Project(name: "Local name")
        local.id = id
        local.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(local)
        try context.save()

        let doc = makeProjectDocument(
            id: id,
            name: "Remote name",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )

        try service.upsertProject(doc, context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Project>())
        #expect(all.first?.name == "Remote name")
    }

    @Test("upsertProject keeps local when local.updatedAt is newer")
    func upsertKeepsNewerLocal() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = Project(name: "Local wins")
        local.id = id
        local.updatedAt = Date(timeIntervalSince1970: 1_700_000_500)
        context.insert(local)
        try context.save()

        let doc = makeProjectDocument(
            id: id,
            name: "Older remote",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try service.upsertProject(doc, context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Project>())
        #expect(all.first?.name == "Local wins")
    }

    // MARK: - upsert: tombstone

    @Test("upsertProject deletes local row when remote is tombstoned")
    func upsertDeletesOnTombstone() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = Project(name: "doomed")
        local.id = id
        context.insert(local)
        try context.save()

        let tombstone = makeProjectDocument(id: id, isDeleted: true)

        try service.upsertProject(tombstone, context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Project>())
        #expect(all.isEmpty)
    }

    @Test("upsertProject is a no-op when tombstone arrives but row never existed locally")
    func upsertTombstoneOnMissingLocalIsNoOp() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let tombstone = makeProjectDocument(isDeleted: true)

        try service.upsertProject(tombstone, context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Project>())
        #expect(all.isEmpty)
    }

    // MARK: - End-to-end syncNow pull

    @Test("syncNow pulls projects via MockRemoteReader and reconciles into SwiftData")
    func syncNowPullsProjects() async throws {
        let context = try makeContext()
        let reader = MockRemoteReader()
        let docA = makeProjectDocument(name: "Cloud A")
        let docB = makeProjectDocument(name: "Cloud B")
        reader.projects = [docA, docB]

        let service = makeService(context: context, reader: reader)

        try await service.syncNow()

        let all = try context.fetch(FetchDescriptor<Project>())
        #expect(Set(all.map(\.name)) == Set(["Cloud A", "Cloud B"]))
        #expect(service.status == .idle)
        #expect(service.lastSyncedAt != nil)
    }

    @Test("syncNow surfaces reader errors as .failed without crashing")
    func syncNowSurfacesReaderError() async throws {
        struct ReaderFailure: LocalizedError {
            var errorDescription: String? { "reader blew up" }
        }
        let context = try makeContext()
        let reader = MockRemoteReader()
        reader.errorToThrow = ReaderFailure()

        let service = makeService(context: context, reader: reader)

        try await service.syncNow()

        if case .failed(let message) = service.status {
            #expect(message == "reader blew up")
        } else {
            Issue.record("expected .failed, got \(service.status)")
        }
    }
}
