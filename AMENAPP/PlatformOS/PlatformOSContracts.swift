import Foundation

/// Additive contracts for the long-lived Platform OS layers. These types are not wired
/// into production behavior until a rollout flag is enabled by a reviewed integration.
enum PlatformOSLayer: String, Codable, CaseIterable, Sendable {
    case identity
    case entitlement
    case subscription
    case rolePermission
    case notification
    case aiCreditUsage
    case reputationTrust
    case legalCompliance
    case creatorEconomy
    case organizationLifecycle
    case churchLifecycle
    case communityLifecycle
    case event
    case search
    case mediaRights
    case moderation
    case device
    case membership
    case relationshipGraph
    case recovery
    case audit
    case revenue
    case automation
    case smartContext
    case memoryContinuity
    case governance
}

struct PlatformOSRollout: Codable, Equatable, Sendable {
    var enabledLayers: Set<PlatformOSLayer>

    init(enabledLayers: Set<PlatformOSLayer> = []) {
        self.enabledLayers = enabledLayers
    }

    static let allOff = PlatformOSRollout()

    func isEnabled(_ layer: PlatformOSLayer) -> Bool {
        enabledLayers.contains(layer)
    }
}

enum PlatformOSReadinessStatus: String, Codable, CaseIterable, Sendable {
    case missing
    case audited
    case designed
    case implementedBehindFlag
    case tested
}

enum PlatformOSSeverity: String, Codable, CaseIterable, Sendable {
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"
}

struct PlatformOSGap: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let layer: PlatformOSLayer
    let severity: PlatformOSSeverity
    let summary: String
    let fileReferences: [String]
    let deferredReason: String?

    init(
        id: String,
        layer: PlatformOSLayer,
        severity: PlatformOSSeverity,
        summary: String,
        fileReferences: [String] = [],
        deferredReason: String? = nil
    ) {
        self.id = id
        self.layer = layer
        self.severity = severity
        self.summary = summary
        self.fileReferences = fileReferences
        self.deferredReason = deferredReason
    }
}

struct PlatformOSLayerReadiness: Identifiable, Codable, Equatable, Sendable {
    var id: PlatformOSLayer { layer }
    let layer: PlatformOSLayer
    var status: PlatformOSReadinessStatus
    var gaps: [PlatformOSGap]

    init(layer: PlatformOSLayer, status: PlatformOSReadinessStatus = .missing, gaps: [PlatformOSGap] = []) {
        self.layer = layer
        self.status = status
        self.gaps = gaps
    }
}

protocol PlatformOSEntitlementChecking: Sendable {
    func can(_ userId: String, perform feature: String) async -> Bool
}

protocol PlatformOSPermissionChecking: Sendable {
    func can(_ actorId: String, perform action: String, on resourceId: String) async -> Bool
}

protocol PlatformOSRecoveryRecording: Sendable {
    func markRecoverableDeletion(objectId: String, objectType: String, actorId: String, retentionDays: Int) async throws
}

protocol PlatformOSAuditRecording: Sendable {
    func record(action: String, actorId: String, resourceId: String, metadata: [String: String]) async throws
}

struct DisabledPlatformOSGate: PlatformOSEntitlementChecking, PlatformOSPermissionChecking, Sendable {
    let rollout: PlatformOSRollout

    init(rollout: PlatformOSRollout = .allOff) {
        self.rollout = rollout
    }

    func can(_ userId: String, perform feature: String) async -> Bool {
        false
    }

    func can(_ actorId: String, perform action: String, on resourceId: String) async -> Bool {
        false
    }
}

struct PlatformOSDependencyOrder: Sendable {
    static let foundational: [PlatformOSLayer] = [
        .identity,
        .rolePermission,
        .entitlement,
        .subscription,
        .recovery,
        .audit
    ]

    static let lifecycleAndGraph: [PlatformOSLayer] = [
        .organizationLifecycle,
        .churchLifecycle,
        .communityLifecycle,
        .event,
        .membership,
        .relationshipGraph,
        .device
    ]

    static let intelligenceAndRevenue: [PlatformOSLayer] = [
        .notification,
        .aiCreditUsage,
        .reputationTrust,
        .legalCompliance,
        .creatorEconomy,
        .search,
        .mediaRights,
        .moderation,
        .revenue,
        .automation,
        .smartContext,
        .memoryContinuity,
        .governance
    ]
}
