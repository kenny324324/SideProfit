//
//  TimeLogRepository.swift
//  DevCal
//
//  Write boundary for TimeLog records.
//

import Foundation
import SwiftData

@MainActor
final class TimeLogRepository {
    private let context: ModelContext
    private let sync: SyncServicing

    init(context: ModelContext, sync: SyncServicing) {
        self.context = context
        self.sync = sync
    }

    @discardableResult
    func createTimeLog(
        project: Project,
        hours: Double,
        hourlyRate: Double,
        hourlyCurrencyCode: String,
        note: String,
        date: Date
    ) async throws -> TimeLog {
        guard hours > 0 else {
            throw DataLayerError.invalidInput("Hours must be greater than zero.")
        }
        let log = TimeLog(
            hours: hours,
            hourlyRate: hourlyRate,
            hourlyCurrencyCode: hourlyCurrencyCode,
            note: note,
            date: date,
            project: project
        )
        context.insert(log)
        try save()
        try enqueueSync(for: log)
        return log
    }

    func updateTimeLog(
        _ log: TimeLog,
        hours: Double,
        hourlyRate: Double,
        hourlyCurrencyCode: String,
        note: String,
        date: Date
    ) async throws {
        guard hours > 0 else {
            throw DataLayerError.invalidInput("Hours must be greater than zero.")
        }
        log.hours = hours
        log.hourlyRate = hourlyRate
        log.hourlyCurrencyCode = hourlyCurrencyCode
        log.note = note
        log.date = date
        log.updatedAt = Date()
        try save()
        try enqueueSync(for: log)
    }

    func deleteTimeLog(_ log: TimeLog) async throws {
        let document = TimeLogDocument(from: log).tombstoned
        context.delete(log)
        try save()
        try enqueueTombstone(document)
    }

    // MARK: - Internals

    private func save() throws {
        do {
            try context.save()
        } catch {
            throw DataLayerError.localSaveFailed(underlying: error)
        }
    }

    private func enqueueSync(for log: TimeLog) throws {
        let doc = TimeLogDocument(from: log)
        let op = try PendingSyncOperation.make(
            entityId: doc.id,
            kind: .timeLog,
            document: doc
        )
        sync.enqueue(op)
    }

    private func enqueueTombstone(_ document: TimeLogDocument) throws {
        let op = try PendingSyncOperation.make(
            entityId: document.id,
            kind: .timeLog,
            document: document
        )
        sync.enqueue(op)
    }
}

private extension TimeLogDocument {
    var tombstoned: TimeLogDocument {
        var copy = self
        copy.isDeleted = true
        copy.updatedAt = Date()
        return copy
    }
}
