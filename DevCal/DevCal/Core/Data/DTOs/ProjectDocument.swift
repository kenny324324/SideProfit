//
//  ProjectDocument.swift
//  DevCal
//
//  Remote / sync representation of a Project. Plain Codable with no SwiftData
//  dependencies so it can be serialized to Firestore (or any other backend)
//  without dragging the local store along.
//
//  Conventions for every *Document in this folder:
//  - `id` is the stable string form of the local UUID.
//  - All dates are stored as Date; the sync layer converts to Firestore.Timestamp at the boundary.
//  - Enums are stored by raw string.
//  - Original currency is preserved exactly as the local model.
//  - `updatedAt` is required on every document; sync uses last-write-wins by this.
//  - `isDeleted` is a tombstone — set true when the local record is deleted so
//    other devices can remove their copy on the next pull.
//

import Foundation

struct ProjectDocument: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var projectDescription: String
    var statusRaw: String
    var kindRaw: String
    var iconImageData: Data?
    var iconPhName: String?
    var iconColorHex: String?
    var launchDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var sortIndex: Double
    var breakevenReachedAt: Date?
    var goalAmount: Double?
    var goalCurrencyCode: String?
    var goalDeadline: Date?
    var isDeleted: Bool
}

extension ProjectDocument {
    init(from project: Project) {
        self.id = project.id.uuidString
        self.name = project.name
        self.projectDescription = project.projectDescription
        self.statusRaw = project.statusRaw
        self.kindRaw = project.kindRaw
        self.iconImageData = project.iconImageData
        self.iconPhName = project.iconPhName
        self.iconColorHex = project.iconColorHex
        self.launchDate = project.launchDate
        self.createdAt = project.createdAt
        self.updatedAt = project.updatedAt
        self.archivedAt = project.archivedAt
        self.sortIndex = project.sortIndex
        self.breakevenReachedAt = project.breakevenReachedAt
        self.goalAmount = project.goalAmount
        self.goalCurrencyCode = project.goalCurrencyCode
        self.goalDeadline = project.goalDeadline
        self.isDeleted = false
    }

    /// Applies this document's fields onto an existing SwiftData Project. Does
    /// not touch relationships (transactions / timeLogs / milestones / categoryItems);
    /// the sync layer is responsible for resolving those by id.
    func apply(to project: Project) {
        project.name = name
        project.projectDescription = projectDescription
        project.statusRaw = statusRaw
        project.kindRaw = kindRaw
        project.iconImageData = iconImageData
        project.iconPhName = iconPhName
        project.iconColorHex = iconColorHex
        project.launchDate = launchDate
        project.createdAt = createdAt
        project.updatedAt = updatedAt
        project.archivedAt = archivedAt
        project.sortIndex = sortIndex
        project.breakevenReachedAt = breakevenReachedAt
        project.goalAmount = goalAmount
        project.goalCurrencyCode = goalCurrencyCode
        project.goalDeadline = goalDeadline
    }

    /// Constructs a fresh SwiftData Project from this document. Used on pull
    /// when no local record exists for `id`.
    func makeProject() -> Project {
        let project = Project()
        project.id = UUID(uuidString: id) ?? UUID()
        apply(to: project)
        return project
    }
}
