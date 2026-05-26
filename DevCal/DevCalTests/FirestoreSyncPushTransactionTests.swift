//
//  FirestoreSyncPushTransactionTests.swift
//  DevCalTests
//
//  Step 3 push coverage for the `Transaction` entity kind. Mirrors the
//  Project test file's shape so the parallel structure is obvious to anyone
//  reading the kind switch in encodePush.
//

import Testing
import Foundation
@testable import DevCal

@MainActor
struct FirestoreSyncPushTransactionTests {

    // MARK: - Helpers

    private func makeTempQueueURL() -> URL {
        let dir = URL.temporaryDirectory.appendingPathComponent(
            "FirestoreSyncPushTransactionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-queue.json", isDirectory: false)
    }

    private func makeTransactionDocument(
        id: UUID = UUID(),
        projectId: String? = UUID().uuidString,
        amount: Double = 199,
        deterministicId: String? = nil
    ) -> TransactionDocument {
        TransactionDocument(
            id: id.uuidString,
            projectId: projectId,
            typeRaw: "expense",
            categoryRaw: "subscription",
            name: "Cursor Pro",
            iconBrandKey: nil,
            iconFallbackName: "subscription",
            iconColorHex: nil,
            originalAmount: amount,
            originalCurrencyCode: "USD",
            note: "",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            sourceCategoryItemId: nil,
            deterministicId: deterministicId,
            isDeleted: false
        )
    }

    private func makeOp(_ doc: TransactionDocument) throws -> PendingSyncOperation {
        try PendingSyncOperation.make(entityId: doc.id, kind: .transaction, document: doc)
    }

    // MARK: - encodePush

    @Test("encodePush routes Transaction ops to the transactions collection")
    func encodePushRoutesTransaction() throws {
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: MockRemoteWriter()
        )
        let doc = makeTransactionDocument()
        let op = try makeOp(doc)

        let push = try service.encodePush(op, ownerUid: "uid-1")

        #expect(push?.collection == "transactions")
        #expect(push?.fields["ownerUid"] as? String == "uid-1")
        #expect(push?.fields["name"] as? String == "Cursor Pro")
        #expect(push?.fields["originalAmount"] as? Double == 199)
        #expect(push?.fields["typeRaw"] as? String == "expense")
    }

    @Test("deterministicId round-trips on the wire so scheduler rows converge")
    func encodePushPreservesDeterministicId() throws {
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: MockRemoteWriter()
        )
        let detId = "cat-1_proj-1_20260526"
        let doc = makeTransactionDocument(deterministicId: detId)
        let op = try makeOp(doc)

        let push = try service.encodePush(op, ownerUid: "uid-1")

        #expect(push?.fields["deterministicId"] as? String == detId)
    }

    // MARK: - syncNow push pass

    @Test("syncNow pushes pending Transaction ops to the transactions collection")
    func syncNowPushesTransaction() async throws {
        let remote = MockRemoteWriter()
        let service = FirestoreSyncService(
            currentUID: { "uid-2" },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        let doc = makeTransactionDocument()
        service.enqueue(try makeOp(doc))

        try await service.syncNow()

        #expect(remote.calls == [.init(collection: "transactions", documentId: doc.id)])
        #expect(remote.lastFields["ownerUid"] as? String == "uid-2")
        #expect(service.snapshotQueue().isEmpty)
        #expect(service.status == .idle)
    }

    @Test("Project + Transaction ops both drain in a single syncNow pass")
    func syncNowDrainsMixedKinds() async throws {
        let remote = MockRemoteWriter()
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        let projectDoc = ProjectDocument(
            id: UUID().uuidString,
            name: "Rolypoly",
            projectDescription: "",
            statusRaw: "live",
            kindRaw: "app",
            iconImageData: nil,
            iconPhName: nil,
            iconColorHex: nil,
            launchDate: nil,
            createdAt: Date(),
            updatedAt: Date(),
            archivedAt: nil,
            sortIndex: 0,
            breakevenReachedAt: nil,
            goalAmount: nil,
            goalCurrencyCode: nil,
            goalDeadline: nil,
            isDeleted: false
        )
        let txnDoc = makeTransactionDocument()
        service.enqueue(try PendingSyncOperation.make(entityId: projectDoc.id, kind: .project, document: projectDoc))
        service.enqueue(try makeOp(txnDoc))

        try await service.syncNow()

        #expect(remote.calls.map(\.collection).sorted() == ["projects", "transactions"])
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
        var doc = makeTransactionDocument()
        doc.isDeleted = true
        service.enqueue(try makeOp(doc))

        try await service.syncNow()

        #expect(remote.lastFields["isDeleted"] as? Bool == true)
        #expect(service.snapshotQueue().isEmpty)
    }
}
