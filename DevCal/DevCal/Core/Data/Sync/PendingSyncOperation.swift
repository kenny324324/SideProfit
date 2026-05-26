//
//  PendingSyncOperation.swift
//  DevCal
//
//  Queue entry produced by a Repository whenever a local write needs to be
//  mirrored to Firestore. Phase 0 only defines the shape; the actual queue
//  and persistence layer land in Phase 4.
//
//  Design notes:
//  - Each operation carries the FULL DTO snapshot at the time of the local
//    write. Replaying the queue is therefore independent of the current
//    SwiftData state — the remote ends up reflecting what the user did,
//    not what the local DB happens to look like when sync runs.
//  - Deletes use a tombstone DTO (`isDeleted = true`) so the same code path
//    handles them as a normal write.
//

import Foundation

/// Which collection / aggregate the operation targets. Used by the sync
/// service to pick the right Firestore path and decode the payload.
enum SyncEntityKind: String, Codable, Sendable {
    case project
    case transaction
    case timeLog
    case categoryItem
    case milestone
}

/// A single pending mirror operation. `payload` is the JSON-encoded DTO so the
/// queue can be persisted as plain Data without locking each entry to a typed
/// generic at the storage layer.
struct PendingSyncOperation: Codable, Equatable, Sendable {
    /// Stable id of the queue entry itself (not the entity). Used so the sync
    /// engine can dedupe and acknowledge specific ops.
    var operationId: String
    /// Entity id (e.g. `project.id.uuidString`). Used to coalesce repeated
    /// writes for the same record into a single push.
    var entityId: String
    var kind: SyncEntityKind
    /// JSON-encoded DTO snapshot. Decoded into the corresponding *Document
    /// type by the sync engine.
    var payload: Data
    var enqueuedAt: Date

    init(
        operationId: String = UUID().uuidString,
        entityId: String,
        kind: SyncEntityKind,
        payload: Data,
        enqueuedAt: Date = Date()
    ) {
        self.operationId = operationId
        self.entityId = entityId
        self.kind = kind
        self.payload = payload
        self.enqueuedAt = enqueuedAt
    }
}

extension PendingSyncOperation {
    /// Convenience encoder so repositories can enqueue without each one
    /// repeating the JSON dance.
    static func make<T: Encodable>(
        entityId: String,
        kind: SyncEntityKind,
        document: T
    ) throws -> PendingSyncOperation {
        let payload = try JSONEncoder.devcalSync.encode(document)
        return PendingSyncOperation(entityId: entityId, kind: kind, payload: payload)
    }
}

extension JSONEncoder {
    /// Single JSON encoder configured for the sync queue. ISO-8601 dates so
    /// the same payload survives a process restart without timezone drift.
    static let devcalSync: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let devcalSync: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
