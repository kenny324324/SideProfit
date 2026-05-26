//
//  AppReviewPrompt.swift
//  DevCal
//
//  Centralizes the review timing rules so feature screens only report successful
//  product moments. The root view owns the actual satisfaction prompt and
//  StoreKit request.
//

import Foundation
import StoreKit
import SwiftUI

@MainActor
@Observable
final class AppReviewPrompter {
    enum Event: String {
        case projectCreated
        case transactionCreated
        case timeLogCreated
        case breakEvenReached
    }

    struct Prompt: Identifiable {
        let id = UUID()
        let event: Event
    }

    static let developerEmail = "Kenny4work324@gmail.com"

    static var developerMailURL: URL {
        let subject = "SideProfit Feedback".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "SideProfit"
        return URL(string: "mailto:\(developerEmail)?subject=\(subject)")!
    }

    var pendingPrompt: Prompt?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var scheduledTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func record(_ event: Event) {
        incrementCount(for: event)
        guard shouldPrompt(for: event) else { return }
        schedulePrompt(for: event)
    }

    func completeCurrentPrompt() {
        scheduledTask?.cancel()
        pendingPrompt = nil
        defaults.set(Date(), forKey: Self.lastPromptDateKey)
        defaults.set(currentVersion, forKey: Self.completedPromptVersionKey)
    }

    func snoozeCurrentPrompt() {
        scheduledTask?.cancel()
        pendingPrompt = nil
        defaults.set(Date(), forKey: Self.lastPromptDateKey)
    }

    private func schedulePrompt(for event: Event) {
        scheduledTask?.cancel()
        scheduledTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard let self, !Task.isCancelled, self.shouldPrompt(for: event) else { return }
            self.pendingPrompt = Prompt(event: event)
        }
    }

    private func shouldPrompt(for event: Event) -> Bool {
        guard pendingPrompt == nil else { return false }
        guard defaults.string(forKey: Self.completedPromptVersionKey) != currentVersion else { return false }
        guard !isInCooldown else { return false }

        switch event {
        case .breakEvenReached:
            return true
        case .transactionCreated:
            return count(for: .transactionCreated) >= 5
        case .timeLogCreated:
            return count(for: .timeLogCreated) >= 3 && count(for: .transactionCreated) >= 2
        case .projectCreated:
            return count(for: .projectCreated) >= 2
        }
    }

    private var isInCooldown: Bool {
        guard let last = defaults.object(forKey: Self.lastPromptDateKey) as? Date else { return false }
        return Date().timeIntervalSince(last) < Self.cooldown
    }

    private func incrementCount(for event: Event) {
        defaults.set(count(for: event) + 1, forKey: countKey(for: event))
    }

    private func count(for event: Event) -> Int {
        defaults.integer(forKey: countKey(for: event))
    }

    private func countKey(for event: Event) -> String {
        "appReview.eventCount.\(event.rawValue)"
    }

    private var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version)-\(build)"
    }

    private static let completedPromptVersionKey = "appReview.completedPromptVersion"
    private static let lastPromptDateKey = "appReview.lastPromptDate"
    private static let cooldown: TimeInterval = 14 * 24 * 60 * 60
}

extension View {
    func appReviewPrompt(_ prompter: AppReviewPrompter) -> some View {
        modifier(AppReviewPromptModifier(prompter: prompter))
    }
}

private struct AppReviewPromptModifier: ViewModifier {
    let prompter: AppReviewPrompter
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content
            .alert(
                "Are you satisfied with SideProfit?",
                isPresented: promptBinding
            ) {
                Button("Satisfied") {
                    prompter.completeCurrentPrompt()
                    requestStoreReviewAfterAlertDismisses()
                }
                Button("Not satisfied") {
                    prompter.completeCurrentPrompt()
                    openDeveloperMailAfterAlertDismisses()
                }
                Button("Maybe later", role: .cancel) {
                    prompter.snoozeCurrentPrompt()
                }
            } message: {
                Text("If SideProfit has been useful, you can rate it on the App Store. If something feels off, email the developer directly.")
            }
            .tint(Theme.primaryText)
    }

    private var promptBinding: Binding<Bool> {
        Binding(
            get: { prompter.pendingPrompt != nil },
            set: { isPresented in
                if !isPresented {
                    prompter.snoozeCurrentPrompt()
                }
            }
        )
    }

    private func requestStoreReviewAfterAlertDismisses() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            requestReview()
        }
    }

    private func openDeveloperMailAfterAlertDismisses() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            openURL(AppReviewPrompter.developerMailURL)
        }
    }
}
