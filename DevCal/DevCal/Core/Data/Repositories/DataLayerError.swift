//
//  DataLayerError.swift
//  DevCal
//
//  Errors thrown across the repository / sync layer. Repositories never
//  swallow failures with `try?` — they surface them as one of these cases so
//  Views can present a single shared error alert.
//

import Foundation

enum DataLayerError: LocalizedError {
    /// The local SwiftData write itself failed. Wraps the underlying error so
    /// debugging can still see the SwiftData detail.
    case localSaveFailed(underlying: Error)
    /// The repository was asked to operate on a record that doesn't exist
    /// anymore (e.g. it was deleted in another sheet between presenting and
    /// saving). Should be treated as a benign no-op by most UIs.
    case recordNotFound
    /// Invariant the caller is supposed to enforce was violated (e.g. trying
    /// to save a transaction with no project). Programmer error, not user
    /// error — surfaces in dev as a fatal-looking alert but is recoverable.
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .localSaveFailed(let underlying):
            return "Local save failed: \(underlying.localizedDescription)"
        case .recordNotFound:
            return "Record not found."
        case .invalidInput(let detail):
            return "Invalid input: \(detail)"
        }
    }
}
