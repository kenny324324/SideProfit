//
//  FirestoreSyncPullCategoryItemTests.swift
//  DevCalTests
//
//  Step 4 pull coverage for `CategoryItem`. The interesting case beyond the
//  standard LWW + tombstone matrix: the many-to-many `projects` array is
//  re-resolved from `projectIds` on every upsert, so a remote allocation
//  change (project added / removed from a shared expense) lands locally.
//

import Testing
import Foundation
import SwiftData
@testable import DevCal

@MainActor
struct FirestoreSyncPullCategoryItemTests {

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
            "FirestoreSyncPullCategoryItemTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-queue.json", isDirectory: false)
    }

    private func makeCategoryItemDoc(
        id: UUID = UUID(),
        name: String = "Cursor",
        projectIds: [String] = [],
        weights: [String: Double]? = nil,
        isShared: Bool = false,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_500),
        isDeleted: Bool = false
    ) -> CategoryItemDocument {
        CategoryItemDocument(
            id: id.uuidString,
            name: name,
            categoryRaw: "subscription",
            totalAmount: 240,
            originalCurrencyCode: "USD",
            billingTypeRaw: "monthly",
            brandIconKey: nil,
            fallbackIconName: nil,
            iconColorHex: nil,
            nextDueDate: nil,
            isActive: true,
            isShared: isShared,
            splitModeRaw: "equal",
            weightsByProjectId: weights,
            projectIds: projectIds,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }

    private func makeService(context: ModelContext, reader: MockRemoteReader) -> FirestoreSyncService {
        FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: MockRemoteWriter(),
            reader: reader,
            modelContext: context
        )
    }

    @Test("upsertCategoryItem hydrates the projects array from projectIds")
    func upsertHydratesProjects() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())

        let pA = Project(name: "A"); pA.id = UUID(); context.insert(pA)
        let pB = Project(name: "B"); pB.id = UUID(); context.insert(pB)
        try context.save()

        let doc = makeCategoryItemDoc(
            isShared: true,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        var docWithIds = doc
        docWithIds.projectIds = [pA.id.uuidString, pB.id.uuidString]

        try service.upsertCategoryItem(docWithIds, context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<CategoryItem>())
        let projects = all.first?.projects ?? []
        #expect(Set(projects.map(\.id)) == Set([pA.id, pB.id]))
    }

    @Test("upsertCategoryItem LWW: newer remote replaces local")
    func upsertAppliesNewerRemote() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = CategoryItem(name: "Local name")
        local.id = id
        local.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(local)
        try context.save()

        try service.upsertCategoryItem(
            makeCategoryItemDoc(id: id, name: "Remote name", updatedAt: Date(timeIntervalSince1970: 1_700_000_500)),
            context: context
        )
        try context.save()

        let all = try context.fetch(FetchDescriptor<CategoryItem>())
        #expect(all.first?.name == "Remote name")
    }

    @Test("upsertCategoryItem LWW: older remote leaves local alone")
    func upsertKeepsNewerLocal() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = CategoryItem(name: "Local wins")
        local.id = id
        local.updatedAt = Date(timeIntervalSince1970: 1_700_000_500)
        context.insert(local)
        try context.save()

        try service.upsertCategoryItem(
            makeCategoryItemDoc(id: id, name: "Stale", updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            context: context
        )
        try context.save()

        let all = try context.fetch(FetchDescriptor<CategoryItem>())
        #expect(all.first?.name == "Local wins")
    }

    @Test("upsertCategoryItem deletes local row on tombstone")
    func upsertDeletesOnTombstone() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = CategoryItem(name: "doomed")
        local.id = id
        context.insert(local)
        try context.save()

        try service.upsertCategoryItem(makeCategoryItemDoc(id: id, isDeleted: true), context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<CategoryItem>())
        #expect(all.isEmpty)
    }

    @Test("syncNow pulls CategoryItems and reconciles them into SwiftData")
    func syncNowPullsCategoryItems() async throws {
        let context = try makeContext()
        let reader = MockRemoteReader()
        reader.categoryItems = [
            makeCategoryItemDoc(name: "Cursor"),
            makeCategoryItemDoc(name: "Linear")
        ]

        let service = makeService(context: context, reader: reader)

        try await service.syncNow()

        let all = try context.fetch(FetchDescriptor<CategoryItem>())
        #expect(Set(all.map(\.name)) == Set(["Cursor", "Linear"]))
    }
}
