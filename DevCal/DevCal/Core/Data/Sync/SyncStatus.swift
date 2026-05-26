//
//  SyncStatus.swift
//  DevCal
//
//  Overall state of the remote sync engine, surfaced to the Settings screen
//  ("Cloud Sync" row) and useful for debug overlays. Phase 0 only declares the
//  enum; Phase 4 hooks it up to FirestoreSyncService.
//

import Foundation

enum SyncStatus: Equatable, Sendable {
    /// Not signed in or sync explicitly disabled. Local-only mode.
    case disabled
    /// Sync engine is ready, no operations pending.
    case idle
    /// Pulling remote → local.
    case pulling
    /// Pushing local → remote.
    case pushing
    /// Last attempt produced an error. Carries a user-facing string.
    case failed(String)

    static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disabled, .disabled),
             (.idle, .idle),
             (.pulling, .pulling),
             (.pushing, .pushing):
            return true
        case let (.failed(a), .failed(b)):
            return a == b
        default:
            return false
        }
    }
}
