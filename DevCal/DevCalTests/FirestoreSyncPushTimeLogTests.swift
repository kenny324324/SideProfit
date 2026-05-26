//
//  FirestoreSyncPushTimeLogTests.swift
//  DevCalTests
//
//  Step 3 push coverage for the `TimeLog` entity kind.
//

import Testing
import Foundation
@testable import DevCal

@MainActor
struct FirestoreSyncPushTimeLogTests {

    // MARK: - Helpers

    private func makeTempQueueURL() -> URL {
        let dir = URL.temporaryDirectory.appendingPathComponent(
            "FirestoreSyncPushTimeLogTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-queue.json", isDirectory: false)
    }

    private func makeTimeLogDocument(
        id: UUID = UUID(),
        hours: Double = 3.5,
        rate: Double = 1200
    ) -> TimeLogDocument {
        TimeLogDocument(
            id: id.uuidString,
            projectId: UUID().uuidString,
            hours: hours,
            hourlyRate: rate,
            hourlyCurrencyCode: "TWD",
            note: "spec review",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            isDeleted: false
        )
    }

    private func makeOp(_ doc: TimeLogDocument) throws -> PendingSyncOperation {
        try PendingSyncOperation.make(entityId: doc.id, kind: .timeLog, document: doc)
    }

    // MARK: - encodePush

    @Test("encodePush routes TimeLog ops to the timeLogs collection")
    func encodePushRoutesTimeLog() throws {
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: MockRemoteWriter()
        )
        let doc = makeTimeLogDocument()
        let op = try makeOp(doc)

        let push = try service.encodePush(op, ownerUid: "uid-1")

        #expect(push?.collection == "timeLogs")
        #expect(push?.fields["ownerUid"] as? String == "uid-1")
        #expect(push?.fields["hours"] as? Double == 3.5)
        #expect(push?.fields["hourlyRate"] as? Double == 1200)
        #expect(push?.fields["hourlyCurrencyCode"] as? String == "TWD")
    }

    // MARK: - syncNow push pass

    @Test("syncNow pushes pending TimeLog ops and acks them")
    func syncNowPushesTimeLog() async throws {
        let remote = MockRemoteWriter()
        let service = FirestoreSyncService(
            currentUID: { "uid-3" },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        let doc = makeTimeLogDocument()
        service.enqueue(try makeOp(doc))

        try await service.syncNow()

        #expect(remote.calls == [.init(collection: "timeLogs", documentId: doc.id)])
        #expect(service.snapshotQueue().isEmpty)
    }

    @Test("tombstone (isDeleted = true) round-trips through the push")
    func syncNowPushesTombstone() async throws {
        let remote = MockRemoteWriter()
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        var doc = makeTimeLogDocument()
        doc.isDeleted = true
        service.enqueue(try makeOp(doc))

        try await service.syncNow()

        #expect(remote.lastFields["isDeleted"] as? Bool == true)
        #expect(service.snapshotQueue().isEmpty)
    }
}
