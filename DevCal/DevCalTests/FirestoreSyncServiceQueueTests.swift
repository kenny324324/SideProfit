//
//  FirestoreSyncServiceQueueTests.swift
//  DevCalTests
//
//  Step 2 coverage: queue persistence + auth-driven status. The push / pull
//  paths land in later steps and get their own test files. We deliberately
//  don't import FirebaseFirestore here — the unit tests only exercise the
//  Foundation half of the service.
//

import Testing
import Foundation
@testable import DevCal

@MainActor
struct FirestoreSyncServiceQueueTests {

    // MARK: - Helpers

    private func makeTempQueueURL() -> URL {
        let dir = URL.temporaryDirectory.appendingPathComponent(
            "FirestoreSyncServiceQueueTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-queue.json", isDirectory: false)
    }

    private func makeOperation(entityId: String = UUID().uuidString) -> PendingSyncOperation {
        PendingSyncOperation(
            entityId: entityId,
            kind: .project,
            payload: Data("payload-\(entityId)".utf8)
        )
    }

    // MARK: - Enqueue

    @Test("enqueue appends to the in-memory snapshot")
    func enqueueAppends() {
        let service = FirestoreSyncService(currentUID: { "uid-1" }, queueURL: makeTempQueueURL())
        let op = makeOperation()

        service.enqueue(op)

        let snapshot = service.snapshotQueue()
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.operationId == op.operationId)
    }

    // MARK: - Drain

    @Test("acknowledge removes the matching op and leaves others alone")
    func acknowledgeDrainsSingleOp() {
        let service = FirestoreSyncService(currentUID: { "uid-1" }, queueURL: makeTempQueueURL())
        let a = makeOperation(entityId: "a")
        let b = makeOperation(entityId: "b")
        service.enqueue(a)
        service.enqueue(b)

        service.acknowledge(operationId: a.operationId)

        let remaining = service.snapshotQueue()
        #expect(remaining.count == 1)
        #expect(remaining.first?.entityId == "b")
    }

    // MARK: - Persistence across restart

    @Test("queue survives a fresh service instance against the same file")
    func queuePersistsAcrossRestart() {
        let url = makeTempQueueURL()
        let first = FirestoreSyncService(currentUID: { "uid-1" }, queueURL: url)
        first.enqueue(makeOperation(entityId: "x"))
        first.enqueue(makeOperation(entityId: "y"))

        let second = FirestoreSyncService(currentUID: { "uid-1" }, queueURL: url)

        let snapshot = second.snapshotQueue()
        #expect(snapshot.map(\.entityId) == ["x", "y"])
    }

    @Test("acknowledged ops do not resurrect on next launch")
    func acknowledgePersists() {
        let url = makeTempQueueURL()
        let first = FirestoreSyncService(currentUID: { "uid-1" }, queueURL: url)
        let keep = makeOperation(entityId: "keep")
        let drop = makeOperation(entityId: "drop")
        first.enqueue(keep)
        first.enqueue(drop)
        first.acknowledge(operationId: drop.operationId)

        let second = FirestoreSyncService(currentUID: { "uid-1" }, queueURL: url)
        let snapshot = second.snapshotQueue()
        #expect(snapshot.map(\.entityId) == ["keep"])
    }

    // MARK: - Status driven by auth

    @Test("status starts .disabled when no uid is available")
    func statusDisabledWhenSignedOut() {
        let service = FirestoreSyncService(currentUID: { nil }, queueURL: makeTempQueueURL())
        #expect(service.status == .disabled)
    }

    @Test("status flips to .idle once auth has a uid")
    func statusIdleAfterSignIn() {
        var uid: String? = nil
        let service = FirestoreSyncService(currentUID: { uid }, queueURL: makeTempQueueURL())
        #expect(service.status == .disabled)

        uid = "uid-2"
        service.refreshStatusFromAuth()

        #expect(service.status == .idle)
    }

    @Test("status falls back to .disabled when uid disappears")
    func statusDisabledAfterSignOut() {
        var uid: String? = "uid-3"
        let service = FirestoreSyncService(currentUID: { uid }, queueURL: makeTempQueueURL())
        #expect(service.status == .idle)

        uid = nil
        service.refreshStatusFromAuth()

        #expect(service.status == .disabled)
    }
}
