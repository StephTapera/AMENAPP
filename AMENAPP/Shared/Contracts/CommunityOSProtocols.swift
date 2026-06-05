// CommunityOSProtocols.swift
// AMENAPP — Shared/Contracts
//
// Wave 0 frozen contracts. Downstream agents code against these interfaces.
// Types come from ContentOSModels.swift — do NOT redefine them here.

import Foundation

// MARK: - Safety Service Protocol
// Scans content for sensitive flags and suggests redactions before any share/forward.
// Implemented by Wave 2 Trust & Safety OS.

protocol SafetyService: Sendable {
    func scan(
        _ card: ContentCard,
        body: String
    ) async -> [SafetyFlag]

    func suggestRedactions(
        for card: ContentCard,
        body: String
    ) async -> [ContentRedactionSuggestion]
}

// MARK: - Safety Flags
// Fine-grained signal set returned by SafetyService.scan.

enum SafetyFlag: String, Codable, Sendable {
    case minorPresent
    case schoolIdentifier
    case homeAddress
    case phoneNumber
    case privatePrayer
    case medical
    case financial
    case churchInternal
    case paidContent
    case copyright
    case crisisLanguage
}

// MARK: - Content Router Protocol
// Given a card + caller context, returns ranked destination suggestions.
// Implemented by Wave 2 AI Context Router.

protocol ContentRouter: Sendable {
    func suggestDestinations(
        for card: ContentCard,
        context: ContentRouterContext
    ) async -> [ContentRouteSuggestion]
}

// MARK: - Router Context
// Caller-supplied context that shapes AI routing suggestions.

struct ContentRouterContext: Sendable {
    var memberId: String
    var memberRole: MemberRoleContext
    var currentSpaceId: String?
    var currentChurchId: String?

    enum MemberRoleContext: String, Sendable {
        case guest, member, leader, admin, pastor, moderator
    }
}

// MARK: - Permission Gate Protocol
// The authoritative choke-point: every share/forward/discuss action must
// pass through this gate. Returns whether the action is allowed, gated, or denied.
// Implemented by Wave 2 Discussion / Approval OS.

protocol PermissionGate: Sendable {
    func evaluate(
        action: ContentAction,
        card: ContentCard,
        requestorId: String,
        requestorIsCreator: Bool,
        requestorIsSpaceAdmin: Bool,
        requestorIsChurchAdmin: Bool,
        requestorIsTrustedMember: Bool,
        targetSurface: ContentSurface
    ) async -> ContentPermissionOutcome
}

// MARK: - Stub Implementations
// Used by Wave 1 surfaces until Wave 2 wires in real implementations.

final class StubSafetyService: SafetyService {
    func scan(_ card: ContentCard, body: String) async -> [SafetyFlag] { [] }
    func suggestRedactions(for card: ContentCard, body: String) async -> [ContentRedactionSuggestion] { [] }
}

final class StubContentRouter: ContentRouter {
    func suggestDestinations(
        for card: ContentCard,
        context: ContentRouterContext
    ) async -> [ContentRouteSuggestion] {
        [
            ContentRouteSuggestion(
                action: .saveToChurchNotes,
                label: "Save to Church Notes",
                rationale: "Good place to keep this for personal reference.",
                confidence: 0.9
            ),
            ContentRouteSuggestion(
                action: .discussInSpace,
                label: "Discuss in a Space",
                rationale: "Open a discussion with your community.",
                confidence: 0.7
            )
        ]
    }
}

// Thin adapter — the real permission logic already lives in ContentPermissionEngine.
final class StubPermissionGate: PermissionGate {
    func evaluate(
        action: ContentAction,
        card: ContentCard,
        requestorId: String,
        requestorIsCreator: Bool,
        requestorIsSpaceAdmin: Bool,
        requestorIsChurchAdmin: Bool,
        requestorIsTrustedMember: Bool,
        targetSurface: ContentSurface
    ) async -> ContentPermissionOutcome {
        ContentPermissionEngine.evaluate(
            action: action,
            card: card,
            requestorIsCreator: requestorIsCreator,
            requestorIsSpaceAdmin: requestorIsSpaceAdmin,
            requestorIsChurchAdmin: requestorIsChurchAdmin,
            requestorIsTrustedMember: requestorIsTrustedMember,
            targetSurface: targetSurface
        )
    }
}
