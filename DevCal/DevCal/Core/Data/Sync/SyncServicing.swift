//
//  SyncServicing.swift
//  DevCal
//
//  Protocol the rest of the app speaks to when it needs to mirror a local
//  write or trigger a sync pass. Kept small on purpose; concrete impls
//  (FirestoreSyncService, NoopSyncService) live in sibling files.
//

import Foundation

@MainActor
protocol SyncServicing: AnyObject {
    var status: SyncStatus { get }

    /// Repositories call this immediately after a successful local write so
    /// the sync engine has a record of what to push. Implementations must
    /// be cheap (queue write only, no network).
    func enqueue(_ operation: PendingSyncOperation)

    /// User-driven "sync now". Runs a push pass followed by a pull. No-op
    /// when `status == .disabled`.
    func syncNow() async throws
}

/// Test / debug stand-in. Swallows every enqueue and reports `.disabled` so
/// callers can construct repositories without wiring Firebase. The production
/// path uses `FirestoreSyncService`; this type is retained so unit tests can
/// build a repository without dragging the sync engine in.
@MainActor
final class NoopSyncService: SyncServicing {
    private(set) var status: SyncStatus = .disabled

    /// Bookkeeping for tests / debugging — holds the most recent N enqueued
    /// ops in memory so assertions can inspect them.
    private(set) var recentlyEnqueued: [PendingSyncOperation] = []
    private let maxRecent = 32

    func enqueue(_ operation: PendingSyncOperation) {
        recentlyEnqueued.append(operation)
        if recentlyEnqueued.count > maxRecent {
            recentlyEnqueued.removeFirst(recentlyEnqueued.count - maxRecent)
        }
    }

    func syncNow() async throws {
        // No remote, nothing to do.
    }
}
