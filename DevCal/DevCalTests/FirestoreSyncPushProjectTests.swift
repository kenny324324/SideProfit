//
//  FirestoreSyncPushProjectTests.swift
//  DevCalTests
//
//  Step 3 push coverage for the `Project` entity kind. Uses a mock
//  RemoteWriting so the tests never touch the Firestore SDK or the network.
//

import Testing
import Foundation
@testable import DevCal

@MainActor
final class MockRemoteWriter: RemoteWriting {
    struct Call: Equatable {
        let collection: String
        let documentId: String
    }

    var calls: [Call] = []
    var lastFields: [String: Any] = [:]
    var errorToThrow: Error?

    func setDocument(
        collection: String,
        documentId: String,
        fields: [String: Any]
    ) async throws {
        if let err = errorToThrow {
            throw err
        }
        calls.append(.init(collection: collection, documentId: documentId))
        lastFields = fields
    }
}

@MainActor
struct FirestoreSyncPushProjectTests {

    // MARK: - Helpers

    private func makeTempQueueURL() -> URL {
        let dir = URL.temporaryDirectory.appendingPathComponent(
            "FirestoreSyncPushProjectTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-queue.json", isDirectory: false)
    }

    private func makeProjectDocument(id: UUID = UUID(), name: String = "ShipSwift") -> ProjectDocument {
        ProjectDocument(
            id: id.uuidString,
            name: name,
            projectDescription: "test",
            statusRaw: "live",
            kindRaw: "app",
            iconImageData: nil,
            iconPhName: "rocket",
            iconColorHex: "#000000",
            launchDate: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            archivedAt: nil,
            sortIndex: 0,
            breakevenReachedAt: nil,
            goalAmount: nil,
            goalCurrencyCode: nil,
            goalDeadline: nil,
            isDeleted: false
        )
    }

    private func makeOp(_ doc: ProjectDocument) throws -> PendingSyncOperation {
        try PendingSyncOperation.make(entityId: doc.id, kind: .project, document: doc)
    }

    // MARK: - encodePush

    @Test("encodePush returns the projects collection + ownerUid + flattened DTO")
    func encodePushShapesPayload() throws {
        let remote = MockRemoteWriter()
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        let doc = makeProjectDocument()
        let op = try makeOp(doc)

        let push = try service.encodePush(op, ownerUid: "uid-1")

        #expect(push?.collection == "projects")
        #expect(push?.fields["ownerUid"] as? String == "uid-1")
        #expect(push?.fields["name"] as? String == "ShipSwift")
        #expect(push?.fields["isDeleted"] as? Bool == false)
    }

    @Test("encodePush returns nil for kinds not yet wired")
    func encodePushSkipsUnimplementedKinds() throws {
        let remote = MockRemoteWriter()
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        let op = PendingSyncOperation(
            entityId: UUID().uuidString,
            kind: .transaction,
            payload: Data()
        )

        let push = try service.encodePush(op, ownerUid: "uid-1")

        #expect(push == nil)
    }

    // MARK: - syncNow push pass

    @Test("syncNow pushes pending Project ops to the projects collection")
    func syncNowPushesProject() async throws {
        let remote = MockRemoteWriter()
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        let doc = makeProjectDocument(name: "Rolypoly")
        service.enqueue(try makeOp(doc))

        try await service.syncNow()

        #expect(remote.calls == [.init(collection: "projects", documentId: doc.id)])
        #expect(remote.lastFields["ownerUid"] as? String == "uid-1")
        #expect(service.snapshotQueue().isEmpty)
        #expect(service.status == .idle)
        #expect(service.lastSyncedAt != nil)
    }

    @Test("syncNow leaves transaction-kind ops in the queue (not yet wired)")
    func syncNowSkipsUnimplementedKinds() async throws {
        let remote = MockRemoteWriter()
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        let project = makeProjectDocument()
        let projectOp = try makeOp(project)
        let txnOp = PendingSyncOperation(
            entityId: "txn-1",
            kind: .transaction,
            payload: Data()
        )
        service.enqueue(projectOp)
        service.enqueue(txnOp)

        try await service.syncNow()

        let remaining = service.snapshotQueue()
        #expect(remaining.map(\.kind) == [.transaction])
        #expect(remote.calls.map(\.collection) == ["projects"])
    }

    @Test("a remote error stops the pass and surfaces as .failed")
    func syncNowSurfacesRemoteErrors() async throws {
        struct RemoteFailure: LocalizedError {
            var errorDescription: String? { "remote write blew up" }
        }
        let remote = MockRemoteWriter()
        remote.errorToThrow = RemoteFailure()

        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        let op = try makeOp(makeProjectDocument())
        service.enqueue(op)

        try await service.syncNow()

        #expect(service.snapshotQueue().count == 1)
        if case .failed(let message) = service.status {
            #expect(message == "remote write blew up")
        } else {
            Issue.record("expected .failed, got \(service.status)")
        }
    }

    @Test("syncNow is a no-op when signed out")
    func syncNowNoOpWhenDisabled() async throws {
        let remote = MockRemoteWriter()
        let service = FirestoreSyncService(
            currentUID: { nil },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        service.enqueue(try makeOp(makeProjectDocument()))

        try await service.syncNow()

        #expect(remote.calls.isEmpty)
        #expect(service.status == .disabled)
    }

    @Test("tombstone (isDeleted = true) round-trips through the push")
    func syncNowPushesTombstone() async throws {
        let remote = MockRemoteWriter()
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        var doc = makeProjectDocument()
        doc.isDeleted = true
        service.enqueue(try makeOp(doc))

        try await service.syncNow()

        #expect(remote.lastFields["isDeleted"] as? Bool == true)
        #expect(service.snapshotQueue().isEmpty)
    }
}
