//
//  FirestoreSyncService.swift
//  DevCal
//
//  Phase 4 sync engine. Owns the on-disk queue of PendingSyncOperations that
//  repositories enqueue after every local write, and (in later steps) drives
//  push/pull against Firestore. This file lands the *skeleton*: queue
//  persistence + auth-driven status. `syncNow()` is a no-op until Step 3.
//
//  Design notes:
//  - Queue is persisted as JSON to Application Support/sync-queue.json so an
//    unsynced op survives a process kill / reboot.
//  - We never store the SwiftData live objects — the queue holds DTO snapshots
//    so replay is independent of current local state.
//  - The current uid is resolved through an injected closure so the unit
//    tests (which don't run Firebase) can drive the service without touching
//    Auth.auth().
//

import Foundation
import FirebaseAuth

@MainActor
final class FirestoreSyncService: SyncServicing {

    // MARK: - Public state

    private(set) var status: SyncStatus = .disabled
    private(set) var lastSyncedAt: Date?

    // MARK: - Stored

    /// In-memory mirror of the on-disk queue. Reads are O(1); every mutation
    /// also rewrites the file so a crash between enqueue and drain doesn't
    /// lose work.
    private var queue: [PendingSyncOperation]
    private let queueURL: URL
    private let currentUID: @MainActor () -> String?

    // MARK: - Init

    /// Designated init. Production callers use the convenience init that
    /// resolves the uid from FirebaseAuth; tests inject their own closure +
    /// a temp queue URL.
    init(
        currentUID: @escaping @MainActor () -> String?,
        queueURL: URL
    ) {
        self.currentUID = currentUID
        self.queueURL = queueURL
        self.queue = Self.loadQueue(at: queueURL)
        refreshStatusFromAuth()
    }

    /// Production convenience: resolves the uid from FirebaseAuth and writes
    /// the queue to the standard Application Support location.
    convenience init() {
        self.init(
            currentUID: { Auth.auth().currentUser?.uid },
            queueURL: Self.defaultQueueURL()
        )
    }

    // MARK: - SyncServicing

    func enqueue(_ operation: PendingSyncOperation) {
        queue.append(operation)
        persistQueue()
    }

    func syncNow() async throws {
        // Step 2 lands the skeleton only. The push half goes in here in Step 3,
        // followed by the pull half in Step 4. Calling syncNow() today refreshes
        // status from auth (so a freshly-signed-in user sees `.idle` instead of
        // a stale `.disabled`) and otherwise returns.
        refreshStatusFromAuth()
    }

    // MARK: - Status

    /// Recompute `status` from the current auth state. Idempotent; safe to
    /// call from `onChange(of: auth.account?.id)`.
    func refreshStatusFromAuth() {
        let signedIn = currentUID() != nil
        switch (status, signedIn) {
        case (_, false):
            status = .disabled
        case (.disabled, true):
            status = .idle
        default:
            // Mid-sync states (.pushing / .pulling / .failed) stay as-is —
            // an auth flip during a sync pass is rare and the next syncNow()
            // call will normalize the state.
            break
        }
    }

    // MARK: - Queue access (used by Step 3 push pass + tests)

    /// Snapshot of the pending queue. Returned by value so callers can iterate
    /// without holding a reference into our storage.
    func snapshotQueue() -> [PendingSyncOperation] {
        queue
    }

    /// Remove a specific entry by `operationId` after a successful push.
    func acknowledge(operationId: String) {
        let before = queue.count
        queue.removeAll { $0.operationId == operationId }
        if queue.count != before {
            persistQueue()
        }
    }

    // MARK: - Persistence

    /// Default queue location: `Application Support/sync-queue.json`. Falls back
    /// to a tmp URL if Application Support somehow can't be resolved (so the
    /// service still works in unusual sandboxes — the queue just becomes
    /// ephemeral instead of crashing the app).
    static func defaultQueueURL() -> URL {
        let fm = FileManager.default
        if let dir = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return dir.appendingPathComponent("sync-queue.json", isDirectory: false)
        }
        return URL.temporaryDirectory.appendingPathComponent("sync-queue.json", isDirectory: false)
    }

    private static func loadQueue(at url: URL) -> [PendingSyncOperation] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder.devcalSync.decode([PendingSyncOperation].self, from: data)
        } catch {
            #if DEBUG
            print("[sync] failed to decode queue at \(url.path): \(error)")
            #endif
            return []
        }
    }

    private func persistQueue() {
        let fm = FileManager.default
        let directory = queueURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.devcalSync.encode(queue)
            try data.write(to: queueURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[sync] queue persistence failed: \(error)")
            #endif
        }
    }
}
