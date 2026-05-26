//
//  FirestoreSyncService.swift
//  DevCal
//
//  Phase 0 placeholder. Defines the protocol that repositories will call into
//  when enqueueing sync operations and that the Settings UI will use to drive
//  the manual "Sync now" button.
//
//  No Firebase SDK is imported here yet. The real implementation lands in
//  Phase 4 — at that point this file will gain a concrete `FirestoreSyncService`
//  conforming to `SyncServicing` and wired up against FirebaseFirestore.
//

import Foundation

/// Public API the rest of the app speaks to when it needs to mirror a local
/// write or trigger a sync pass. Kept small on purpose; Phase 4 may add more
/// methods (conflict resolution, full re-sync, etc.).
@MainActor
protocol SyncServicing: AnyObject {
    var status: SyncStatus { get }

    /// Repositories call this immediately after a successful local write so
    /// the sync engine has a record of what to push. Phase 0 implementations
    /// may discard the operation; Phase 4 persists it to disk.
    func enqueue(_ operation: PendingSyncOperation)

    /// User-driven "sync now". Runs a push pass followed by a pull. No-op
    /// when `status == .disabled`.
    func syncNow() async throws
}

/// Phase 0 stand-in. Swallows every enqueue and reports `.disabled` so the
/// app behaves exactly as it does today (local-only). Wired into the
/// environment by `DevCalApp` so views and repositories can depend on the
/// protocol immediately without waiting for Firebase.
@MainActor
final class NoopSyncService: SyncServicing {
    private(set) var status: SyncStatus = .disabled

    /// Bookkeeping for tests / debugging. The real service will persist these
    /// to disk; here we just hold the most recent N in-memory.
    private(set) var recentlyEnqueued: [PendingSyncOperation] = []
    private let maxRecent = 32

    func enqueue(_ operation: PendingSyncOperation) {
        recentlyEnqueued.append(operation)
        if recentlyEnqueued.count > maxRecent {
            recentlyEnqueued.removeFirst(recentlyEnqueued.count - maxRecent)
        }
    }

    func syncNow() async throws {
        // Phase 0: no remote, nothing to do. Phase 4 will implement push+pull.
    }
}
