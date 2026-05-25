//
//  Entitlements.swift
//  DevCal
//
//  Mock subscription entitlements for the UI-first phase. Real StoreKit 2 wiring +
//  Firestore mirror happens later (see Files/Firebase_Setup_Checklist.md → "7. Subscription").
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class Entitlements {

    enum Plan: String, Codable {
        case free
        case proMonthly
        case proYearly
    }

    private(set) var plan: Plan {
        didSet {
            UserDefaults.standard.set(plan.rawValue, forKey: Self.storageKey)
        }
    }

    var isPro: Bool { plan != .free }

    // Free-tier limits per planning doc.
    let freeProjectLimit = 1
    let freeTransactionLimit = 50

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let restored = Plan(rawValue: raw) {
            plan = restored
        } else {
            plan = .free
        }
    }

    func upgrade(to plan: Plan) {
        // TODO(storekit): trigger real purchase via StoreKit 2 Product.purchase().
        self.plan = plan
    }

    func restore() {
        // TODO(storekit): real restore via AppStore.sync().
    }

    func reset() {
        plan = .free
    }

    private static let storageKey = "entitlements.plan"
}
