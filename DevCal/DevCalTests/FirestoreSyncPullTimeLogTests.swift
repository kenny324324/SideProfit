//
//  FirestoreSyncPullTimeLogTests.swift
//  DevCalTests
//
//  Step 4 pull coverage for the `TimeLog` entity kind. Mirrors the
//  Transaction pull tests — same hydrate / LWW / tombstone matrix.
//

import Testing
import Foundation
import SwiftData
@testable import DevCal

@MainActor
struct FirestoreSyncPullTimeLogTests {

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
            "FirestoreSyncPullTimeLogTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-queue.json", isDirectory: false)
    }

    private func makeTimeLogDoc(
        id: UUID = UUID(),
        projectId: String? = nil,
        hours: Double = 3,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_500),
        isDeleted: Bool = false
    ) -> TimeLogDocument {
        TimeLogDocument(
            id: id.uuidString,
            projectId: projectId,
            hours: hours,
            hourlyRate: 1200,
            hourlyCurrencyCode: "TWD",
            note: "",
            date: Date(timeIntervalSince1970: 1_700_000_000),
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

    @Test("upsertTimeLog hydrates parent project when it exists locally")
    func upsertHydratesProject() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())

        let projectId = UUID()
        let project = Project(name: "Parent")
        project.id = projectId
        context.insert(project)
        try context.save()

        try service.upsertTimeLog(makeTimeLogDoc(projectId: projectId.uuidString), context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<TimeLog>())
        #expect(all.first?.project?.id == projectId)
    }

    @Test("upsertTimeLog LWW: newer remote replaces local")
    func upsertAppliesNewerRemote() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = TimeLog()
        local.id = id
        local.hours = 1
        local.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(local)
        try context.save()

        try service.upsertTimeLog(
            makeTimeLogDoc(id: id, hours: 5, updatedAt: Date(timeIntervalSince1970: 1_700_000_500)),
            context: context
        )
        try context.save()

        let all = try context.fetch(FetchDescriptor<TimeLog>())
        #expect(all.first?.hours == 5)
    }

    @Test("upsertTimeLog LWW: older remote leaves local alone")
    func upsertKeepsNewerLocal() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = TimeLog()
        local.id = id
        local.hours = 9
        local.updatedAt = Date(timeIntervalSince1970: 1_700_000_500)
        context.insert(local)
        try context.save()

        try service.upsertTimeLog(
            makeTimeLogDoc(id: id, hours: 1, updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            context: context
        )
        try context.save()

        let all = try context.fetch(FetchDescriptor<TimeLog>())
        #expect(all.first?.hours == 9)
    }

    @Test("upsertTimeLog deletes local row on tombstone")
    func upsertDeletesOnTombstone() throws {
        let context = try makeContext()
        let service = makeService(context: context, reader: MockRemoteReader())
        let id = UUID()

        let local = TimeLog()
        local.id = id
        context.insert(local)
        try context.save()

        try service.upsertTimeLog(makeTimeLogDoc(id: id, isDeleted: true), context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<TimeLog>())
        #expect(all.isEmpty)
    }

    @Test("syncNow pulls TimeLogs and reconciles them into SwiftData")
    func syncNowPullsTimeLogs() async throws {
        let context = try makeContext()
        let reader = MockRemoteReader()
        reader.timeLogs = [
            makeTimeLogDoc(hours: 2),
            makeTimeLogDoc(hours: 4)
        ]

        let service = makeService(context: context, reader: reader)

        try await service.syncNow()

        let all = try context.fetch(FetchDescriptor<TimeLog>())
        #expect(all.count == 2)
        #expect(Set(all.map(\.hours)) == Set([2.0, 4.0]))
    }
}
