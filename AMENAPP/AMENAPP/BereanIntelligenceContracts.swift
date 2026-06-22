// BereanIntelligenceContracts.swift
// AMENAPP — Berean Assistant UI frozen contracts.
// Foundation for all Berean UI components: enums, models, shared tokens.
// DO NOT change signatures without re-broadcasting to all component files.

import SwiftUI

// MARK: - BereanIntelligenceState

enum BereanIntelligenceState: String, CaseIterable {
    case scriptureExplanation
    case prayerSupport
    case churchNotes
    case emotionalSupport
    case safePosting
    case theologicalComparison
    case communityDiscussion
    case reminderActionPlanning
}

// MARK: - SmartAction

enum SmartAction: String, CaseIterable, Identifiable {
    case explainVerse
    case createPrayer
    case summarizeNotes
    case compareTranslations
    case saveReflection
    case startDiscussion
    case shareSafely

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explainVerse:         return "Explain Verse"
        case .createPrayer:         return "Create Prayer"
        case .summarizeNotes:       return "Summarize Notes"
        case .compareTranslations:  return "Compare Translations"
        case .saveReflection:       return "Save Reflection"
        case .startDiscussion:      return "Start Discussion"
        case .shareSafely:          return "Share Safely"
        }
    }

    var systemImage: String {
        switch self {
        case .explainVerse:         return "book.pages"
        case .createPrayer:         return "hands.sparkles"
        case .summarizeNotes:       return "doc.text"
        case .compareTranslations:  return "arrow.left.arrow.right"
        case .saveReflection:       return "bookmark"
        case .startDiscussion:      return "bubble.left.and.bubble.right"
        case .shareSafely:          return "square.and.arrow.up.trianglebadge.exclamationmark"
        }
    }
}

// MARK: - TrayAction

enum TrayAction: String, CaseIterable, Identifiable {
    case addBibleVerse
    case addPrayerRequest
    case addChurchNotes
    case addPhotoSafely
    case addVoiceNote
    case addSermonClip
    case addReminder
    case shareToSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addBibleVerse:    return "Add Bible verse"
        case .addPrayerRequest: return "Add prayer request"
        case .addChurchNotes:   return "Add church notes"
        case .addPhotoSafely:   return "Add photo safely"
        case .addVoiceNote:     return "Add voice note"
        case .addSermonClip:    return "Add sermon clip"
        case .addReminder:      return "Add reminder"
        case .shareToSpace:     return "Share to Space"
        }
    }

    var systemImage: String {
        switch self {
        case .addBibleVerse:    return "book.closed"
        case .addPrayerRequest: return "hands.sparkles"
        case .addChurchNotes:   return "note.text"
        case .addPhotoSafely:   return "photo.badge.checkmark"
        case .addVoiceNote:     return "waveform"
        case .addSermonClip:    return "film.stack"
        case .addReminder:      return "bell"
        case .shareToSpace:     return "person.3"
        }
    }

    var requiresModeration: Bool {
        self == .addPhotoSafely || self == .shareToSpace
    }
}

// MARK: - BereanPulse

struct BereanPulse: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let iconAsset: String

    static let today = BereanPulse(
        id: UUID(),
        title: "Today's Berean Pulse",
        subtitle: "Scripture, prayer, wisdom, and what matters today.",
        iconAsset: "berean.pulse"
    )
}

// MARK: - ComposerState

struct ComposerState {
    var text: String = ""
    var detectedState: BereanIntelligenceState? = nil
    var suggestedActions: [SmartAction] = []
    var isTrayOpen: Bool = false
}

// MARK: - BereanShareDraft

struct BereanShareDraft: Identifiable {
    let id: UUID
    let text: String
    let mediaURL: URL?
    let destinationLabel: String

    init(text: String, mediaURL: URL? = nil, destinationLabel: String = "Community") {
        self.id = UUID()
        self.text = text
        self.mediaURL = mediaURL
        self.destinationLabel = destinationLabel
    }
}

// MARK: - ReflectionDraft

struct ReflectionDraft: Identifiable {
    let id: UUID
    let text: String
    let verse: String?
    let mood: String?

    init(text: String, verse: String? = nil, mood: String? = nil) {
        self.id = UUID()
        self.text = text
        self.verse = verse
        self.mood = mood
    }
}

// MARK: - DesignTokens

enum DesignTokens {
    // Surfaces
    static let surfaceWhite         = Color(.systemBackground)
    static let surfacePageGray      = Color(red: 0.971, green: 0.971, blue: 0.969)
    static let glassFill            = Color.white.opacity(0.52)
    static let glassStroke          = Color.white.opacity(0.55)

    // Text
    static let textPrimary          = Color.primary
    static let textSecondary        = Color.secondary
    static let textTertiary         = Color(.tertiaryLabel)

    // Accent — blue voice orb
    static let accentBlue           = Color(red: 0.20, green: 0.48, blue: 1.00)

    // Radii
    static let radiusCard: CGFloat          = 22
    static let radiusCapsule: CGFloat       = 30
    static let radiusPill: CGFloat          = 14

    // Spacing
    static let spacingXS: CGFloat   = 4
    static let spacingS: CGFloat    = 8
    static let spacingM: CGFloat    = 16
    static let spacingL: CGFloat    = 24
    static let spacingXL: CGFloat   = 32

    // Shadow
    static let shadowCard           = Color.black.opacity(0.05)
    static let shadowElevated       = Color.black.opacity(0.10)
}

// MARK: - Glass ViewModifier

struct BereanLiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = DesignTokens.radiusCard

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: DesignTokens.shadowCard, radius: 12, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
        } else {
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(DesignTokens.glassFill)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [DesignTokens.glassStroke, DesignTokens.glassStroke.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: DesignTokens.shadowCard, radius: 12, y: 4)
        }
    }
}

extension View {
    func bereanLiquidGlass(cornerRadius: CGFloat = DesignTokens.radiusCard) -> some View {
        modifier(BereanLiquidGlassModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Accessibility Helpers

enum BereanAccessibility {
    static func selectableLabel(_ action: SmartAction) -> String {
        "Berean action: \(action.title)"
    }
    static func trayActionLabel(_ action: TrayAction) -> String {
        action.requiresModeration
            ? "\(action.title) — reviewed for safety before adding"
            : action.title
    }
}
