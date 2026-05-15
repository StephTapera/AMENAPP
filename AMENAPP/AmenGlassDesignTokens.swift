import SwiftUI

// MARK: - AmenGlassMetrics
// Centralized layout constants for the Liquid Glass intelligence layer.

enum AmenGlassMetrics {
    static let cornerRadiusSmall: CGFloat = 10
    static let cornerRadiusMedium: CGFloat = 16
    static let cornerRadiusLarge: CGFloat = 24
    static let pillHeightCompact: CGFloat = 32
    static let pillHeightRegular: CGFloat = 40
    static let borderWidth: CGFloat = 0.6
    static let shadowRadius: CGFloat = 8
    static let innerHighlightOpacity: Double = 0.22
    static let pillHorizontalPadding: CGFloat = 12
    static let pillVerticalPadding: CGFloat = 7
    static let pillStackSpacing: CGFloat = 8
    static let popoverMaxWidth: CGFloat = 280
    static let popoverCornerRadius: CGFloat = 18
}

// MARK: - AmenGlassBehavior
// Behaviour constants for adaptive glass animations and accessibility fallbacks.

enum AmenGlassBehavior {
    static let scrollOpacity: Double = 0.0
    static let pressedScale: CGFloat = 0.97
    static let busyBackgroundOpacity: Double = 0.18
    static let cleanBackgroundOpacity: Double = 0.08
    static let pillHideVelocityThreshold: CGFloat = 300
    static let pillShowRestDelay: TimeInterval = 0.35
    static let presencePillMaxVisible: Int = 3
}

// MARK: - AmenPresencePriority
// Ranks AI action pills. Lower rawValue == shown first when screen is crowded.

enum AmenPresencePriority: Int, Comparable, CaseIterable {
    case safety = 0
    case activeTask = 1
    case semanticDefinition = 2
    case scriptureContext = 3
    case creation = 4
    case reflection = 5
    case navigation = 6
    case secondary = 7

    static func < (lhs: AmenPresencePriority, rhs: AmenPresencePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var analyticsName: String {
        switch self {
        case .safety:             return "safety"
        case .activeTask:         return "active_task"
        case .semanticDefinition: return "semantic_definition"
        case .scriptureContext:   return "scripture_context"
        case .creation:           return "creation"
        case .reflection:         return "reflection"
        case .navigation:         return "navigation"
        case .secondary:          return "secondary"
        }
    }
}

// MARK: - AmenSmartAction
// A ranked AI action that can be surfaced as a Liquid Glass pill.

struct AmenSmartAction: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let priority: AmenPresencePriority
    let requiresAuth: Bool
    let requiresTranscript: Bool
    let analyticsEvent: String
    let action: () -> Void

    init(
        id: String = UUID().uuidString,
        icon: String,
        title: String,
        subtitle: String? = nil,
        priority: AmenPresencePriority = .secondary,
        requiresAuth: Bool = true,
        requiresTranscript: Bool = false,
        analyticsEvent: String = "smart_action_tapped",
        action: @escaping () -> Void
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.priority = priority
        self.requiresAuth = requiresAuth
        self.requiresTranscript = requiresTranscript
        self.analyticsEvent = analyticsEvent
        self.action = action
    }

    static func == (lhs: AmenSmartAction, rhs: AmenSmartAction) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - AmenPulseSignalType
// Signal types that the Pulse awareness layer can detect.

enum AmenPulseSignalType: String, CaseIterable {
    case confusion         = "confusion"
    case scrollFatigue     = "scroll_fatigue"
    case hesitation        = "hesitation"
    case repeatedTap       = "repeated_tap"
    case reflectionMoment  = "reflection_moment"
    case urgency           = "urgency"
    case overload          = "overload"
    case failedAction      = "failed_action"
}

// MARK: - AmenSemanticTerm
// A tappable theological or contextual term found in content.

struct AmenSemanticTerm: Identifiable, Equatable {
    let id: String
    let term: String
    let range: NSRange
    let confidence: Double
    let category: TermCategory

    enum TermCategory: String {
        case theological  = "theological"
        case scripture    = "scripture"
        case general      = "general"
        case spiritual    = "spiritual"
    }

    var isHighConfidence: Bool { confidence >= 0.75 }
}

// MARK: - AmenSemanticDefinition
// A definition payload returned by the defineSemanticTerm Cloud Function.

struct AmenSemanticDefinition: Codable, Identifiable {
    let id: String
    let term: String
    let compactDefinition: String
    let expandedDefinition: String?
    let biblicalContext: String?
    let relatedScriptureRefs: [String]
    let confidence: Double
    let safetyNotes: String?
    let generatedAt: Date
    let modelUsed: String
    let cacheStatus: String

    enum CodingKeys: String, CodingKey {
        case id, term, compactDefinition, expandedDefinition
        case biblicalContext, relatedScriptureRefs, confidence
        case safetyNotes, generatedAt, modelUsed, cacheStatus
    }
}
