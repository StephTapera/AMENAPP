//
//  SafetyPlanStore.swift
//  AMENAPP
//
//  Persists the user's interactive safety plan locally (UserDefaults).
//  Never sent to a server — privacy-first, works offline.
//

import Foundation

// MARK: - Data Model

struct SafetyPlan: Codable {
    var warningSignsINotice: [String] = []
    var internalCopingStrategies: [String] = []
    var peopleAndPlacesThatHelp: [String] = []
    var trustedPeopleToCall: [TrustedPerson] = []
    var professionalContacts: [String] = []
    var environmentSafetySteps: [String] = []
    var lastModified: Date = Date()
}

struct TrustedPerson: Codable, Identifiable {
    var id = UUID()
    var name: String
    var phone: String
}

// MARK: - Store

@MainActor
final class SafetyPlanStore: ObservableObject {
    static let shared = SafetyPlanStore()

    @Published var plan: SafetyPlan {
        didSet { save() }
    }

    private let key = "amen.safetyPlan"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(SafetyPlan.self, from: data) {
            plan = decoded
        } else {
            plan = SafetyPlan()
        }
    }

    private func save() {
        plan.lastModified = Date()
        if let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// True if the user has entered anything at all.
    var hasContent: Bool {
        !plan.warningSignsINotice.isEmpty ||
        !plan.internalCopingStrategies.isEmpty ||
        !plan.peopleAndPlacesThatHelp.isEmpty ||
        !plan.trustedPeopleToCall.isEmpty ||
        !plan.professionalContacts.isEmpty ||
        !plan.environmentSafetySteps.isEmpty
    }
}
