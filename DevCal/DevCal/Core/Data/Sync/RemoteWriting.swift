//
//  RemoteWriting.swift
//  DevCal
//
//  Thin write-side seam between FirestoreSyncService and FirebaseFirestore.
//  Exists so unit tests can verify the push pass (collection / docId / fields)
//  without booting the emulator or touching the network.
//
//  The protocol takes `[String: Any]` rather than a Codable value because
//  Firestore.Encoder is the canonical way to flatten our DTOs (Date →
//  Timestamp, Optional handling, nested encoding) and the sync service has
//  to inject `ownerUid` per-doc before the write. Doing both at the dict
//  layer keeps the seam dumb.
//

import Foundation
import FirebaseFirestore

@MainActor
protocol RemoteWriting: AnyObject {
    /// Upserts `fields` into `collection/documentId` with merge semantics.
    /// Throws on any Firestore error so the caller can surface it as
    /// `SyncStatus.failed(...)`.
    func setDocument(
        collection: String,
        documentId: String,
        fields: [String: Any]
    ) async throws
}

/// Production implementation. Talks directly to the default Firestore
/// instance (configured by `FirebaseApp.configure()` in DevCalApp.init).
@MainActor
final class FirestoreRemoteWriter: RemoteWriting {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func setDocument(
        collection: String,
        documentId: String,
        fields: [String: Any]
    ) async throws {
        try await db
            .collection(collection)
            .document(documentId)
            .setData(fields, merge: true)
    }
}
