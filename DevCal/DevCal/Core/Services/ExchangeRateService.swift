//
//  ExchangeRateService.swift
//  DevCal
//
//  Single source of truth for currency conversion across the app. Pulls the
//  latest rates from Frankfurter (ECB-sourced, no API key, CC0). Caches the
//  table in UserDefaults so the UI always has something to show offline.
//
//  Design notes:
//  - One @Observable singleton, accessed via `ExchangeRateService.shared` or
//    injected via `.environment(...)` so views auto-update on refresh.
//  - Rates are stored relative to USD. `convert(_:from:to:)` triangulates.
//  - No snapshot: each render uses today's rate (per Multi_Currency_Plan v1).
//

import Foundation
import SwiftUI

@Observable
final class ExchangeRateService {

    static let shared = ExchangeRateService()

    /// The 15 ISO codes exposed in pickers and Settings. Order is intentional:
    /// TWD first (Kenny's locale), USD second (universal), then large markets
    /// followed by frequent indie markets.
    static let supportedCodes: [String] = [
        "TWD", "USD", "JPY", "EUR", "GBP", "CNY",
        "HKD", "KRW", "SGD", "AUD", "CAD", "CHF",
        "INR", "THB", "MYR"
    ]

    /// USD-based table. e.g. `rates["TWD"] = 32.45` means 1 USD = 32.45 TWD.
    /// `USD` itself is always present at 1.0. Pre-seeded with bundled
    /// baseline rates so the app never shows 0 when the network is cold —
    /// the live fetch overwrites these as soon as it completes.
    private(set) var rates: [String: Double] = ExchangeRateService.baselineRates
    private(set) var lastUpdated: Date? = nil
    private(set) var isFetching: Bool = false
    private(set) var lastError: String? = nil

    /// Bundled approximate rates used as a cold-start fallback so conversion
    /// never returns nil before the first successful network fetch. Values are
    /// rough yearly averages — accurate enough that totals are sensible while
    /// stale, and gets replaced wholesale by the next Frankfurter refresh.
    /// Order matches `supportedCodes`.
    static let baselineRates: [String: Double] = [
        "USD": 1.0,
        "TWD": 32.0,
        "JPY": 155.0,
        "EUR": 0.92,
        "GBP": 0.79,
        "CNY": 7.25,
        "HKD": 7.80,
        "KRW": 1380.0,
        "SGD": 1.35,
        "AUD": 1.52,
        "CAD": 1.36,
        "CHF": 0.89,
        "INR": 83.5,
        "THB": 36.5,
        "MYR": 4.70
    ]

    private static let cacheKey = "exchangeRates.v1"
    private static let endpoint = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD")!
    private static let refreshInterval: TimeInterval = 6 * 60 * 60   // 6h
    private static let staleInterval: TimeInterval = 24 * 60 * 60    // 24h

    init() {
        loadFromCache()
    }

    // MARK: - Public API

    /// Today's-rate conversion. Same code → original. Either code missing → nil.
    /// Returns Double for ergonomics; callers should show "—" when nil.
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        if from == to { return amount }
        // Both are stored relative to USD: amount(in:to) = amount * rates[to] / rates[from].
        guard let fromRate = rates[from], fromRate > 0,
              let toRate = rates[to], toRate > 0 else { return nil }
        return amount * toRate / fromRate
    }

    /// Fetches the latest rates and persists to UserDefaults.
    /// Safe to call concurrently — only one fetch runs at a time.
    func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        do {
            var request = URLRequest(url: Self.endpoint)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            // Frankfurter is ECB-sourced and does not return every code we expose
            // (e.g. TWD). Merging on top of the baseline keeps stored amounts in
            // those currencies convertible instead of collapsing them to 0.
            self.rates = Self.merge(remote: decoded.rates, baseline: Self.baselineRates)
            self.lastUpdated = Date()
            self.lastError = nil
            saveToCache()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Refresh only if we haven't pulled in the last 6 hours (or never).
    func refreshIfNeeded() async {
        if let last = lastUpdated, Date().timeIntervalSince(last) < Self.refreshInterval {
            return
        }
        await refresh()
    }

    /// True when the cached table is older than 24h (or never fetched).
    var isStale: Bool {
        guard let last = lastUpdated else { return true }
        return Date().timeIntervalSince(last) > Self.staleInterval
    }

    // MARK: - Merge

    /// Layer the Frankfurter response on top of the bundled baseline so codes
    /// the ECB doesn't publish (e.g. TWD) survive a network refresh. Exposed
    /// `internal` so the test target can verify the merge directly without
    /// stubbing URLSession.
    static func merge(remote: [String: Double], baseline: [String: Double]) -> [String: Double] {
        var merged = baseline
        for (code, rate) in remote { merged[code] = rate }
        merged["USD"] = 1.0
        return merged
    }

    // MARK: - Persistence

    private func loadFromCache() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.cacheKey),
              let cached = try? JSONDecoder().decode(CachedRates.self, from: data) else {
            return
        }
        // Merge cached values on top of the baseline — any code missing from
        // the cache falls back to the bundled rate so conversion never fails.
        var merged = Self.baselineRates
        for (code, rate) in cached.rates { merged[code] = rate }
        merged["USD"] = 1.0
        self.rates = merged
        self.lastUpdated = cached.lastUpdated
    }

    private func saveToCache() {
        let payload = CachedRates(rates: rates, lastUpdated: lastUpdated ?? Date())
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    // MARK: - DTOs

    private struct FrankfurterResponse: Decodable {
        let amount: Double
        let base: String
        let date: String
        let rates: [String: Double]
    }

    private struct CachedRates: Codable {
        let rates: [String: Double]
        let lastUpdated: Date
    }
}

// MARK: - Environment plumbing

private struct DisplayCurrencyKey: EnvironmentKey {
    static let defaultValue: String = "TWD"
}

extension EnvironmentValues {
    /// User-selected display currency, set at the app root from
    /// `@AppStorage("defaultCurrency")` so views read one value and react to changes.
    var displayCurrency: String {
        get { self[DisplayCurrencyKey.self] }
        set { self[DisplayCurrencyKey.self] = newValue }
    }
}
