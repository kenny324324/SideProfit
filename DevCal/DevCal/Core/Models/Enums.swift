//
//  Enums.swift
//  DevCal
//
//  Shared enums for projects, transactions, and milestones. All cases carry their
//  own icon + LocalizedStringKey for UI use; raw values are stable Strings safe for
//  SwiftData / future Firestore serialization.
//

import SwiftUI
import PhosphorSymbols

// MARK: - Project

/// Which side of the two-stage progress system a project is in.
///
/// - `stageOne`: pre break-even; progress = totalIncome / totalExpenses.
/// - `justReached`: break-even hit, but user hasn't set a goal yet (celebration state).
/// - `stageTwo`: user has set a goal; progress = totalIncome / goalAmount.
enum ProgressStage {
    case stageOne
    case justReached
    case stageTwo
}

enum ProjectKind: String, CaseIterable, Codable, Identifiable {
    case app
    case web
    case game
    case browserExtension
    case plugin
    case template
    case assets
    case course
    case other

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .app: "App"
        case .web: "Web"
        case .game: "Game"
        case .browserExtension: "Extension"
        case .plugin: "Plugin"
        case .template: "Template"
        case .assets: "Assets"
        case .course: "Course"
        case .other: "Other"
        }
    }

    var icon: Image {
        switch self {
        case .app: Image(ph: "device-mobile")
        case .web: Image(ph: "globe")
        case .game: Image(ph: "game-controller")
        case .browserExtension: Image(ph: "puzzle-piece")
        case .plugin: Image(ph: "plug")
        case .template: Image(ph: "squares-four")
        case .assets: Image(ph: "image-square")
        case .course: Image(ph: "graduation-cap")
        case .other: Image(ph: "dots-three-circle")
        }
    }

    /// Phosphor symbol name (no weight suffix) — used as the project's icon
    /// fallback when the user hasn't uploaded or picked a custom one.
    var defaultPhName: String {
        switch self {
        case .app: "device-mobile"
        case .web: "globe"
        case .game: "game-controller"
        case .browserExtension: "puzzle-piece"
        case .plugin: "plug"
        case .template: "squares-four"
        case .assets: "image-square"
        case .course: "graduation-cap"
        case .other: "dots-three-circle"
        }
    }
}

enum ProjectStatus: String, CaseIterable, Codable, Identifiable {
    case planned
    case building
    case live
    case paused

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .planned: "Planned"
        case .building: "Building"
        case .live: "Live"
        case .paused: "Paused"
        }
    }

    var icon: Image {
        switch self {
        case .planned: Image(ph: "lightbulb")
        case .building: Image(ph: "hammer")
        case .live: Image(ph: "seal-check")
        case .paused: Image(ph: "pause-circle")
        }
    }

    var tint: Color {
        switch self {
        case .planned: .gray
        case .building: Theme.brand
        case .live: Theme.income
        case .paused: .secondary
        }
    }
}

// MARK: - Transaction

enum TransactionType: String, CaseIterable, Codable, Identifiable {
    case income
    case expense

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        }
    }

    var icon: Image {
        switch self {
        case .income: Image(ph: "arrow-circle-down")
        case .expense: Image(ph: "arrow-circle-up")
        }
    }

    var tint: Color {
        switch self {
        case .income: Theme.income
        case .expense: Theme.expense
        }
    }
}

enum TransactionCategory: String, CaseIterable, Codable, Identifiable {
    // Income
    case appSales
    case subscriptions
    case adRevenue
    case sponsorship
    case otherIncome

    // Expense
    case server
    case api
    case appStoreFee
    case googlePlayFee
    case domain
    case design
    case advertising
    case outsourcing
    case software
    case aiTools
    case testingDevices
    case devTools
    case otherExpense

    var id: String { rawValue }

