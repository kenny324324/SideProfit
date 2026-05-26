//
//  SWDateExtension.swift
//  ShipSwift
//
//  Date extension providing locale-aware formatting, relative time descriptions,
//  date comparison, and date arithmetic helpers.
//
//  Refactored 2026-05-26 to use `Locale.current` + `setLocalizedDateFormatFromTemplate`
//  + `RelativeDateTimeFormatter` so JA / KO / EN users no longer see hard-wired
//  Traditional Chinese strings. The old `appLanguage` UserDefaults toggle is gone —
//  the device locale is now the single source of truth.
//
//  Usage:
//    Date().formatMonth()       // "Jan" / "1月" / "1月" / "1월"
//    Date().formatMonthDay()    // "Jan 15" / "1月15日" / "1月15日" / "1월 15일"
//    Date().formatFullDate()    // "Jan 15, 2025" / "2025年1月15日" / "2025年1月15日" / "2025년 1월 15일"
//    Date().formatTime()        // "14:30"
//    Date().formatDateTime()    // "Jan 15, 14:30" / "1月15日 14:30" / ...
//
//    someDate.timeAgo()         // "Just now" / "3 分鐘前" / "3분 전" / etc. (locale-driven)
//
//    date.isToday / date.isYesterday / date.isSameDay(as:)
//    date.startOfDay / date.endOfDay
//    date.adding(days:) / adding(months:) / adding(years:)
//    date.days(from:)
//
//    Date.shouldResetDaily(dateKey:) / Date.updateDailyResetDate(dateKey:)
//
//  Created by Wei Zhong on 3/1/26.
//

import Foundation

// MARK: - Date Formatting

extension Date {

    // MARK: - Basic Formatting

    /// Format as month, locale-aware. EN → "Jan", JA → "1月", zh-Hant → "1月", KO → "1월".
    func formatMonth() -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: self)
    }

    /// Format as day of month — locale-neutral integer.
    func formatDay() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: self)
    }

    /// Format as month + day, locale-aware. EN → "Jan 15", zh-Hant/JA → "1月15日", KO → "1월 15일".
    func formatMonthDay() -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: self)
    }

    /// Format as full date, locale-aware. EN → "Jan 15, 2025", zh-Hant/JA → "2025年1月15日",
    /// KO → "2025년 1월 15일".
    func formatFullDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: self)
    }

    /// Format as 24-hour time. Locale-neutral.
    func formatTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    /// Format as date + time, locale-aware.
    func formatDateTime() -> String {
        "\(formatMonthDay()) \(formatTime())"
    }

    // MARK: - Relative Time

    /// Locale-aware relative time. Uses Apple's `RelativeDateTimeFormatter` so
    /// the output is fully translated by the system — EN gets "3 min ago",
    /// zh-Hant gets "3 分鐘前", JA gets "3分前", KO gets "3분 전".
    ///
    /// Falls back to a full date (locale-aware) for anything more than 7 days
    /// in the past so users don't see "7 weeks ago" when they want the actual
    /// calendar date.
    func timeAgo() -> String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        // Future date — show calendar date rather than "in 3 hours" since
        // the call sites (transaction lists, logs) only ever look back.
        if interval < 0 {
            return formatMonthDay()
        }

        // > 7 days → show the actual date instead of a vague "N weeks ago".
        if interval >= 604_800 {
            return formatMonthDay()
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: now)
    }

    // MARK: - Date Comparison

    /// Whether the date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Whether the date is yesterday
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// Whether the date is tomorrow
    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }

    /// Whether this date is the same day as another date
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// Get the start of day (00:00:00)
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// Get the end of day (23:59:59)
    var endOfDay: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!.addingTimeInterval(-1)
    }

    // MARK: - Date Arithmetic

    /// Add days
    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    /// Add months
    func adding(months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }

    /// Add years
    func adding(years: Int) -> Date {
        Calendar.current.date(byAdding: .year, value: years, to: self) ?? self
    }

    /// Number of days between two dates
    func days(from other: Date) -> Int {
        Calendar.current.dateComponents([.day], from: other.startOfDay, to: self.startOfDay).day ?? 0
    }
}

// MARK: - Daily Reset Helper

extension Date {
    /// Check whether the daily counter needs to be reset
    /// - Parameter key: The key used to store the date in UserDefaults
    /// - Returns: Whether a reset is needed (day has changed)
    static func shouldResetDaily(dateKey: String) -> Bool {
        let today = Date().startOfDay
        let lastDate = UserDefaults.standard.object(forKey: dateKey) as? Date ?? .distantPast
        return !today.isSameDay(as: lastDate)
    }

    /// Update the daily reset date
    /// - Parameter key: The key used to store the date in UserDefaults
    static func updateDailyResetDate(dateKey: String) {
        UserDefaults.standard.set(Date().startOfDay, forKey: dateKey)
    }
}
