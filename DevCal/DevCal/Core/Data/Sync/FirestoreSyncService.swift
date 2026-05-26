//
//  FirestoreSyncService.swift
//  DevCal
//
//  Phase 4 sync engine. Owns the on-disk queue of PendingSyncOperations that
//  repositories enqueue after every local write, and (in later steps) drives
//  push/pull against Firestore.
//
//  Step 2 landed queue persistence + auth-driven status. Step 3 adds the push
//  half of `syncNow()` for the `Project` entity kind; other kinds stay in the
//  queue until their commit lands. Step 4 will layer the pull pass on top.
//
//  Design notes:
//  - Queue is persisted as JSON to Application Support/sync-queue.json so an
//    unsynced op survives a process kill / reboot.
//  - We never store the SwiftData live objects — the queue holds DTO snapshots
//    so replay is independent of current local state.
//  - The current uid is resolved through an injected closure, and remote
//    writes go through the `RemoteWriting` seam, so unit tests can drive the
//    service without booting Firebase or the emulator.
//  - Flat schema: every collection sits at the root and every doc carries
//    `ownerUid`. Security rules in `Files/firestore.rules` enforce that
//    `ownerUid == request.auth.uid` on every read/write.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
@Observable
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
    private let remote: (any RemoteWriting)?

    // MARK: - Init

    /// Designated init. Production callers use the convenience init that
    /// resolves the uid from FirebaseAuth and writes via FirestoreRemoteWriter;
    /// tests inject their own closure + a temp queue URL + a mock writer.
    init(
        currentUID: @escaping @MainActor () -> String?,
        queueURL: URL,
        remote: (any RemoteWriting)? = nil
    ) {
        self.currentUID = currentUID
        self.queueURL = queueURL
        self.remote = remote
        self.queue = Self.loadQueue(at: queueURL)
        refreshStatusFromAuth()
    }

    /// Production convenience: resolves the uid from FirebaseAuth, writes the
    /// queue to the standard Application Support location, and pushes via
    /// FirestoreRemoteWriter against the default Firestore instance.
    convenience init() {
        self.init(
            currentUID: { Auth.auth().currentUser?.uid },
            queueURL: Self.defaultQueueURL(),
            remote: FirestoreRemoteWriter()
        )
    }

    // MARK: - SyncServicing

    func enqueue(_ operation: PendingSyncOperation) {
        queue.append(operation)
        persistQueue()
    }

    func syncNow() async throws {
        refreshStatusFromAuth()
        guard case .idle = status else { return }
        await runPush()
    }

    // MARK: - Push

    /// Push pass. Walks a snapshot of the queue, encodes each op into a
    /// Firestore-shaped dict (DTO + ownerUid), writes with `merge: true`, and
    /// acks on success. The first remote failure flips `status` to `.failed`
    /// and stops the pass; subsequent retries pick up where this one left off.
    ///
    /// Ops whose `kind` has not yet been wired (Step 3 lands `.project`; the
    /// others arrive in follow-up commits) are skipped without acking — they
    /// stay queued until their commit teaches `encodePush` how to handle them.
    private func runPush() async {
        guard let uid = currentUID(), let remote = remote else { return }
        let snapshot = queue
        guard !snapshot.isEmpty else {
            lastSyncedAt = Date()
            return
        }

        status = .pushing

        for op in snapshot {
            do {
                guard let push = try encodePush(op, ownerUid: uid) else {
                    // Kind not implemented yet — leave the op in the queue
                    // for the commit that adds it.
                    continue
                }
                try await remote.setDocument(
                    collection: push.collection,
                    documentId: op.entityId,
                    fields: push.fields
                )
                acknowledge(operationId: op.operationId)
            } catch {
                status = .failed(error.localizedDescription)
                return
            }
        }

        lastSyncedAt = Date()
        status = .idle
    }

    /// Pure encoder so the push loop is easy to unit-test independently. Returns
    /// `nil` for kinds whose Step 3+ commit hasn't landed yet.
    /// Marked `internal` rather than `private` so the push tests can drive it
    /// directly without going through `runPush`.
    func encodePush(
        _ op: PendingSyncOperation,
        ownerUid: String
    ) throws -> (collection: String, fields: [String: Any])? {
        switch op.kind {
        case .project:
            let doc = try JSONDecoder.devcalSync.decode(ProjectDocument.self, from: op.payload)
            let fields = try Self.flattenForFirestore(doc, ownerUid: ownerUid)
            return ("projects", fields)
        case .transaction:
            let doc = try JSONDecoder.devcalSync.decode(TransactionDocument.self, from: op.payload)
            let fields = try Self.flattenForFirestore(doc, ownerUid: ownerUid)
            return ("transactions", fields)
        case .timeLog, .categoryItem, .milestone:
            // Each of these lands in its own follow-up commit per the Phase 4
            // plan. Until then the queue absorbs writes and the next commit
            // drains them.
            return nil
        }
    }

    /// Convert a Codable DTO into the dict shape Firestore expects (Date →
    /// Timestamp, optionals dropped, nested structs flattened) and inject the
    /// `ownerUid` field that security rules pivot on.
    private static func flattenForFirestore<T: Encodable>(
        _ value: T,
        ownerUid: String
    ) throws -> [String: Any] {
        let encoder = Firestore.Encoder()
        var dict = try encoder.encode(value)
        dict["ownerUid"] = ownerUid
        return dict
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

    // MARK: - Queue access (used by push pass + tests)

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
