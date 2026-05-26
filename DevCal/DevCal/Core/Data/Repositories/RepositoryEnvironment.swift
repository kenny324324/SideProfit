//
//  RepositoryEnvironment.swift
//  DevCal
//
//  SwiftUI environment keys for the data layer. Views pull the repository
//  they need via `@Environment(\.projectRepository)` etc. — keeps the View
//  files free of `ModelContext` plumbing and matches how AuthService /
//  ExchangeRateService are already wired.
//
//  All defaults are `nil`; the App layer injects real instances at the root,
//  and any view that asks for a repository when the app forgot to inject one
//  will crash loudly during dev. That's preferable to a silent no-op repo
//  that swallows writes.
//

import SwiftUI

private struct ProjectRepositoryKey: EnvironmentKey {
    static let defaultValue: ProjectRepository? = nil
}

private struct TransactionRepositoryKey: EnvironmentKey {
    static let defaultValue: TransactionRepository? = nil
}

private struct TimeLogRepositoryKey: EnvironmentKey {
    static let defaultValue: TimeLogRepository? = nil
}

private struct CategoryItemRepositoryKey: EnvironmentKey {
    static let defaultValue: CategoryItemRepository? = nil
}

private struct TransactionUseCaseKey: EnvironmentKey {
    static let defaultValue: TransactionUseCase? = nil
}

extension EnvironmentValues {
    var projectRepository: ProjectRepository? {
        get { self[ProjectRepositoryKey.self] }
        set { self[ProjectRepositoryKey.self] = newValue }
    }
    var transactionRepository: TransactionRepository? {
        get { self[TransactionRepositoryKey.self] }
        set { self[TransactionRepositoryKey.self] = newValue }
    }
    var timeLogRepository: TimeLogRepository? {
        get { self[TimeLogRepositoryKey.self] }
        set { self[TimeLogRepositoryKey.self] = newValue }
    }
    var categoryItemRepository: CategoryItemRepository? {
        get { self[CategoryItemRepositoryKey.self] }
        set { self[CategoryItemRepositoryKey.self] = newValue }
    }
    var transactionUseCase: TransactionUseCase? {
        get { self[TransactionUseCaseKey.self] }
        set { self[TransactionUseCaseKey.self] = newValue }
    }
}
