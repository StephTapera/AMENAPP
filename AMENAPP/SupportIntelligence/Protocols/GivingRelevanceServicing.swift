//
//  GivingRelevanceServicing.swift
//  AMENAPP
//

import Foundation

protocol GivingRelevanceServicing: AnyObject, Sendable {
    func fetchGivingProfile(userId: String) async throws -> GivingProfile
    func rankedCauseCategories(for userId: String) async throws -> [GivingCauseCategory]
    func updateGivingIntent(userId: String, signal: SupportSignal) async throws
}
