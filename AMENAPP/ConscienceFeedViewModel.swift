// ConscienceFeedViewModel.swift
// AMENAPP — Conscience Feed ViewModel

// SOUL DATA — handle with care

import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - ConscienceFeedViewModel

@MainActor
final class ConscienceFeedViewModel: ObservableObject {

    // MARK: - Published State

    @Published var conscience: UserConscience?
    @Published var driftLevel: ConscienceService.DriftLevel = .aligned
    @Published var weeklyReflection: String?
    @Published var isLoading = false
    @Published var showDriftWarning = false
    @Published var showLogOffSuggestion = false
    @Published var errorMessage: String?

    // MARK: - Private

    private let service = ConscienceService.shared
    private var currentUserId: String? { Auth.auth().currentUser?.uid }

    // MARK: - Load

    func loadConscience() async {
        guard let uid = currentUserId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            conscience = try await service.fetchConscience(userId: uid)
            if let c = conscience {
                evaluateDrift(c)
                weeklyReflection = c.weeklyConscience.isEmpty ? nil : c.weeklyConscience
            }
        } catch {
            errorMessage = "Couldn't load your conscience profile."
        }
    }

    // MARK: - Record Engagement

    /// Call this when the user engages with content tagged with a specific theme.
    func recordEngagement(theme: String, minutes: Int) {
        guard let uid = currentUserId else { return }
        Task {
            try? await service.recordEngagement(userId: uid, theme: theme, minutes: minutes)
            // Refresh drift state after new engagement
            await loadConscience()
        }
    }

    // MARK: - Drift Evaluation

    private func evaluateDrift(_ conscience: UserConscience) {
        let score = service.calculateDriftScore(conscience: conscience)
        driftLevel = service.driftLevel(for: score)

        // Show drift warning UI only if we haven't warned recently (24h cooldown)
        let twentyFourHoursAgo = Date().addingTimeInterval(-86400)
        let lastWarning = conscience.lastDriftWarningAt?.dateValue() ?? .distantPast

        switch driftLevel {
        case .aligned:
            showDriftWarning = false
        case .softWarning, .firmWarning:
            showDriftWarning = lastWarning < twentyFourHoursAgo
        }

        // Suggest logging off if daily usage exceeds 60 minutes
        showLogOffSuggestion = conscience.dailyUsageMinutes > 60
    }

    // MARK: - Drift Warning Acknowledged

    func acknowledgeDriftWarning() {
        guard let uid = currentUserId else { return }
        showDriftWarning = false
        Task {
            try? await service.recordDriftWarningShown(userId: uid)
        }
    }

    // MARK: - Weekly Conscience Refresh

    /// Triggers AI to generate a fresh weekly reflection.
    /// Should be called once per week, ideally from a background trigger.
    // COST NOTE: one AI call per user per week — safe to call on app launch with a date guard.
    func refreshWeeklyConscience(recentActivity: [ActivityLog]) async {
        guard let uid = currentUserId, let c = conscience else { return }

        if let reflection = await service.generateWeeklyConscience(conscience: c, recentActivity: recentActivity) {
            weeklyReflection = reflection
            try? await service.saveWeeklyConscience(userId: uid, reflection: reflection)
        }
        // If AI fails, keep existing weeklyConscience — do not clear it
    }

    // MARK: - Onboarding Save

    /// Called at end of conscience onboarding flow.
    func saveInitialConscience(
        identityStatement: String,
        values: [String],
        goals: [String],
        offLimits: [String]
    ) async {
        guard let uid = currentUserId else { return }

        let conscience = UserConscience(
            userId: uid,
            statedValues: values,
            statedIdentityStatement: identityStatement,
            spiritualGoals: goals,
            offLimitsTopics: offLimits
        )

        do {
            try await service.saveConscience(conscience)
            self.conscience = conscience
        } catch {
            errorMessage = "Couldn't save your conscience profile. Please try again."
        }
    }
}
