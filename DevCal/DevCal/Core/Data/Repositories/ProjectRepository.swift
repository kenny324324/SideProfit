//
//  ProjectRepository.swift
//  DevCal
//
//  The single write boundary for Project records. Views call into this
//  instead of touching `context.insert` / `context.delete` / `context.save`
//  directly. Every successful local write enqueues a PendingSyncOperation
//  so Phase 4 can mirror to Firestore without further view changes.
//
//  All methods are `async throws` even when no awaits are involved — this
//  keeps the surface uniform and lets the sync layer add real awaits later
//  without changing every call site.
//

import Foundation
import SwiftData

@MainActor
final class ProjectRepository {
    private let context: ModelContext
    private let sync: SyncServicing

    init(context: ModelContext, sync: SyncServicing) {
        self.context = context
        self.sync = sync
    }

    // MARK: - Create / Update

    /// Inserts a new project at the top of the list (lowest sortIndex).
    @discardableResult
    func createProject(
        name: String,
        description: String,
        status: ProjectStatus,
        kind: ProjectKind,
        iconImageData: Data?,
        iconPhName: String?,
        iconColorHex: String?,
        launchDate: Date?,
        goalAmount: Double?,
        goalCurrencyCode: String?,
        goalDeadline: Date?
    ) async throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw DataLayerError.invalidInput("Project name cannot be empty.")
        }

        let project = Project(
            name: trimmed,
            description: description,
            status: status,
            kind: kind,
            iconImageData: iconImageData,
            iconPhName: iconPhName,
            iconColorHex: iconColorHex,
            launchDate: launchDate,
            goalAmount: goalAmount,
            goalCurrencyCode: goalCurrencyCode,
            goalDeadline: goalDeadline
        )
        let currentMin = (try context.fetch(FetchDescriptor<Project>()).map(\.sortIndex).min()) ?? 0
        project.sortIndex = currentMin - 1
        context.insert(project)
        try save()
        try enqueueSync(for: project)
        return project
    }

    /// Updates a project in place. Caller mutates fields they care about and
    /// the repo handles the bookkeeping (`updatedAt`, save, sync enqueue).
    func updateProject(_ project: Project, mutate: (Project) -> Void) async throws {
        mutate(project)
        project.updatedAt = Date()
        try save()
        try enqueueSync(for: project)
    }

    /// Stage-2 goal write. Pass `nil` for all three to clear the goal.
    func setGoal(
        on project: Project,
        amount: Double?,
        currencyCode: String?,
        deadline: Date?
    ) async throws {
        project.goalAmount = amount
        project.goalCurrencyCode = currencyCode
        project.goalDeadline = deadline
        project.updatedAt = Date()
        try save()
        try enqueueSync(for: project)
    }

    // MARK: - Delete / Reorder

    func deleteProject(_ project: Project) async throws {
        let document = ProjectDocument(from: project).tombstoned
        context.delete(project)
        try save()
        try enqueueTombstone(document)
    }

    /// Renumber `sortIndex` on the supplied ordered list. Caller is expected
    /// to have already moved items in memory; we just persist the order.
    func reorder(_ orderedProjects: [Project]) async throws {
        for (idx, project) in orderedProjects.enumerated() {
            project.sortIndex = Double(idx)
            project.updatedAt = Date()
        }
        try save()
        for project in orderedProjects {
            try enqueueSync(for: project)
        }
    }

    // MARK: - Internals

    private func save() throws {
        do {
            try context.save()
        } catch {
            throw DataLayerError.localSaveFailed(underlying: error)
        }
    }

    private func enqueueSync(for project: Project) throws {
        let doc = ProjectDocument(from: project)
        let op = try PendingSyncOperation.make(
            entityId: doc.id,
            kind: .project,
            document: doc
        )
        sync.enqueue(op)
    }

    private func enqueueTombstone(_ document: ProjectDocument) throws {
        let op = try PendingSyncOperation.make(
            entityId: document.id,
            kind: .project,
            document: document
        )
        sync.enqueue(op)
    }
}

private extension ProjectDocument {
    /// Returns a copy of this document with `isDeleted = true`. Used to
    /// enqueue a remote tombstone after a local delete.
    var tombstoned: ProjectDocument {
        var copy = self
        copy.isDeleted = true
        copy.updatedAt = Date()
        return copy
    }
}
