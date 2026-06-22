//
//  SupportSessionServicing.swift
//  AMENAPP
//

import Foundation

protocol SupportSessionServicing: AnyObject, Sendable {
    func startSession(userId: String, type: String, surface: SupportSurface, entryReason: String) async throws -> SupportSession
    func recordAction(_ action: String, sessionId: String, userId: String) async throws
    func endSession(_ sessionId: String, userId: String, resolvedState: String?) async throws
}
