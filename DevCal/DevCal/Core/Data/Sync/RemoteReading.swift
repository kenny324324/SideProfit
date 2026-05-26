//
//  RemoteReading.swift
//  DevCal
//
//  Read-side counterpart to RemoteWriting. Exposes one method per entity
//  kind (instead of a generic existential) so the mock used by pull tests
//  stays trivial — each fixture is just a stored array of typed DTOs.
//
//  The production impl decodes Firestore snapshots through `Firestore.Decoder`
//  inside this file, keeping FirestoreSyncService unaware of `Timestamp` vs
//  `Date` shape differences between the SDK and unit tests.
//

import Foundation
import FirebaseFirestore

@MainActor
protocol RemoteReading: AnyObject {
    func fetchProjects(ownerUid: String, limit: Int) async throws -> [ProjectDocument]
    func fetchTransactions(ownerUid: String, limit: Int) async throws -> [TransactionDocument]
    func fetchTimeLogs(ownerUid: String, limit: Int) async throws -> [TimeLogDocument]
    func fetchCategoryItems(ownerUid: String, limit: Int) async throws -> [CategoryItemDocument]
    func fetchMilestones(ownerUid: String, limit: Int) async throws -> [MilestoneDocument]
}

@MainActor
final class FirestoreRemoteReader: RemoteReading {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchProjects(ownerUid: String, limit: Int) async throws -> [ProjectDocument] {
        try await fetch(collection: "projects", ownerUid: ownerUid, limit: limit)
    }

    func fetchTransactions(ownerUid: String, limit: Int) async throws -> [TransactionDocument] {
        try await fetch(collection: "transactions", ownerUid: ownerUid, limit: limit)
    }

    func fetchTimeLogs(ownerUid: String, limit: Int) async throws -> [TimeLogDocument] {
        try await fetch(collection: "timeLogs", ownerUid: ownerUid, limit: limit)
    }

    func fetchCategoryItems(ownerUid: String, limit: Int) async throws -> [CategoryItemDocument] {
        try await fetch(collection: "categoryItems", ownerUid: ownerUid, limit: limit)
    }

    func fetchMilestones(ownerUid: String, limit: Int) async throws -> [MilestoneDocument] {
        try await fetch(collection: "milestones", ownerUid: ownerUid, limit: limit)
    }

    private func fetch<T: Decodable>(
        collection: String,
        ownerUid: String,
        limit: Int
    ) async throws -> [T] {
        let snapshot = try await db
            .collection(collection)
            .whereField("ownerUid", isEqualTo: ownerUid)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        let decoder = Firestore.Decoder()
        return try snapshot.documents.map { try decoder.decode(T.self, from: $0.data()) }
    }
}
