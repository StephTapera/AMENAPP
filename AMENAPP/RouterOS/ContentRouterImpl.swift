// ContentRouterImpl.swift
// AMENAPP — RouterOS
// Real implementation of ContentRouter. Combines rule-based suggestions
// with Firebase callable for AI-powered routing.

import Foundation
import FirebaseFunctions

final class ContentRouterImpl: ContentRouter {
    private let functions = Functions.functions()

    func suggestDestinations(
        for card: ContentCard,
        context: ContentRouterContext
    ) async -> [ContentRouteSuggestion] {
        // Build rule-based base suggestions first (instant, no network)
        var suggestions = ruleBased(card: card, context: context)

        // Overlay with AI suggestions if body is substantial
        if let body = card.body as String?, !body.isEmpty && body.count > 30 {
            let aiSuggestions = await aiSuggestions(card: card, context: context)
            // Merge: AI suggestions take priority if action not already present
            for ai in aiSuggestions {
                if !suggestions.contains(where: { $0.action == ai.action }) {
                    suggestions.append(ai)
                }
            }
        }

        // Sort by confidence desc, cap at 6
        return suggestions
            .sorted { $0.confidence > $1.confidence }
            .prefix(6)
            .map { $0 }
    }

    // MARK: - Rule-Based Routing

    private func ruleBased(card: ContentCard, context: ContentRouterContext) -> [ContentRouteSuggestion] {
        var s: [ContentRouteSuggestion] = []

        // Saving to Church Notes is always safe
        s.append(ContentRouteSuggestion(
            action: .saveToChurchNotes,
            label: "Save to Church Notes",
            rationale: "Keeps this for your personal reference.",
            confidence: 0.85
        ))

        // Prayer content → prayer room or mentor
        if card.hasPrayerContent || card.sourceType == .prayerRequest {
            s.append(ContentRouteSuggestion(
                action: .createPrayerRoom,
                label: "Open a Prayer Room",
                rationale: "Gather others to pray for this together.",
                confidence: 0.90
            ))
            s.append(ContentRouteSuggestion(
                action: .sendToMentor,
                label: "Send to Mentor",
                rationale: "Your mentor can pray with you privately.",
                confidence: 0.75
            ))
        }

        // Sermon clips → study or discuss
        if card.sourceType == .sermonClip || card.sourceType == .churchNote {
            s.append(ContentRouteSuggestion(
                action: .createStudy,
                label: "Start a Bible Study",
                rationale: "Turn this into a guided study for your group.",
                confidence: 0.82
            ))
            s.append(ContentRouteSuggestion(
                action: .discussInSpace,
                label: "Discuss in Your Space",
                rationale: "Share the insight with your community.",
                confidence: 0.70
            ))
        }

        // Events → discuss or follow-up
        if card.sourceType == .event {
            s.append(ContentRouteSuggestion(
                action: .createEventFollowUp,
                label: "Create Event Follow-Up",
                rationale: "Keep the conversation going after the event.",
                confidence: 0.78
            ))
        }

        // DM messages → notes only (cannot go public)
        if card.isDM {
            return s.filter { $0.action == .saveToChurchNotes || $0.action == .sendToMentor }
        }

        // Restricted content → request permission before broader share
        if card.originalAudience.isRestricted {
            s.append(ContentRouteSuggestion(
                action: .requestPermission,
                label: "Ask Creator for Permission",
                rationale: "This content is restricted — ask before sharing.",
                confidence: 0.95
            ))
        }

        return s
    }

    // MARK: - AI Suggestions

    private func aiSuggestions(card: ContentCard, context: ContentRouterContext) async -> [ContentRouteSuggestion] {
        do {
            let result = try await functions.httpsCallable("contentRouteSuggest").call([
                "cardId":      card.id,
                "sourceType":  card.sourceType.rawValue,
                "audience":    card.originalAudience.rawValue,
                "bodyPreview": String((card.body ?? "").prefix(500)),
                "memberId":    context.memberId,
                "memberRole":  context.memberRole.rawValue
            ])
            guard let data = result.data as? [[String: Any]] else { return [] }
            return data.compactMap { dict -> ContentRouteSuggestion? in
                guard let actionStr = dict["action"] as? String,
                      let action = ContentAction(rawValue: actionStr),
                      let label = dict["label"] as? String,
                      let rationale = dict["rationale"] as? String,
                      let confidence = dict["confidence"] as? Double else { return nil }
                return ContentRouteSuggestion(action: action, label: label, rationale: rationale, confidence: confidence)
            }
        } catch {
            return []
        }
    }
}
