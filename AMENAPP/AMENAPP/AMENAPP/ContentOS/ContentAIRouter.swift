// ContentAIRouter.swift
// AMENAPP — ContentOS
//
// AI-powered destination router. Takes a ContentCard and returns ranked
// ContentRouteSuggestions telling the user the best next action.
// Backed by Firebase Functions (same pattern as BereanContextActionEngine).

import Foundation
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class ContentAIRouter: ObservableObject {
    static let shared = ContentAIRouter()
    private init() {}

    @Published private(set) var isLoading = false
    @Published private(set) var suggestions: [ContentRouteSuggestion] = []
    @Published private(set) var errorMessage: String?

    private let functions = Functions.functions()

    // MARK: - Route

    func route(card: ContentCard) async {
        guard AMENFeatureFlags.shared.contentAIRouterEnabled else {
            suggestions = localFallbackSuggestions(for: card)
            return
        }
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Sign in to get routing suggestions."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await functions.httpsCallable("routeContentAction").call([
                "contentId":        card.id,
                "sourceType":       card.sourceType.rawValue,
                "sourceSurface":    card.sourceSurface.rawValue,
                "originalAudience": card.originalAudience.rawValue,
                "hasPrayerContent": card.hasPrayerContent,
                "sensitivityScore": card.sensitivityScore,
                "title":            card.title,
                "bodyPreview":      String(card.body.prefix(500))
            ] as [String: Any])

            if let data = result.data as? [[String: Any]] {
                suggestions = data.compactMap { parseSuggestion($0) }
            } else {
                suggestions = localFallbackSuggestions(for: card)
            }
        } catch {
            suggestions = localFallbackSuggestions(for: card)
        }
    }

    func clear() {
        suggestions = []
        errorMessage = nil
    }

    // MARK: - Local Fallback (no network needed)

    private func localFallbackSuggestions(for card: ContentCard) -> [ContentRouteSuggestion] {
        switch card.sourceType {
        case .sermonClip, .livestreamMoment:
            return [
                .init(action: .saveToChurchNotes,  label: "Save to Church Notes",      rationale: "Capture key moments from this sermon.", confidence: 0.95),
                .init(action: .discussInSpace,      label: "Discuss in a Space",        rationale: "Start a conversation around this clip.",  confidence: 0.85),
                .init(action: .sendToMentor,        label: "Send to Your Mentor",       rationale: "Get deeper reflection with your mentor.",  confidence: 0.75),
                .init(action: .createStudy,         label: "Create a Study",            rationale: "Build a study guide from this message.",   confidence: 0.70)
            ]

        case .prayerRequest:
            return [
                .init(action: .createPrayerRoom,    label: "Open a Prayer Room",        rationale: "Gather others to pray together.",          confidence: 0.90),
                .init(action: .sendToMentor,        label: "Share with Mentor",         rationale: "Your mentor can provide personal support.", confidence: 0.85),
                .init(action: .saveToChurchNotes,   label: "Save Privately",            rationale: "Keep this as a private prayer reminder.",  confidence: 0.80)
            ]

        case .event:
            return [
                .init(action: .createEventFollowUp, label: "Create Follow-Up",         rationale: "Keep the conversation going after the event.", confidence: 0.90),
                .init(action: .sendToSmallGroup,    label: "Share with Small Group",   rationale: "Invite your group to this event.",              confidence: 0.85),
                .init(action: .saveToChurchNotes,   label: "Save to Notes",            rationale: "Add this event to your church notes.",          confidence: 0.75)
            ]

        case .testimony:
            return [
                .init(action: .discussInSpace,      label: "Share in a Space",          rationale: "Encourage others with this testimony.",     confidence: 0.90),
                .init(action: .createStudy,         label: "Build a Study from This",   rationale: "Use this as a discussion starter.",         confidence: 0.75),
                .init(action: .saveToChurchNotes,   label: "Save to Notes",             rationale: "Archive this testimony for future reference.", confidence: 0.70)
            ]

        default:
            return [
                .init(action: .discussInSpace,      label: "Discuss in a Space",        rationale: "Start a discussion around this content.",   confidence: 0.80),
                .init(action: .saveToChurchNotes,   label: "Save to Church Notes",      rationale: "Save this for personal reference.",         confidence: 0.75),
                .init(action: .sendToMentor,        label: "Send to Mentor",            rationale: "Get guidance on this content.",             confidence: 0.65)
            ]
        }
    }

    // MARK: - Parse

    private func parseSuggestion(_ dict: [String: Any]) -> ContentRouteSuggestion? {
        guard
            let actionRaw  = dict["action"]     as? String,
            let action     = ContentAction(rawValue: actionRaw),
            let label      = dict["label"]      as? String,
            let rationale  = dict["rationale"]  as? String
        else { return nil }

        let confidence = dict["confidence"] as? Double ?? 0.5
        return ContentRouteSuggestion(action: action, label: label, rationale: rationale, confidence: confidence)
    }
}
