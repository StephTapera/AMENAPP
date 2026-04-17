// BereanOnboardingModels.swift
// AMENAPP — Berean Onboarding V3
// All models, enums, content definitions, and starter context derivation.

import Foundation

// MARK: - Step

enum BereanOnboardingStep: Int, CaseIterable, Identifiable, Codable {
    case introduction = 0
    case capabilities = 1
    case focus = 2
    case ready = 3

    var id: Int { rawValue }
    var index: Int { rawValue }
    var analyticsIndex: Int { rawValue + 1 }
    static var total: Int { allCases.count }

    var eyebrow: String {
        switch self {
        case .introduction: return "Your guide for faith and life"
        case .capabilities: return "What Berean helps with"
        case .focus: return "Personalize your focus"
        case .ready: return "Ready to begin"
        }
    }

    var analyticsName: String {
        switch self {
        case .introduction: return "introduction"
        case .capabilities: return "capabilities"
        case .focus: return "focus"
        case .ready: return "ready"
        }
    }

    var isFirst: Bool { self == .introduction }
    var isLast: Bool { self == .ready }
    var next: BereanOnboardingStep? { BereanOnboardingStep(rawValue: rawValue + 1) }
    var previous: BereanOnboardingStep? { BereanOnboardingStep(rawValue: rawValue - 1) }
}

// MARK: - Focus

enum BereanFocus: String, CaseIterable, Identifiable, Codable, Hashable {
    case faith = "Faith"
    case study = "Study"
    case work = "Work"
    case life = "Life"
    case creativity = "Creativity"
    case building = "Building"

    var id: String { rawValue }
    var label: String { rawValue }

    var icon: String {
        switch self {
        case .faith: return "cross"
        case .study: return "book.pages"
        case .work: return "briefcase"
        case .life: return "heart"
        case .creativity: return "paintbrush"
        case .building: return "hammer"
        }
    }
}

// MARK: - Completion Mode

enum BereanOnboardingCompletionMode: String, Codable {
    case completed
    case skipped
}

// MARK: - Persistence Snapshot

struct BereanOnboardingState: Equatable {
    var hasCompletedBereanOnboarding: Bool
    var selectedFocuses: Set<BereanFocus>
    var lastViewedStep: BereanOnboardingStep
    var completionDate: Date?
    var completionMode: BereanOnboardingCompletionMode?

    static let empty = BereanOnboardingState(
        hasCompletedBereanOnboarding: false,
        selectedFocuses: [],
        lastViewedStep: .introduction,
        completionDate: nil,
        completionMode: nil
    )
}

// MARK: - Starter Context

struct BereanStarterContext: Equatable {
    let selectedFocuses: Set<BereanFocus>
    let promptHints: [String]
    let greetingVariant: String
    let starterPromptCategory: String

    static func derive(from focuses: Set<BereanFocus>) -> BereanStarterContext {
        let hints: [String]
        let greeting: String
        let category: String

        switch true {
        case focuses.isSuperset(of: [.faith, .study]):
            hints = [
                "Explain the context of a Bible passage",
                "What does this verse mean theologically?",
                "Help me understand cross-references for Romans 8"
            ]
            greeting = "Ready to study scripture and explore faith together."
            category = "faith_study"

        case focuses.isSuperset(of: [.work, .life]):
            hints = [
                "Help me think through a decision I'm facing",
                "What does the Bible say about this situation?",
                "How do I balance work and rest faithfully?"
            ]
            greeting = "Ready to help you navigate life and work with wisdom."
            category = "work_life"

        case focuses.isSuperset(of: [.creativity, .building]):
            hints = [
                "How can I create with purpose and intention?",
                "What does scripture say about stewardship of gifts?",
                "Help me think through this project"
            ]
            greeting = "Ready to help you build and create with purpose."
            category = "creativity_building"

        case focuses.contains(.faith):
            hints = [
                "Help me grow in my faith",
                "What does the Bible say about prayer?",
                "Explain a passage I'm reading"
            ]
            greeting = "Ready to walk alongside you in faith."
            category = "faith"

        case focuses.contains(.study):
            hints = [
                "Help me study a passage",
                "What are the main themes of this book?",
                "Give me context for this scripture"
            ]
            greeting = "Ready to help you study scripture more deeply."
            category = "study"

        default:
            hints = [
                "Ask me anything",
                "What’s on your heart today?",
                "Help me think through something"
            ]
            greeting = "Ready to meet you wherever you are."
            category = "default"
        }

        return BereanStarterContext(
            selectedFocuses: focuses,
            promptHints: hints,
            greetingVariant: greeting,
            starterPromptCategory: category
        )
    }
}

// MARK: - Content

struct BereanOnboardingFeature: Equatable {
    let icon: String
    let title: String
    let description: String
}

struct BereanOnboardingStrength: Equatable {
    let icon: String
    let label: String
}

struct BereanOnboardingContent {
    let step1Title: String
    let step1Subtitle: String
    let step1Bullets: [String]
    let step2Title: String
    let step2Features: [BereanOnboardingFeature]
    let step3Title: String
    let step3Subtitle: String
    let step3Footnote: String
    let step4Title: String
    let step4Subtitle: String
    let step4Defaults: [String]
    let step4Strengths: [BereanOnboardingStrength]
    let ctaContinue: String
    let ctaStartChat: String
    let ctaBack: String
    let ctaSkip: String
}

protocol BereanOnboardingContentProviding {
    var content: BereanOnboardingContent { get }
}

struct BereanDefaultOnboardingContentProvider: BereanOnboardingContentProviding {
    let content = BereanOnboardingContent(
        step1Title: "Berean",
        step1Subtitle: "Your AI companion for faith, study, and life.",
        step1Bullets: [
            "Scripture-grounded answers",
            "Clear next steps and practices",
            "Respectful, safe, and human-first"
        ],
        step2Title: "What Berean does",
        step2Features: [
            BereanOnboardingFeature(
                icon: "magnifyingglass.circle",
                title: "Study the Bible deeply",
                description: "Context, cross-references, and theological insight on any passage."
            ),
            BereanOnboardingFeature(
                icon: "brain.head.profile",
                title: "Think through life decisions",
                description: "Grounded guidance for work, relationships, and personal choices."
            ),
            BereanOnboardingFeature(
                icon: "heart.text.square",
                title: "Pray and reflect with guidance",
                description: "Prayer prompts, devotionals, and reflective questions tailored to you."
            )
        ],
        step3Title: "What brings you here?",
        step3Subtitle: "Choose what matters most.",
        step3Footnote: "Choose as many as you like. We’ll tailor your prompts and follow-ups.",
        step4Title: "You are ready.",
        step4Subtitle: "Start a conversation and ask anything. Berean will meet you where you are.",
        step4Defaults: ["Faith-aware", "Study-ready", "Human-first"],
        step4Strengths: [
            BereanOnboardingStrength(icon: "sparkles", label: "Smart prompts"),
            BereanOnboardingStrength(icon: "shield.lefthalf.filled", label: "Safe guidance"),
            BereanOnboardingStrength(icon: "bubble.left.and.bubble.right", label: "Natural chat"),
            BereanOnboardingStrength(icon: "book.closed", label: "Scripture context"),
            BereanOnboardingStrength(icon: "person.fill", label: "Human-first tone"),
            BereanOnboardingStrength(icon: "arrow.triangle.turn.up.right.diamond", label: "Thoughtful follow-ups")
        ],
        ctaContinue: "Continue",
        ctaStartChat: "Start Chat",
        ctaBack: "Back",
        ctaSkip: "Skip"
    )
}
