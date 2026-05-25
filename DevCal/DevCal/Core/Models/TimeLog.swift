//
//  TimeLog.swift
//  DevCal
//

import Foundation
import SwiftData

@Model
final class TimeLog {
    var id: UUID = UUID()
    var hours: Double = 0
    var hourlyRate: Double = 0
    /// ISO 4217 currency the user picked when setting the rate.
    var hourlyCurrencyCode: String = "TWD"
    var note: String = ""
    var date: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var project: Project?

    init(
        hours: Double = 0,
        hourlyRate: Double = 0,
        hourlyCurrencyCode: String = "TWD",
        note: String = "",
        date: Date = Date(),
        project: Project? = nil
    ) {
        self.id = UUID()
        self.hours = hours
        self.hourlyRate = hourlyRate
        self.hourlyCurrencyCode = hourlyCurrencyCode
        self.note = note
        self.date = date
        self.project = project
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    /// In the ORIGINAL currency. UI converts via ExchangeRateService.
    var laborCost: Double {
        hours * hourlyRate
    }

    func convertedLaborCost(to displayCode: String, fx: ExchangeRateService) -> Double {
        fx.convert(laborCost, from: hourlyCurrencyCode, to: displayCode) ?? 0
    }

    func convertedHourlyRate(to displayCode: String, fx: ExchangeRateService) -> Double {
        fx.convert(hourlyRate, from: hourlyCurrencyCode, to: displayCode) ?? 0
    }
}
