//
//  CategoryItemSplitTests.swift
//  DevCalTests
//
//  Tests for the shared-expense split logic introduced 2026-05-19. Keyed-
//  weights migration (Phase 0) means weighted splits should survive any
//  project reordering — these cases also cover the equal / invalid fallback
//  behavior so a future regression can't silently change everyone's
//  per-project share.
//

import Testing
import Foundation
import SwiftData
@testable import DevCal

@MainActor
struct CategoryItemSplitTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Project.self,
            Transaction.self,
            TimeLog.self,
            Milestone.self,
            CategoryItem.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    // MARK: - Equal split

    @Test("Equal split divides totalAmount evenly across allocated projects")
    func equalSplit() throws {
        let context = try makeContext()
        let a = Project(name: "A"); context.insert(a)
        let b = Project(name: "B"); context.insert(b)
        let c = Project(name: "C"); context.insert(c)

        let item = CategoryItem(
            name: "shared",
            totalAmount: 300,
            isShared: true,
            splitMode: .equal,
            projects: [a, b, c]
        )
        context.insert(item)

        #expect(item.amount(for: a) == 100)
        #expect(item.amount(for: b) == 100)
        #expect(item.amount(for: c) == 100)
    }

    // MARK: - Weighted split

    @Test("Weighted split honors weightsByProjectId map regardless of order")
    func weightedSplitByKey() throws {
        let context = try makeContext()
        let a = Project(name: "A"); context.insert(a)
        let b = Project(name: "B"); context.insert(b)

        let weights: [String: Double] = [
            a.id.uuidString: 3,
            b.id.uuidString: 1
        ]
        let item = CategoryItem(
            name: "shared",
            totalAmount: 400,
            isShared: true,
            splitMode: .weighted,
            weightsByProjectId: weights,
            projects: [a, b]
        )
        context.insert(item)

        #expect(item.amount(for: a) == 300) // 400 * (3/4)
        #expect(item.amount(for: b) == 100) // 400 * (1/4)

        // Flip the visible order — the share follows the project, not the index.
        item.projects = [b, a]
        #expect(item.amount(for: a) == 300)
        #expect(item.amount(for: b) == 100)
    }

    // MARK: - Edge cases

    @Test("Project outside the allocation gets 0 from a shared item")
    func nonMemberProjectReturnsZero() throws {
        let context = try makeContext()
        let inside = Project(name: "in"); context.insert(inside)
        let outside = Project(name: "out"); context.insert(outside)
        let other = Project(name: "other"); context.insert(other)

        let item = CategoryItem(
            name: "shared",
            totalAmount: 100,
            isShared: true,
            splitMode: .equal,
            projects: [inside, other]
        )
        context.insert(item)

        #expect(item.amount(for: outside) == 0)
    }

    @Test("Weighted mode with nil/empty weights falls back to equal split")
    func invalidWeightsFallback() throws {
        let context = try makeContext()
        let a = Project(name: "A"); context.insert(a)
        let b = Project(name: "B"); context.insert(b)

        // weightsByProjectId nil → fall back to equal.
        let item = CategoryItem(
            name: "shared",
            totalAmount: 100,
            isShared: true,
            splitMode: .weighted,
            weightsByProjectId: nil,
            projects: [a, b]
        )
        context.insert(item)
        #expect(item.amount(for: a) == 50)
        #expect(item.amount(for: b) == 50)

        // All zero weights → still fall back to equal so the user never sees 0
        // when the UI didn't populate weights yet.
        item.weightsByProjectId = [
            a.id.uuidString: 0,
            b.id.uuidString: 0
        ]
        #expect(item.amount(for: a) == 50)
        #expect(item.amount(for: b) == 50)
    }

    @Test("Dedicated (non-shared) items always return the full amount")
    func dedicatedItem() throws {
        let context = try makeContext()
        let a = Project(name: "A"); context.insert(a)
        let item = CategoryItem(
            name: "dedicated",
            totalAmount: 1500,
            isShared: false,
            projects: [a]
        )
        context.insert(item)
        #expect(item.amount(for: a) == 1500)
    }
}
