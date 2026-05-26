//
//  DTOMappingTests.swift
//  DevCalTests
//
//  Round-trip every SwiftData model through its Codable *Document so we can
//  catch field drift before Phase 4 wires Firestore to the same DTOs.
//

import Testing
import Foundation
import SwiftData
@testable import DevCal

@MainActor
struct DTOMappingTests {

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

    // MARK: - Project

    @Test("ProjectDocument round-trips required + optional fields")
    func projectRoundTrip() throws {
        let context = try makeContext()
        let project = Project(
            name: "ShipSwift",
            description: "test",
            status: .live,
            kind: .template,
            iconImageData: Data([0xDE, 0xAD]),
            iconPhName: "rocket",
            iconColorHex: "#FF8800",
            launchDate: Date(timeIntervalSince1970: 1_000),
            goalAmount: 500_000,
            goalCurrencyCode: "USD",
            goalDeadline: Date(timeIntervalSince1970: 2_000)
        )
        project.breakevenReachedAt = Date(timeIntervalSince1970: 500)
        project.sortIndex = 7
        context.insert(project)

        let doc = ProjectDocument(from: project)
        let encoded = try JSONEncoder.devcalSync.encode(doc)
        let decoded = try JSONDecoder.devcalSync.decode(ProjectDocument.self, from: encoded)

        #expect(decoded == doc)

        let rebuilt = decoded.makeProject()
        #expect(rebuilt.id == project.id)
        #expect(rebuilt.name == project.name)
        #expect(rebuilt.statusRaw == project.statusRaw)
        #expect(rebuilt.kindRaw == project.kindRaw)
        #expect(rebuilt.iconImageData == project.iconImageData)
        #expect(rebuilt.iconPhName == project.iconPhName)
        #expect(rebuilt.iconColorHex == project.iconColorHex)
        #expect(rebuilt.launchDate == project.launchDate)
        #expect(rebuilt.goalAmount == project.goalAmount)
        #expect(rebuilt.goalCurrencyCode == project.goalCurrencyCode)
        #expect(rebuilt.goalDeadline == project.goalDeadline)
        #expect(rebuilt.breakevenReachedAt == project.breakevenReachedAt)
        #expect(rebuilt.sortIndex == project.sortIndex)
    }

    // MARK: - Transaction

    @Test("TransactionDocument preserves enum raw values + deterministic id")
    func transactionRoundTrip() throws {
        let context = try makeContext()
        let project = Project(name: "P"); context.insert(project)

        let txn = Transaction(
            type: .income,
            category: .appSales,
            name: "Sub income",
            iconBrandKey: "stripe",
            iconFallbackName: "credit-card",
            iconColorHex: "#11AA22",
            originalAmount: 199,
            originalCurrencyCode: "USD",
            note: "first payout",
            date: Date(timeIntervalSince1970: 3_000),
            project: project,
            sourceCategoryItemID: UUID(),
            deterministicID: "abc_def_20260101"
        )
        context.insert(txn)

        let doc = TransactionDocument(from: txn)
        let encoded = try JSONEncoder.devcalSync.encode(doc)
        let decoded = try JSONDecoder.devcalSync.decode(TransactionDocument.self, from: encoded)
        #expect(decoded == doc)

        let rebuilt = decoded.makeTransaction()
        #expect(rebuilt.typeRaw == TransactionType.income.rawValue)
        #expect(rebuilt.categoryRaw == TransactionCategory.appSales.rawValue)
        #expect(rebuilt.iconBrandKey == "stripe")
        #expect(rebuilt.iconFallbackName == "credit-card")
        #expect(rebuilt.iconColorHex == "#11AA22")
        #expect(rebuilt.originalAmount == 199)
        #expect(rebuilt.originalCurrencyCode == "USD")
        #expect(rebuilt.note == "first payout")
        #expect(rebuilt.date == txn.date)
        #expect(rebuilt.sourceCategoryItemID == txn.sourceCategoryItemID)
        #expect(rebuilt.deterministicID == "abc_def_20260101")
    }

    // MARK: - TimeLog

    @Test("TimeLogDocument round-trips currency + rate")
    func timeLogRoundTrip() throws {
        let context = try makeContext()
        let project = Project(name: "P"); context.insert(project)

        let log = TimeLog(
            hours: 3.5,
            hourlyRate: 600,
            hourlyCurrencyCode: "TWD",
            note: "shipped settings",
            date: Date(timeIntervalSince1970: 4_000),
            project: project
        )
        context.insert(log)

        let doc = TimeLogDocument(from: log)
        let encoded = try JSONEncoder.devcalSync.encode(doc)
        let decoded = try JSONDecoder.devcalSync.decode(TimeLogDocument.self, from: encoded)
        #expect(decoded == doc)

        let rebuilt = decoded.makeTimeLog()
        #expect(rebuilt.hours == 3.5)
        #expect(rebuilt.hourlyRate == 600)
        #expect(rebuilt.hourlyCurrencyCode == "TWD")
        #expect(rebuilt.note == "shipped settings")
        #expect(rebuilt.date == log.date)
    }

    // MARK: - CategoryItem

    @Test("CategoryItemDocument carries weightsByProjectId + projectIds")
    func categoryItemRoundTrip() throws {
        let context = try makeContext()
        let a = Project(name: "A"); context.insert(a)
        let b = Project(name: "B"); context.insert(b)

        let weights = [
            a.id.uuidString: 2.0,
            b.id.uuidString: 1.0
        ]
        let item = CategoryItem(
            name: "shared",
            category: .aiTools,
            totalAmount: 600,
            originalCurrencyCode: "USD",
            billingType: .monthly,
            brandIconKey: "openai",
            fallbackIconName: "robot",
            iconColorHex: "#000000",
            nextDueDate: Date(timeIntervalSince1970: 5_000),
            isActive: true,
            isShared: true,
            splitMode: .weighted,
            weightsByProjectId: weights,
            projects: [a, b]
        )
        context.insert(item)

        let doc = CategoryItemDocument(from: item)
        let encoded = try JSONEncoder.devcalSync.encode(doc)
        let decoded = try JSONDecoder.devcalSync.decode(CategoryItemDocument.self, from: encoded)
        #expect(decoded == doc)

        #expect(decoded.weightsByProjectId == weights)
        #expect(Set(decoded.projectIds) == Set([a.id.uuidString, b.id.uuidString]))
        #expect(decoded.billingTypeRaw == BillingType.monthly.rawValue)
        #expect(decoded.splitModeRaw == SplitMode.weighted.rawValue)
    }

    // MARK: - Milestone

    @Test("MilestoneDocument preserves auto/manual + type raw")
    func milestoneRoundTrip() throws {
        let context = try makeContext()
        let project = Project(name: "P"); context.insert(project)

        let milestone = Milestone(
            type: .breakEvenReached,
            title: "Break-even!",
            note: "🎉",
            date: Date(timeIntervalSince1970: 7_000),
            autoGenerated: true,
            project: project
        )
        context.insert(milestone)

        let doc = MilestoneDocument(from: milestone)
        let encoded = try JSONEncoder.devcalSync.encode(doc)
        let decoded = try JSONDecoder.devcalSync.decode(MilestoneDocument.self, from: encoded)
        #expect(decoded == doc)

        let rebuilt = decoded.makeMilestone()
        #expect(rebuilt.typeRaw == MilestoneType.breakEvenReached.rawValue)
        #expect(rebuilt.title == "Break-even!")
        #expect(rebuilt.autoGenerated == true)
    }
}
