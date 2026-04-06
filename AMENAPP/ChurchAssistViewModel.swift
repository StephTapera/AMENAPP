// ChurchAssistViewModel.swift
// Orchestrates all church assist state, prompts, and integrations
// AMENAPP

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - ChurchAssistViewModel

@MainActor
final class ChurchAssistViewModel: ObservableObject {

    // MARK: - Shared Instance
    static let shared = ChurchAssistViewModel()

    // MARK: - Published State
    @Published private(set) var currentPrompt: ChurchAssistPromptType?
    @Published private(set) var showPill: Bool = false
    @Published private(set) var showSheet: Bool = false
    @Published private(set) var showServiceMode: Bool = false
    @Published private(set) var showPostVisitReflection: Bool = false
    @Published private(set) var currentChurchName: String = ""
    @Published private(set) var currentChurchId: String = ""
    @Published private(set) var visitInsights: ChurchVisitInsights?

    // MARK: - Private Dependencies
    private let sessionManager = ChurchVisitSessionManager.shared
    private let locationManager = ChurchLocationManager.shared
    private let db = Firestore.firestore()
    private var insightsListener: ListenerRegistration?

    // MARK: - Init
    private init() {}

    // MARK: - Setup

    /// Initialize assist layer for a user: load state, wire location callbacks, load insights.
    func setup(userId: String) async {
        await sessionManager.loadAssistState(userId: userId)
        await loadInsights(userId: userId)
        setupLocationCallbacks(userId: userId)
        dlog("[ChurchAssist] Setup complete for user \(userId)")
    }

    private func setupLocationCallbacks(userId: String) {
        locationManager.onArrival = { [weak self] churchId, confidence in
            Task { @MainActor [weak self] in
                await self?.handleArrival(churchId: churchId, churchName: self?.currentChurchName ?? "", confidence: confidence)
            }
        }
        locationManager.onInService = { [weak self] churchId in
            Task { @MainActor [weak self] in
                await self?.handleInService(churchId: churchId)
            }
        }
        locationManager.onExit = { [weak self] churchId, dwellSeconds in
            Task { @MainActor [weak self] in
                await self?.handleExit(churchId: churchId, dwellSeconds: dwellSeconds)
            }
        }
        dlog("[ChurchAssist] Location callbacks wired")
    }

    // MARK: - Event Handlers

    /// Handle a confirmed arrival at a church.
    func handleArrival(churchId: String, churchName: String, confidence: Double) async {
        guard ChurchAssistFeatureFlags.effective(ChurchAssistFeatureFlags.enableArrivalPrompts) else {
            dlog("[ChurchAssist] Arrival prompts disabled by feature flag")
            return
        }
        currentChurchId = churchId
        if !churchName.isEmpty { currentChurchName = churchName }

        let assistState = sessionManager.assistState
        let decision = ChurchPromptPolicyEngine.shouldShowPrompt(.arrivedNeedsNotes, assistState: assistState)
        guard decision.shouldShow else {
            dlog("[ChurchAssist] Arrival prompt suppressed: \(decision.suppressReason ?? "unknown")")
            return
        }
        await sessionManager.recordArrival(churchId: churchId, confidence: confidence)
        currentPrompt = .arrivedNeedsNotes
        withAnimation(Motion.adaptive(Animation.spring(response: 0.4, dampingFraction: 0.8))) {
            showPill = true
        }
        dlog("[ChurchAssist] Showing arrival pill for \(churchName)")
    }

    /// Handle transition into service at a church.
    func handleInService(churchId: String) async {
        guard ChurchAssistFeatureFlags.effective(ChurchAssistFeatureFlags.enableServiceMode) else { return }

        let assistState = sessionManager.assistState
        let decision = ChurchPromptPolicyEngine.shouldShowPrompt(.inServiceCaptureVerse, assistState: assistState)
        guard decision.shouldShow else {
            dlog("[ChurchAssist] In-service prompt suppressed: \(decision.suppressReason ?? "unknown")")
            return
        }
        await sessionManager.transitionToInService()
        currentPrompt = .inServiceCaptureVerse
        withAnimation(Motion.adaptive(Animation.spring(response: 0.4, dampingFraction: 0.8))) {
            showPill = false
            showServiceMode = true
        }
        dlog("[ChurchAssist] Activated service mode for church \(churchId)")
    }

