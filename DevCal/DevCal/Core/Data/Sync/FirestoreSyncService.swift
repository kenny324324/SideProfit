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
import SwiftData
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
    private let reader: (any RemoteReading)?
    private let modelContext: ModelContext?
    private let pullPageLimit: Int

    // MARK: - Init

    /// Designated init. Production callers use the convenience init that
    /// resolves the uid from FirebaseAuth and writes via FirestoreRemoteWriter;
    /// tests inject their own closure + a temp queue URL + a mock writer +
    /// (for pull tests) a mock reader and an in-memory ModelContext.
    init(
        currentUID: @escaping @MainActor () -> String?,
        queueURL: URL,
        remote: (any RemoteWriting)? = nil,
        reader: (any RemoteReading)? = nil,
        modelContext: ModelContext? = nil,
        pullPageLimit: Int = 500
    ) {
        self.currentUID = currentUID
        self.queueURL = queueURL
        self.remote = remote
        self.reader = reader
        self.modelContext = modelContext
        self.pullPageLimit = pullPageLimit
        self.queue = Self.loadQueue(at: queueURL)
        refreshStatusFromAuth()
    }

    /// Production convenience: wires FirebaseAuth, the standard queue file,
    /// and Firestore reader/writer instances. The caller hands in the
    /// SwiftData `mainContext` so pull can reconcile cloud → local.
    convenience init(modelContext: ModelContext) {
        self.init(
            currentUID: { Auth.auth().currentUser?.uid },
            queueURL: Self.defaultQueueURL(),
            remote: FirestoreRemoteWriter(),
            reader: FirestoreRemoteReader(),
            modelContext: modelContext
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
        // Bail before pull if push surfaced an error — pulling on top of a
        // failed push could clobber the local change the user just made.
        if case .failed = status { return }
        await runPull()
    }

    // MARK: - Push

    /// Push pass. Walks a snapshot of the queue, encodes each op into a
    /// Firestore-shaped dict (DTO + ownerUid), writes with `merge: true`, and
    /// acks on success. The first remote failure flips `status` to `.failed`
    /// and stops the pass; subsequent retries pick up where this one left off.
    ///
    /// Ops whose `kind` doesn't yet map to a collection are skipped without
    /// acking so no data is lost — but with all five entity kinds wired
    /// (Project / Transaction / TimeLog / CategoryItem / Milestone) this is a
    /// no-op path until a future schema migration introduces a new kind.
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
        case .timeLog:
            let doc = try JSONDecoder.devcalSync.decode(TimeLogDocument.self, from: op.payload)
            let fields = try Self.flattenForFirestore(doc, ownerUid: ownerUid)
            return ("timeLogs", fields)
        case .categoryItem:
            let doc = try JSONDecoder.devcalSync.decode(CategoryItemDocument.self, from: op.payload)
            let fields = try Self.flattenForFirestore(doc, ownerUid: ownerUid)
            return ("categoryItems", fields)
        case .milestone:
            let doc = try JSONDecoder.devcalSync.decode(MilestoneDocument.self, from: op.payload)
            let fields = try Self.flattenForFirestore(doc, ownerUid: ownerUid)
            return ("milestones", fields)
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

    // MARK: - Pull

    /// Pull pass. Pulls each collection scoped to `ownerUid`, then reconciles
    /// against local SwiftData using last-write-wins on `updatedAt`. Tombstones
    /// (`isDeleted == true`) delete the matching local row.
    ///
    /// Project pull lands in Step 4 / commit-1. Transaction / TimeLog /
    /// CategoryItem / Milestone pulls land in follow-up commits — the
    /// `if let reader, let context` guards mean nothing breaks if a kind's
    /// upsert hasn't been written yet.
    ///
    /// Conflict policy: pure LWW, no merge, no user prompt. MVP-acceptable
    /// per Files/Phase_4_Plan_2026-05-26.md.
    private func runPull() async {
        guard let uid = currentUID(),
              let reader = reader,
              let context = modelContext
        else { return }

        status = .pulling

        do {
            // Projects first so transactions / timeLogs / milestones / categoryItems
            // can resolve their projectId relationship by the time they're applied.
            try await pullProjects(uid: uid, reader: reader, context: context)
            try await pullTransactions(uid: uid, reader: reader, context: context)
            try await pullTimeLogs(uid: uid, reader: reader, context: context)
            try await pullCategoryItems(uid: uid, reader: reader, context: context)
            try await pullMilestones(uid: uid, reader: reader, context: context)
            try context.save()
            status = .idle
            lastSyncedAt = Date()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func pullProjects(uid: String, reader: any RemoteReading, context: ModelContext) async throws {
        let docs = try await reader.fetchProjects(ownerUid: uid, limit: pullPageLimit)
        for doc in docs {
            try upsertProject(doc, context: context)
        }
    }

    private func pullTransactions(uid: String, reader: any RemoteReading, context: ModelContext) async throws {
        let docs = try await reader.fetchTransactions(ownerUid: uid, limit: pullPageLimit)
        for doc in docs {
            try upsertTransaction(doc, context: context)
        }
    }

    private func pullTimeLogs(uid: String, reader: any RemoteReading, context: ModelContext) async throws {
        let docs = try await reader.fetchTimeLogs(ownerUid: uid, limit: pullPageLimit)
        for doc in docs {
            try upsertTimeLog(doc, context: context)
        }
    }

    private func pullCategoryItems(uid: String, reader: any RemoteReading, context: ModelContext) async throws {
        let docs = try await reader.fetchCategoryItems(ownerUid: uid, limit: pullPageLimit)
        for doc in docs {
            try upsertCategoryItem(doc, context: context)
        }
    }

    private func pullMilestones(uid: String, reader: any RemoteReading, context: ModelContext) async throws {
        let docs = try await reader.fetchMilestones(ownerUid: uid, limit: pullPageLimit)
        for doc in docs {
            try upsertMilestone(doc, context: context)
        }
    }

    /// Apply one ProjectDocument to local SwiftData. Idempotent.
    /// `internal` so pull tests can drive it directly without a mock reader.
    func upsertProject(_ doc: ProjectDocument, context: ModelContext) throws {
        guard let uuid = UUID(uuidString: doc.id) else { return }

        // Small dataset (MVP indie users have <100 projects each). A full
        // fetch + .first(where:) avoids #Predicate macro pitfalls around
        // captured values and works fine for the launch window.
        let all = try context.fetch(FetchDescriptor<Project>())
        let existing = all.first { $0.id == uuid }

        if doc.isDeleted {
            if let existing { context.delete(existing) }
            return
        }

        if let existing {
            // LWW on updatedAt. Strictly greater so a same-timestamp pull is
            // a no-op (avoids touching mainContext for nothing).
            if doc.updatedAt > existing.updatedAt {
                doc.apply(to: existing)
            }
        } else {
            let new = doc.makeProject()
            context.insert(new)
        }
    }

    /// Apply one TransactionDocument to local SwiftData. Hydrates the
    /// `project` relationship by looking up the parent Project by id.
    /// `internal` so pull tests can drive it directly without a mock reader.
    func upsertTransaction(_ doc: TransactionDocument, context: ModelContext) throws {
        guard let uuid = UUID(uuidString: doc.id) else { return }

        let all = try context.fetch(FetchDescriptor<Transaction>())
        let existing = all.first { $0.id == uuid }

        if doc.isDeleted {
            if let existing { context.delete(existing) }
            return
        }

        let project = try resolveProject(byId: doc.projectId, context: context)

        if let existing {
            if doc.updatedAt > existing.updatedAt {
                doc.apply(to: existing)
                existing.project = project
            }
        } else {
            let new = doc.makeTransaction()
            new.project = project
            context.insert(new)
        }
    }

    /// Apply one TimeLogDocument to local SwiftData. Hydrates the `project`
    /// relationship the same way transactions do.
    /// `internal` so pull tests can drive it directly without a mock reader.
    func upsertTimeLog(_ doc: TimeLogDocument, context: ModelContext) throws {
        guard let uuid = UUID(uuidString: doc.id) else { return }

        let all = try context.fetch(FetchDescriptor<TimeLog>())
        let existing = all.first { $0.id == uuid }

        if doc.isDeleted {
            if let existing { context.delete(existing) }
            return
        }

        let project = try resolveProject(byId: doc.projectId, context: context)

        if let existing {
            if doc.updatedAt > existing.updatedAt {
                doc.apply(to: existing)
                existing.project = project
            }
        } else {
            let new = doc.makeTimeLog()
            new.project = project
            context.insert(new)
        }
    }

    /// Apply one CategoryItemDocument to local SwiftData. Re-resolves the
    /// many-to-many `projects` array from `projectIds` so a remote allocation
    /// change (added / removed project) lands on the local row.
    /// `internal` so pull tests can drive it directly without a mock reader.
    func upsertCategoryItem(_ doc: CategoryItemDocument, context: ModelContext) throws {
        guard let uuid = UUID(uuidString: doc.id) else { return }

        let all = try context.fetch(FetchDescriptor<CategoryItem>())
        let existing = all.first { $0.id == uuid }

        if doc.isDeleted {
            if let existing { context.delete(existing) }
            return
        }

        let projects = try resolveProjects(byIds: doc.projectIds, context: context)

        if let existing {
            if doc.updatedAt > existing.updatedAt {
                doc.apply(to: existing)
                existing.projects = projects
            }
        } else {
            let new = doc.makeCategoryItem()
            new.projects = projects
            context.insert(new)
        }
    }

    /// Apply one MilestoneDocument to local SwiftData. Milestone has no
    /// `updatedAt` in SwiftData yet (see MilestoneDocument.swift), so LWW
    /// pivots on local `createdAt` against `doc.updatedAt` — which the DTO
    /// mirrors from `createdAt` on the write side. Manual milestones are
    /// generally write-once today; this anchor is good enough for MVP.
    /// `internal` so pull tests can drive it directly without a mock reader.
    func upsertMilestone(_ doc: MilestoneDocument, context: ModelContext) throws {
        guard let uuid = UUID(uuidString: doc.id) else { return }

        let all = try context.fetch(FetchDescriptor<Milestone>())
        let existing = all.first { $0.id == uuid }

        if doc.isDeleted {
            if let existing { context.delete(existing) }
            return
        }

        let project = try resolveProject(byId: doc.projectId, context: context)

        if let existing {
            if doc.updatedAt > existing.createdAt {
                doc.apply(to: existing)
                existing.project = project
            }
        } else {
            let new = doc.makeMilestone()
            new.project = project
            context.insert(new)
        }
    }

    /// Resolve an array of project UUID strings to live `Project` rows.
    /// Drops ids that don't have a local Project yet (orphaned references).
    private func resolveProjects(byIds projectIdStrings: [String], context: ModelContext) throws -> [Project] {
        guard !projectIdStrings.isEmpty else { return [] }
        let all = try context.fetch(FetchDescriptor<Project>())
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return projectIdStrings.compactMap { idString in
            guard let uuid = UUID(uuidString: idString) else { return nil }
            return byId[uuid]
        }
    }

    /// Look up a `Project` by its UUID string. Returns nil if `projectIdString`
    /// is nil or the project hasn't been pulled yet — sync layer treats nil as
    /// orphaned per the DTO comment.
    private func resolveProject(byId projectIdString: String?, context: ModelContext) throws -> Project? {
        guard let projectIdString,
              let projectUUID = UUID(uuidString: projectIdString)
        else { return nil }
        let all = try context.fetch(FetchDescriptor<Project>())
        return all.first { $0.id == projectUUID }
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
