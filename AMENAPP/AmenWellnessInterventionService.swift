//
//  AmenWellnessInterventionService.swift
//  AMENAPP
//
//  Context-aware wellness interventions.
//  Detects doomscrolling, anger content, late-night usage,
//  repeated conflict replies, and other unhealthy patterns.
//
//  Interventions are gentle, optional, and non-shaming.
//  Safety-critical interventions (receiving harassment) are
//  surfaced more prominently but still user-controllable.
//

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class AmenWellnessInterventionService: ObservableObject {

    static let shared = AmenWellnessInterventionService()

    private let flags = AmenSafetyFeatureFlags.shared

    @Published var pendingIntervention: WellnessInterventionContext?
    @Published var isShowingIntervention: Bool = false

    // Session tracking
    private var sessionStartTime: Date = Date()
    private var scrollEventCount: Int = 0
    private var angerContentCount: Int = 0
    private var conflictRepliesCount: Int = 0
    private var recentContentCategories: [String] = []

    // Thresholds
    private let doomscrollThreshold: Int = 40  // scroll events in a session
    private let angerContentThreshold: Int = 5
    private let conflictRepliesThreshold: Int = 3
    private let lateNightHour: Int = 23
    private let earlyMorningHour: Int = 5

    private init() {}

    // MARK: - Session tracking

    func trackScrollEvent() {
        guard flags.wellnessInterventionsEnabled else { return }
        scrollEventCount += 1
        if scrollEventCount >= doomscrollThreshold, flags.selahPauseEnabled {
            triggerIntervention(.doomscrolling, intervention: .selahPause)
        }
    }

    func trackContentViewed(categories: [String]) {
        guard flags.wellnessInterventionsEnabled else { return }
        recentContentCategories.append(contentsOf: categories)
        if recentContentCategories.filter({ $0 == "anger" || $0 == "outrage" }).count >= angerContentThreshold {
            triggerIntervention(.repeatedAngerContent, intervention: .reflectionPrompt)
        }
    }

    func trackConflictReply() {
        guard flags.wellnessInterventionsEnabled else { return }
        conflictRepliesCount += 1
        if conflictRepliesCount >= conflictRepliesThreshold {
            triggerIntervention(.repeatedConflictReplies, intervention: .conflictWarning)
        }
    }

    func checkLateNightUsage() {
        guard flags.wellnessInterventionsEnabled, flags.selahPauseEnabled else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= lateNightHour || hour <= earlyMorningHour {
            triggerIntervention(.lateNightUsage, intervention: .selahPause)
        }
    }

    // MARK: - Pre-post check

    func checkBeforePost(text: String) -> WellnessInterventionContext? {
        guard flags.wellnessInterventionsEnabled, flags.postConfirmationEnabled else { return nil }
        // Triggered by TSPreflightDecision → borderline outcome or high risk score
        return nil  // populated by AmenTrustSafetyService on borderline decisions
    }

    func triggerBeforePost(reason: String) {
        guard flags.postConfirmationEnabled else { return }
        let context = WellnessInterventionContext(
            trigger: .aboutToPostHarmful,
            intervention: .postConfirmation,
            customMessage: reason
        )
        pendingIntervention = context
        isShowingIntervention = true
    }

    // MARK: - Harassment detection trigger

    func notifyReceivingHarassment() {
        guard flags.wellnessInterventionsEnabled else { return }
        triggerIntervention(.receivingHarassment, intervention: .muteSuggestion)
    }

    // MARK: - Reply reflection

    func checkBeforeReply() -> Bool {
        guard flags.wellnessInterventionsEnabled else { return false }
        if conflictRepliesCount >= 2 {
            triggerIntervention(.repeatedConflictReplies, intervention: .replyReflection)
            return true
        }
        return false
    }

    // MARK: - Dismiss / act on

    func dismissIntervention() {
        isShowingIntervention = false
        pendingIntervention = nil
        // Reset some counters on dismiss
        angerContentCount = 0
        conflictRepliesCount = 0
    }

    func actOnIntervention() {
        isShowingIntervention = false
        pendingIntervention = nil
        // Log to Firestore for analytics (wellness_events)
        logWellnessEvent()
    }

    func resetSession() {
        sessionStartTime = Date()
        scrollEventCount = 0
        angerContentCount = 0
        conflictRepliesCount = 0
        recentContentCategories = []
    }

    // MARK: - Private

    private func triggerIntervention(_ trigger: WellnessTrigger, intervention: TSWellnessIntervention) {
        // Debounce: don't show if already showing
        guard !isShowingIntervention else { return }
        pendingIntervention = WellnessInterventionContext(
            trigger: trigger,
            intervention: intervention,
            customMessage: nil
        )
        isShowingIntervention = true
    }

    private func logWellnessEvent() {
        guard let uid = Auth.auth().currentUser?.uid,
              let ctx = pendingIntervention else { return }
        let db = Firestore.firestore()
        let eventData: [String: Any] = [
            "uid": uid,
            "trigger": ctx.trigger.rawValue,
            "intervention": ctx.intervention.rawValue,
            "actedOn": true,
            "dismissed": false,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        db.collection("users/\(uid)/wellness/events").addDocument(data: eventData)
    }
}

// MARK: - Context model

struct WellnessInterventionContext: Identifiable {
    let id = UUID()
    let trigger: WellnessTrigger
    let intervention: TSWellnessIntervention
    let customMessage: String?

    var title: String { intervention.title }
    var message: String { customMessage ?? intervention.message }
}
