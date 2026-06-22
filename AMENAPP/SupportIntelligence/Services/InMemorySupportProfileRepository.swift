//
//  InMemorySupportProfileRepository.swift
//  AMENAPP
//
//  Lightweight repository used as a local fallback while Firestore-backed
//  persistence is phased in. Keeps the coordinator and UI integration stable.
//

import Foundation

actor InMemorySupportProfileRepository: SupportProfileRepository {
    private var profiles: [String: SupportProfile] = [:]
    private var promptStates: [String: SupportPromptState] = [:]
    private var recoveryStates: [String: SupportRecoveryState] = [:]
    private var signals: [String: [SupportSignal]] = [:]
    private var interventions: [String: [SupportIntervention]] = [:]
    private var contacts: [String: [SupportTrustedContact]] = [:]
    private var plans: [String: [SupportResourcePlan]] = [:]

    func fetchProfile(userId: String) async throws -> SupportProfile? {
        profiles[userId]
    }

    func saveProfile(_ profile: SupportProfile, userId: String) async throws {
        profiles[userId] = profile
    }

    func fetchPromptState(userId: String) async throws -> SupportPromptState? {
        promptStates[userId]
    }

    func savePromptState(_ state: SupportPromptState, userId: String) async throws {
        promptStates[userId] = state
    }

    func fetchRecoveryState(userId: String) async throws -> SupportRecoveryState? {
        recoveryStates[userId]
    }

    func saveRecoveryState(_ state: SupportRecoveryState, userId: String) async throws {
        recoveryStates[userId] = state
    }

    func saveSignal(_ signal: SupportSignal, userId: String) async throws {
        signals[userId, default: []].insert(signal, at: 0)
    }

    func saveIntervention(_ intervention: SupportIntervention, userId: String) async throws {
        interventions[userId, default: []].insert(intervention, at: 0)
    }

    func fetchRecentSignals(userId: String, limit: Int) async throws -> [SupportSignal] {
        Array(signals[userId, default: []].prefix(limit))
    }

    func fetchTrustedContacts(userId: String) async throws -> [SupportTrustedContact] {
        contacts[userId, default: []]
    }

    func saveTrustedContacts(_ contacts: [SupportTrustedContact], userId: String) async throws {
        self.contacts[userId] = contacts
    }

    func fetchResourcePlans(userId: String) async throws -> [SupportResourcePlan] {
        plans[userId, default: []]
    }

    func saveResourcePlan(_ plan: SupportResourcePlan, userId: String) async throws {
        var existing = plans[userId, default: []]
        existing.removeAll { $0.id == plan.id }
        existing.insert(plan, at: 0)
        plans[userId] = existing
    }
}
