// GivingIntentProfileViewModel.swift
// AMENAPP
//
// Manages the values intake stepper — 3 taps max, editable anytime.
// Skipped flows get reduced-confidence ranking profile.

import Foundation
import SwiftUI

@MainActor
final class GivingIntentProfileViewModel: ObservableObject {

    @Published var step: IntentStep = .causes
    @Published var selectedCauses: Set<GivingCause> = []
    @Published var geographicPreference: GeographicPreference = .balanced
    @Published var theologicalAlignment: TheologicalAlignment = .denominationallyNeutral
    @Published var givingStyles: Set<GivingStyle> = []
    @Published var isEditing = false

    enum IntentStep: Int, CaseIterable {
        case causes = 0
        case geography = 1
        case alignment = 2

        var title: String {
            switch self {
            case .causes: return "What moves you?"
            case .geography: return "Where would you focus?"
            case .alignment: return "How do you approach giving?"
            }
        }

        var subtitle: String {
            switch self {
            case .causes: return "Choose the causes that should shape what you see."
            case .geography: return "Choose how AMEN should bias the feed geographically."
            case .alignment: return "This changes ranking and framing, never truthfulness."
            }
        }

        var isFirst: Bool { self == .causes }
        var isLast: Bool { self == .alignment }
    }

    func advance() {
        if let next = IntentStep(rawValue: step.rawValue + 1) {
            withAnimation(.spring(duration: 0.32, bounce: 0.08)) {
                step = next
            }
        }
    }

    func retreat() {
        if let prev = IntentStep(rawValue: step.rawValue - 1) {
            withAnimation(.spring(duration: 0.32, bounce: 0.08)) {
                step = prev
            }
        }
    }

    func toggleCause(_ cause: GivingCause) {
        if selectedCauses.contains(cause) {
            selectedCauses.remove(cause)
        } else {
            selectedCauses.insert(cause)
        }
    }

    func toggleStyle(_ style: GivingStyle) {
        if givingStyles.contains(style) {
            givingStyles.remove(style)
        } else {
            givingStyles.insert(style)
        }
    }

    func buildProfile() -> GivingProfile {
        GivingProfile(
            causePreferences: Array(selectedCauses),
            geographicPreference: geographicPreference,
            theologicalAlignment: theologicalAlignment,
            givingStylePreferences: Array(givingStyles),
            locationMode: .none,
            completedIntentFlowAt: Date(),
            rankProfileVersion: 1
        )
    }

    func loadFrom(profile: GivingProfile) {
        selectedCauses = Set(profile.causePreferences)
        geographicPreference = profile.geographicPreference
        theologicalAlignment = profile.theologicalAlignment
        givingStyles = Set(profile.givingStylePreferences)
    }

    var summaryText: String {
        let causeStr = selectedCauses.map(\.rawValue).joined(separator: ", ")
        return "AMEN will prioritize \(causeStr.isEmpty ? "balanced causes" : causeStr), with a \(geographicPreference.rawValue.lowercased()) focus, in a \(theologicalAlignment.rawValue) framing."
    }
}
