// ExternalOSContracts.swift — AMEN IntegrationOS
// X1–X7 provider-agnostic contracts for all external integrations.

import Foundation

// MARK: - X1: Provider Adapter

protocol ProviderAdapter: AnyObject {
    var providerId: String { get }
    var capabilities: ProviderCapabilitySet { get }
    var costClass: ProviderCostClass { get }
    func authorize(scopes: [ConsentScope]) async throws
    func refresh() async throws
    func revoke() async throws
    func fetch(request: ProviderRequest) async throws -> ProviderResponse
    func normalize(payload: ProviderResponse) throws -> ExternalUniversalObject
    func health() async -> ProviderHealthStatus
}

// MARK: - X2: Consent Scope

enum ConsentScope: String, Codable, CaseIterable, Hashable {
    case calendarRead, calendarWrite, locationApproximate, locationPrecise
    case contactsHashedMatch, healthWalkingSteps, healthSleepData, healthWorkouts
    case mediaLibraryRead, musicPlayback, messagingPush, messagingSMS, messagingEmail
    case webhookReceive, orgKnowledgeRead, orgKnowledgeWrite
    case eventsRead, eventsRSVP, profileRead, opportunityPost
}

// MARK: - X3: Provider Capability

struct ProviderCapabilitySet: OptionSet {
    let rawValue: Int
    static let maps         = ProviderCapabilitySet(rawValue: 1 << 0)
    static let calendar     = ProviderCapabilitySet(rawValue: 1 << 1)
    static let contacts     = ProviderCapabilitySet(rawValue: 1 << 2)
    static let media        = ProviderCapabilitySet(rawValue: 1 << 3)
    static let health       = ProviderCapabilitySet(rawValue: 1 << 4)
    static let messaging    = ProviderCapabilitySet(rawValue: 1 << 5)
    static let events       = ProviderCapabilitySet(rawValue: 1 << 6)
    static let transport    = ProviderCapabilitySet(rawValue: 1 << 7)
    static let knowledge    = ProviderCapabilitySet(rawValue: 1 << 8)
    static let career       = ProviderCapabilitySet(rawValue: 1 << 9)
}

enum ProviderCostClass: String, Codable {
    case free, paid, metered
}

// MARK: - X4: Provider Request / Response

struct ProviderRequest {
    let scopes: [ConsentScope]
    let parameters: [String: Any]
    let requestId: String = UUID().uuidString
}

struct ProviderResponse {
    let providerId: String
    let payload: [String: Any]
    let statusCode: Int
    let timestamp: Date = Date()
}

// MARK: - X5: Universal Object

struct ExternalUniversalObject: Identifiable, Codable {
    let id: String
    let sourceProviderId: String
    let type: ExternalObjectType
    let title: String
    let subtitle: String?
    let metadata: [String: String]
    let fetchedAt: Date
}

enum ExternalObjectType: String, Codable {
    case mapPlace, calendarEvent, contact, mediaTrack, healthMetric
    case messagingChannel, opportunity, knowledgeDoc, churchEvent
}

// MARK: - X6: Provider Health

enum ProviderHealthStatus: String, Codable {
    case healthy, degraded, unavailable, unauthorized
}

struct ProviderHealthReport: Identifiable {
    let id: String
    let providerId: String
    let status: ProviderHealthStatus
    let lastChecked: Date
    let latencyMs: Int?
    let errorMessage: String?
}

// MARK: - X7: Cost Governor

protocol CostGovernorProtocol {
    func canProceed(scope: ConsentScope, estimatedCost: Double) async -> Bool
    func recordUsage(scope: ConsentScope, actualCost: Double) async
    func currentBudget() async -> Double
    func resetMonthly() async
}

// MARK: - Consent Ledger Entry

struct ConsentLedgerEntry: Codable, Identifiable {
    var id: String = UUID().uuidString
    let uid: String
    let scope: ConsentScope
    let providerId: String
    let granted: Bool
    let grantedAt: Date
    let revokedAt: Date?
    let userAgent: String
}

// MARK: - Webhook Payload

struct WebhookPayload: Codable {
    let providerId: String
    let event: String
    let signature: String
    let body: Data
    let receivedAt: Date
}

// MARK: - Minor Account Guard

enum AccountTier: String {
    case minor, standard, verified, creator
}

struct MinorAccountGuard {
    static let blockedScopes: [ConsentScope] = [
        .contactsHashedMatch, .messagingSMS, .messagingEmail
    ]

    static func isBlocked(_ scope: ConsentScope, for tier: AccountTier) -> Bool {
        guard tier == .minor else { return false }
        return blockedScopes.contains(scope)
    }
}