    /// Handle exit from a church.
    func handleExit(churchId: String, dwellSeconds: Int) async {
        guard ChurchAssistFeatureFlags.effective(ChurchAssistFeatureFlags.enablePostVisitReflection) else { return }

        await sessionManager.recordExit(dwellDurationSeconds: dwellSeconds)

        let assistState = sessionManager.assistState
        let decision = ChurchPromptPolicyEngine.shouldShowPrompt(.postVisitReflection, assistState: assistState)
        guard decision.shouldShow else {
            dlog("[ChurchAssist] Post-visit prompt suppressed: \(decision.suppressReason ?? "unknown")")
            return
        }
        currentPrompt = .postVisitReflection
        withAnimation(Motion.adaptive(Animation.spring(response: 0.4, dampingFraction: 0.8))) {
            showServiceMode = false
            showPill = true
        }
        dlog("[ChurchAssist] Showing post-visit prompt for church \(churchId)")
    }

    /// Route a prompt action to the appropriate sheet or view.
    func handlePromptAction(_ action: ChurchAssistPromptType) async {
        dlog("[ChurchAssist] Handling prompt action: \(action.rawValue)")
        withAnimation(Motion.adaptive(Motion.springRelease)) {
            showPill = false
        }
        switch action {
        case .postVisitReflection, .postVisitShare:
            showPostVisitReflection = true
        case .arrivedNeedsNotes, .arrivedChecklist,
             .inServiceCaptureVerse, .inServicePrayerThought,
             .planningToAttend, .compareServices,
             .firstVisitCompanion, .revisitSuggestion:
            showSheet = true
        }
        currentPrompt = action
    }

    /// Dismiss the current prompt and log the dismissal.
    func dismissPrompt() async {
        guard let prompt = currentPrompt else { return }
        let userId = sessionManager.assistState.currentChurchId ?? ""
        if !userId.isEmpty {
            await sessionManager.dismissPrompt(prompt, userId: userId)
        }
        withAnimation(Motion.adaptive(Motion.springRelease)) {
            showPill = false
            showSheet = false
            showServiceMode = false
        }
        currentPrompt = nil
        dlog("[ChurchAssist] Dismissed prompt: \(prompt.rawValue)")
    }

    // MARK: - Insights

    /// Load visit insights from Firestore and start a real-time listener.
    func loadInsights(userId: String) async {
        insightsListener?.remove()
        insightsListener = db
            .collection("users").document(userId)
            .collection("churchVisitInsights").document("summary")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    dlog("[ChurchAssist] Insights listener error: \(error)")
                    return
                }
                if let data = snapshot?.data() {
                    do {
                        let insights = try Firestore.Decoder().decode(ChurchVisitInsights.self, from: data)
                        self.visitInsights = insights
                        dlog("[ChurchAssist] Loaded insights: \(insights.totalVisits) total visits")
                    } catch {
                        dlog("[ChurchAssist] Error decoding insights: \(error)")
                    }
                }
            }
    }

    /// Save a church to the user's saved churches subcollection.
    func saveCurrentChurch(_ churchId: String, name: String, userId: String) async {
        let data: [String: Any] = [
            "churchId": churchId,
            "name": name,
            "savedAt": Timestamp(date: Date()),
            "userId": userId
        ]
        do {
            try await db
                .collection("users").document(userId)
                .collection("savedChurches").document(churchId)
                .setData(data, merge: true)
            dlog("[ChurchAssist] Saved church \(churchId) for user \(userId)")
        } catch {
            dlog("[ChurchAssist] Error saving church: \(error)")
        }
    }
}
