//
//  FirestoreSyncPushCategoryItemTests.swift
//  DevCalTests
//
//  Step 3 push coverage for the `CategoryItem` entity kind. The interesting
//  bits beyond the standard shape: `projectIds` is an array and
//  `weightsByProjectId` is a string-keyed dictionary — both have to survive
//  the Firestore.Encoder flatten without flipping into Swift-only types.
//

import Testing
import Foundation
@testable import DevCal

@MainActor
struct FirestoreSyncPushCategoryItemTests {

    // MARK: - Helpers

    private func makeTempQueueURL() -> URL {
        let dir = URL.temporaryDirectory.appendingPathComponent(
            "FirestoreSyncPushCategoryItemTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-queue.json", isDirectory: false)
    }

    private func makeCategoryItemDocument(
        id: UUID = UUID(),
        isShared: Bool = false,
        projectIds: [String] = [],
        weights: [String: Double]? = nil
    ) -> CategoryItemDocument {
        CategoryItemDocument(
            id: id.uuidString,
            name: "Cursor Pro",
            categoryRaw: "subscription",
            totalAmount: 240,
            originalCurrencyCode: "USD",
            billingTypeRaw: "monthly",
            brandIconKey: "cursor",
            fallbackIconName: nil,
            iconColorHex: nil,
            nextDueDate: Date(timeIntervalSince1970: 1_700_000_000),
            isActive: true,
            isShared: isShared,
            splitModeRaw: "equal",
            weightsByProjectId: weights,
            projectIds: projectIds,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            isDeleted: false
        )
    }

    private func makeOp(_ doc: CategoryItemDocument) throws -> PendingSyncOperation {
        try PendingSyncOperation.make(entityId: doc.id, kind: .categoryItem, document: doc)
    }

    // MARK: - encodePush

    @Test("encodePush routes CategoryItem ops to the categoryItems collection")
    func encodePushRoutesCategoryItem() throws {
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: MockRemoteWriter()
        )
        let doc = makeCategoryItemDocument()
        let op = try makeOp(doc)

        let push = try service.encodePush(op, ownerUid: "uid-1")

        #expect(push?.collection == "categoryItems")
        #expect(push?.fields["name"] as? String == "Cursor Pro")
        #expect(push?.fields["totalAmount"] as? Double == 240)
        #expect(push?.fields["billingTypeRaw"] as? String == "monthly")
    }

    @Test("shared expense: projectIds + weightsByProjectId survive the flatten")
    func encodePushPreservesSharedExpenseAllocation() throws {
        let service = FirestoreSyncService(
            currentUID: { "uid-1" },
            queueURL: makeTempQueueURL(),
            remote: MockRemoteWriter()
        )
        let projectA = UUID().uuidString
        let projectB = UUID().uuidString
        let doc = makeCategoryItemDocument(
            isShared: true,
            projectIds: [projectA, projectB],
            weights: [projectA: 0.7, projectB: 0.3]
        )
        let op = try makeOp(doc)

        let push = try service.encodePush(op, ownerUid: "uid-1")

        #expect(push?.fields["isShared"] as? Bool == true)
        #expect(push?.fields["projectIds"] as? [String] == [projectA, projectB])

        let weights = push?.fields["weightsByProjectId"] as? [String: Double]
        #expect(weights?[projectA] == 0.7)
        #expect(weights?[projectB] == 0.3)
    }

    // MARK: - syncNow push pass

    @Test("syncNow pushes pending CategoryItem ops and acks them")
    func syncNowPushesCategoryItem() async throws {
        let remote = MockRemoteWriter()
        let service = FirestoreSyncService(
            currentUID: { "uid-4" },
            queueURL: makeTempQueueURL(),
            remote: remote
        )
        let doc = makeCategoryItemDocument()
        service.enqueue(try makeOp(doc))

        try await service.syncNow()

        #expect(remote.calls == [.init(collection: "categoryItems", documentId: doc.id)])
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
        var doc = makeCategoryItemDocument()
        doc.isDeleted = true
        service.enqueue(try makeOp(doc))

        try await service.syncNow()

        #expect(remote.lastFields["isDeleted"] as? Bool == true)
        #expect(service.snapshotQueue().isEmpty)
    }
}
