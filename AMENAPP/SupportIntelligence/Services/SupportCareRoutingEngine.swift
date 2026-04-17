//
//  SupportCareRoutingEngine.swift
//  AMENAPP
//
//  Maps support classifications and support profile state into concrete,
//  user-safe actions that the app can render consistently across surfaces.
//

import Foundation

protocol SupportCareRouting: AnyObject, Sendable {
    func route(
        classification: SupportClassification,
        profile: SupportProfile,
        trustedContacts: [SupportTrustedContact],
        surface: SupportSurface
    ) -> SupportRouteDecision
}

final class SupportCareRoutingEngine: SupportCareRouting, @unchecked Sendable {
    func route(
        classification: SupportClassification,
        profile: SupportProfile,
        trustedContacts: [SupportTrustedContact],
        surface: SupportSurface
    ) -> SupportRouteDecision {
        guard classification.severity != .none || !classification.domains.isEmpty else {
            return .none(surface: surface)
        }

        let routingLevel: SupportRoutingLevel
        switch classification.severity {
        case .acute, .elevated:
            routingLevel = .immediateHelp
        case .moderate:
            routingLevel = .guidedSupport
        case .low:
            routingLevel = .gentleSupport
        case .none:
            routingLevel = .none
        }

        var actions: [SupportAction] = []
        let domains = classification.domains
        let hasTrustedContacts = !trustedContacts.isEmpty && profile.trustedContactsEnabled

        if domains.contains(.crisisImmediate) || classification.severity >= .elevated {
            actions.append(SupportAction(type: .call988, title: "Call 988"))
            actions.append(SupportAction(type: .text988, title: "Text 988"))
            actions.append(SupportAction(type: .openBreathingTool, title: "Start grounding"))
        } else if domains.contains(.helpingSomeoneElse) || classification.helpingSomeoneElse {
            actions.append(SupportAction(type: .openHelpingSomeoneElse, title: "Helping someone else"))
            actions.append(SupportAction(type: .openPrayerFlow, title: "Pray for them", promptTemplate: "prayer_for_someone_else"))
        } else {
            if domains.contains(.anxietyStress) || domains.contains(.emotionalWellness) {
                actions.append(SupportAction(type: .openGroundingExercise, title: "3-minute reset"))
                actions.append(SupportAction(type: .openPrayerFlow, title: "Prayer for peace", promptTemplate: "peace_and_calm"))
            }
            if domains.contains(.griefLoss) {
                actions.append(SupportAction(type: .openSupportGroups, title: "Find grief support"))
            }
            if domains.contains(.financialNeed) || domains.contains(.foodHousingNeed) {
                actions.append(SupportAction(type: .openNonprofitResources, title: "Find practical support", filters: ["need": "financial_aid"]))
                actions.append(SupportAction(type: .openFindChurch, title: "Churches with benevolence", filters: ["supportTag": "benevolence"]))
            }
            if domains.contains(.churchHurt) || domains.contains(.newcomerChurchDiscovery) || domains.contains(.lonelinessCommunity) {
                actions.append(SupportAction(type: .openFindChurch, title: "Find a caring church", filters: ["supportTag": "newcomers"]))
            }
            if domains.contains(.counselingTherapy) || domains.contains(.marriageRelationships) || domains.contains(.addictionRecovery) {
                actions.append(SupportAction(type: .openCounselingResources, title: "Explore counseling", filters: ["domain": domains.first?.rawValue ?? "support"]))
            }
            if domains.contains(.prayerSupport) || domains.contains(.bibleGuidance) {
                actions.append(SupportAction(type: .openBerean, title: "Ask Berean", promptTemplate: "support_next_steps"))
            }
        }

        if hasTrustedContacts, routingLevel != .none {
            actions.append(SupportAction(type: .messageTrustedContact, title: "Message someone I trust"))
        }

        if surface == .postDraft || surface == .dmDraft || surface == .note || surface == .churchNote {
            actions.append(SupportAction(type: .saveToPrivateNotes, title: "Save privately"))
            actions.append(SupportAction(type: .convertToPrivatePrayer, title: "Turn into prayer"))
        }

        let promptType: SupportPromptType?
        switch routingLevel {
        case .immediateHelp:
            promptType = .crisisHelpRespectful
        case .guidedSupport:
            if domains.contains(.helpingSomeoneElse) || classification.helpingSomeoneElse {
                promptType = .forFriendGuideSoft
            } else if domains.contains(.financialNeed) || domains.contains(.foodHousingNeed) {
                promptType = .practicalAidBridge
            } else if surface == .churchNote || surface == .note {
                promptType = .noteCareSummary
            } else {
                promptType = .prayerSupportBridge
            }
        case .gentleSupport:
            promptType = .wellnessGroundingSubtle
        case .none:
            promptType = nil
        }

        return SupportRouteDecision(
            routingLevel: routingLevel,
            domains: domains,
            actions: unique(actions),
            promptType: promptType,
            shouldSuppressGiving: classification.severity >= .elevated || profile.givingSuppressed,
            shouldOfferTrustedContact: hasTrustedContacts,
            shouldOfferFollowUp: profile.followUpsEnabled && routingLevel != .none,
            supportingReasons: classification.reasoningCodes,
            sourceSurface: surface
        )
    }

    private func unique(_ actions: [SupportAction]) -> [SupportAction] {
        var seen = Set<SupportActionType>()
        return actions.filter { seen.insert($0.type).inserted }
    }
}
