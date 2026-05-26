//
//  TimeLogDocument.swift
//  DevCal
//
//  Remote / sync representation of a TimeLog. See ProjectDocument for shared
//  conventions.
//

import Foundation

struct TimeLogDocument: Codable, Equatable, Sendable {
    var id: String
    var projectId: String?
    var hours: Double
    var hourlyRate: Double
    var hourlyCurrencyCode: String
    var note: String
    var date: Date
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

extension TimeLogDocument {
    init(from log: TimeLog) {
        self.id = log.id.uuidString
        self.projectId = log.project?.id.uuidString
        self.hours = log.hours
        self.hourlyRate = log.hourlyRate
        self.hourlyCurrencyCode = log.hourlyCurrencyCode
        self.note = log.note
        self.date = log.date
        self.createdAt = log.createdAt
        self.updatedAt = log.updatedAt
        self.isDeleted = false
    }

    func apply(to log: TimeLog) {
        log.hours = hours
        log.hourlyRate = hourlyRate
        log.hourlyCurrencyCode = hourlyCurrencyCode
        log.note = note
        log.date = date
        log.createdAt = createdAt
        log.updatedAt = updatedAt
    }

    func makeTimeLog() -> TimeLog {
        let log = TimeLog()
        log.id = UUID(uuidString: id) ?? UUID()
        apply(to: log)
        return log
    }
}
