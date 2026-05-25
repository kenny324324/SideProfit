//
//  CurrencyFormatter.swift
//  DevCal
//
//  Lightweight wrappers around NumberFormatter / FormatStyle for consistent currency
//  display. Uses per-project currencyCode (TWD, USD, JPY, etc.) and falls back to
//  the device locale's currency code if a project's code is empty.
//

import Foundation

enum CurrencyFormatter {

    /// Full currency formatting, e.g. "NT$12,345" / "$12.50".
    static func format(_ value: Double, currencyCode: String) -> String {
        let code = currencyCode.isEmpty ? Locale.current.currency?.identifier ?? "USD" : currencyCode
        return value.formatted(
            .currency(code: code)
                .precision(.fractionLength(0...2))
        )
    }

    /// Compact formatting for chart axes / cards — drops fraction digits and
    /// abbreviates large numbers as 1.2K / 3.4M.
    static func formatCompact(_ value: Double, currencyCode: String) -> String {
        let code = currencyCode.isEmpty ? Locale.current.currency?.identifier ?? "USD" : currencyCode
        let abs = Swift.abs(value)
        let sign = value < 0 ? "-" : ""

        let symbol = symbol(for: code)
        if abs >= 1_000_000 {
            return "\(sign)\(symbol)\(format(abs / 1_000_000))M"
        } else if abs >= 10_000 {
            return "\(sign)\(symbol)\(format(abs / 1_000))K"
        } else {
            return value.formatted(.currency(code: code).precision(.fractionLength(0)))
        }
    }

    private static func symbol(for currencyCode: String) -> String {
        let locale = Locale(identifier: "\(Locale.current.identifier)@currency=\(currencyCode)")
        return locale.currencySymbol ?? "$"
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension Double {
    func asCurrency(_ code: String) -> String {
        CurrencyFormatter.format(self, currencyCode: code)
    }

    func asCompactCurrency(_ code: String) -> String {
        CurrencyFormatter.formatCompact(self, currencyCode: code)
    }
}
