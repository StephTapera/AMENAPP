//
//  SupportProfileRepository.swift
//  AMENAPP
//

import Foundation

protocol SupportProfileRepository: AnyObject, Sendable {
    func fetchProfile(userId: String) async throws -> SupportProfile?
    func saveProfile(_ profile: SupportProfile, userId: String) async throws
    func fetchPromptState(userId: String) async throws -> SupportPromptState?
    func savePromptState(_ state: SupportPromptState, userId: String) async throws
    func fetchRecoveryState(userId: String) async throws -> SupportRecoveryState?
    func saveRecoveryState(_ state: SupportRecoveryState, userId: String) async throws
    func saveSignal(_ signal: SupportSignal, userId: String) async throws
    func saveIntervention(_ intervention: SupportIntervention, userId: String) async throws
    func fetchRecentSignals(userId: String, limit: Int) async throws -> [SupportSignal]
    func fetchTrustedContacts(userId: String) async throws -> [SupportTrustedContact]
    func saveTrustedContacts(_ contacts: [SupportTrustedContact], userId: String) async throws
    func fetchResourcePlans(userId: String) async throws -> [SupportResourcePlan]
    func saveResourcePlan(_ plan: SupportResourcePlan, userId: String) async throws
}
