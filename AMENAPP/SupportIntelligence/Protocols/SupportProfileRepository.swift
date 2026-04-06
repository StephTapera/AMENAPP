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
}
