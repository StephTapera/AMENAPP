//
//  SupportInferenceServicing.swift
//  AMENAPP
//

import Foundation

/// Accepts signals and triggers support profile updates.
protocol SupportInferenceServicing: AnyObject, Sendable {
    /// Submit a local signal from a user action (post, note, behavior).
    func submitSignal(_ signal: SupportSignal) async

    /// Force a full profile refresh for the given user.
    func refreshProfile(for userId: String) async throws -> SupportProfile
}