    var type: TransactionType {
        switch self {
        case .appSales, .subscriptions, .adRevenue, .sponsorship, .otherIncome:
            return .income
        default:
            return .expense
        }
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .appSales: "App Sales"
        case .subscriptions: "Subscriptions"
        case .adRevenue: "Ad Revenue"
        case .sponsorship: "Sponsorship"
        case .otherIncome: "Other Income"
        case .server: "Server"
        case .api: "API"
        case .appStoreFee: "App Store Fee"
        case .googlePlayFee: "Google Play Fee"
        case .domain: "Domain"
        case .design: "Design"
        case .advertising: "Ads"
        case .outsourcing: "Outsourcing"
        case .software: "Software"
        case .aiTools: "AI Tools"
        case .testingDevices: "Testing Devices"
        case .devTools: "Dev Tools"
        case .otherExpense: "Other Expense"
        }
    }

    @ViewBuilder
    var icon: some View {
        switch self {
        case .appSales: Image(ph: "device-mobile")
        case .subscriptions: Image(ph: "arrows-clockwise")
        case .adRevenue: Image(ph: "megaphone")
        case .sponsorship: Image(ph: "heart")
        case .otherIncome: Image(ph: "plus-circle")
        case .server: Image(ph: "hard-drives")
        case .api: Image(ph: "network")
        case .appStoreFee: BrandIconRegistry.image(for: "apple")
        case .googlePlayFee: BrandIconRegistry.image(for: "google")
        case .domain: Image(ph: "globe")
        case .design: Image(ph: "paint-brush")
        case .advertising: Image(ph: "speaker-high")
        case .outsourcing: Image(ph: "users")
        case .software: Image(ph: "app-window")
        case .aiTools: BrandIconRegistry.image(for: "openai")
        case .testingDevices: Image(ph: "devices")
        case .devTools: Image(ph: "wrench")
        case .otherExpense: Image(ph: "dots-three-circle")
        }
    }

    static func categories(for type: TransactionType) -> [TransactionCategory] {
        allCases.filter { $0.type == type }
    }
}

// MARK: - Milestone

enum MilestoneType: String, CaseIterable, Codable, Identifiable {
    case firstTransaction
    case firstIncome
    case firstExpense
    case firstProfitableMonth
    case breakEven25
    case breakEven50
    case breakEven75
    case breakEvenReached
    case firstThousandEarned
    case firstTenThousandEarned
    case manual

    var id: String { rawValue }

    var defaultTitle: LocalizedStringKey {
        switch self {
        case .firstTransaction: "First transaction logged"
        case .firstIncome: "First revenue earned"
        case .firstExpense: "First expense tracked"
        case .firstProfitableMonth: "First profitable month"
        case .breakEven25: "25% to break-even"
        case .breakEven50: "Halfway to break-even"
        case .breakEven75: "75% to break-even"
        case .breakEvenReached: "Reached break-even"
        case .firstThousandEarned: "First $1,000 earned"
        case .firstTenThousandEarned: "First $10,000 earned"
        case .manual: "Custom milestone"
        }
    }

    var icon: Image {
        switch self {
        case .firstTransaction: Image(ph: "file-text")
        case .firstIncome: Image(ph: "currency-circle-dollar")
        case .firstExpense: Image(ph: "credit-card")
        case .firstProfitableMonth: Image(ph: "chart-line-up")
        case .breakEven25, .breakEven50, .breakEven75: Image(ph: "gauge")
        case .breakEvenReached: Image(ph: "seal-check")
        case .firstThousandEarned, .firstTenThousandEarned: Image(ph: "star")
        case .manual: Image(ph: "flag")
        }
    }

    var tint: Color {
        switch self {
        case .firstTransaction, .firstExpense: .blue
        case .firstIncome, .firstThousandEarned, .firstTenThousandEarned: .yellow
        case .firstProfitableMonth, .breakEvenReached: Theme.income
        case .breakEven25, .breakEven50, .breakEven75: Theme.brand
        case .manual: .purple
        }
    }
}
