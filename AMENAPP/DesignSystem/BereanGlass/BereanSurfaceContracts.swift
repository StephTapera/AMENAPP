// BereanSurfaceContracts.swift
// AMEN — Berean Reading Surface (BRS): frozen type contracts (Wave 0)
//
// FROZEN after BRS-W0-GATE. No agent may add, remove, rename, or retype
// anything in this file without a Class C blocker and human approval.
//
// Pre-check results (2026-06-16):
//   BAS tokens: basWarmPaper / basWineRed / basTan / basInk — present in
//               BereanAgentContracts.swift:466-482. berean* are aliases.
//   GlassEffectContainer: iOS 26 SwiftUI API, shimmed in GlassEffectModifiers.swift
//   Motion.adaptive: present in Motion.swift
//   Features/Berean/: did not exist — new path, created safely
//   BereanOrbState, BereanAIAction, BereanHomeChip: no prior definitions found
//   LiquidGlassCard/Pill/Toolbar/InputBar: no prior definitions found
//   VoiceOrb, ScriptureActionRow, AIKeyboardToolbar: no prior definitions found
//   WordGlowLoader, FloatingPrimaryCTA: no prior definitions found
//   BereanSpeaker, BereanTranscriptTurn, BereanPrayerEntry: no prior definitions found
//
// Safety invariants (enforced by implementations, documented here):
//   mic consent: mandatory explicit gate before any capture
//   journals: private by default; move-to-shared requires confirmation + Guard routing
//   UGC (voice transcripts, notes, prayer entries): all route through GUARDIAN/Aegis
//   crisis language: route to existing safe path — no new copy, no hard-coded resources
//   child safety / COPPA: all surfaces inherit existing gates — do not bypass
//   zero new Cloud Functions without explicit human sign-off

import Foundation
import SwiftUI

// MARK: - C-1: Orb State

/// Visual + semantic state of VoiceOrb — maps 1:1 to the active Berean backend mode.
/// idle = orb hidden; all other states show the orb.
enum BereanOrbState: Equatable {
    case idle
    case listening      // → Ask mode
    case discerning     // → Discern mode
    case praying        // → Reflect mode
    case summarizing    // → Build mode
}

// MARK: - C-2: Backend Modes

/// The five Berean callable-proxy modes. rawValue = function name fragment.
enum BereanBackendMode: String {
    case ask
    case discern
    case build
    case guard_  = "guard"
    case reflect
}

// MARK: - C-3: AI Actions

/// Every AI-backed action surfaced by the reading surface.
/// Each case documents the backend mode it routes to.
/// Zero new Cloud Functions — all route through the existing Berean callable proxy.
enum BereanAIAction: CaseIterable {

    // → Ask
    case explainPassage
    case clarifyTerm
    case askBerean

    // → Discern  (may surface contested readings in bereanWine — suggestive, not authoritative)
    case crossReference
    case originalLanguage
    case checkContext

    // → Build
    case summarize
    case outline
    case studyPlan
    case turnIntoPrayer
    case devotional

    // → Reflect
    case guidedPrayer
    case scriptureToMeditate

    var routesTo: BereanBackendMode {
        switch self {
        case .explainPassage, .clarifyTerm, .askBerean:
            return .ask
        case .crossReference, .originalLanguage, .checkContext:
            return .discern
        case .summarize, .outline, .studyPlan, .turnIntoPrayer, .devotional:
            return .build
        case .guidedPrayer, .scriptureToMeditate:
            return .reflect
        }
    }

    var displayName: String {
        switch self {
        case .explainPassage:      return "Explain"
        case .clarifyTerm:         return "Clarify"
        case .askBerean:           return "Ask Berean"
        case .crossReference:      return "Cross-Reference"
        case .originalLanguage:    return "Original Language"
        case .checkContext:        return "Check Context"
        case .summarize:           return "Summarize"
        case .outline:             return "Outline"
        case .studyPlan:           return "Study Plan"
        case .turnIntoPrayer:      return "Turn into Prayer"
        case .devotional:          return "Devotional"
        case .guidedPrayer:        return "Guided Prayer"
        case .scriptureToMeditate: return "Scripture to Meditate"
        }
    }
}

// MARK: - C-4: Home Quick-Action Chips

enum BereanHomeChip: String, CaseIterable, Identifiable {
    case readScripture   = "Read Scripture"
    case askBerean       = "Ask Berean"
    case explainPassage  = "Explain a Passage"
    case sermonNotes     = "Sermon Notes"
    case prayerJournal   = "Prayer Journal"
    case dailyPlan       = "Daily Plan"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .readScripture:  return "book.fill"
        case .askBerean:      return "sparkle"
        case .explainPassage: return "text.magnifyingglass"
        case .sermonNotes:    return "note.text"
        case .prayerJournal:  return "hands.and.sparkles.fill"
        case .dailyPlan:      return "calendar.badge.clock"
        }
    }
}

// MARK: - C-5: FloatingCTA Labels

enum BereanCTALabel: String {
    case continueStudy    = "Continue Study"
    case openPassage      = "Open Passage"
    case startPrayer      = "Start Prayer"
    case nextReflection   = "Next Reflection"
}

// MARK: - C-6: Word Glow Words

enum BereanGlowWord: String, CaseIterable {
    case light = "LIGHT"
    case word  = "WORD"
    case truth = "TRUTH"
    case grace = "GRACE"
    case abide = "ABIDE"
    case peace = "PEACE"
}

// MARK: - C-7: Feature Flags

/// All feature flags for the Berean Reading Surface. All default false.
enum BereanSurfaceFlag {
    static let glassComponents = "bereanGlassComponents"  // W1 dev-only
    static let homeV2          = "bereanHomeV2"           // W2
    static let askBar          = "bereanAskBar"           // W3
    static let listening       = "bereanListening"        // W3
    static let notesEditor     = "bereanNotesEditor"      // W4
    static let readerActions   = "bereanReaderActions"    // W5
    static let prayerJournal   = "bereanPrayerJournal"    // W6
    static let wordLoader      = "bereanWordLoader"       // W7
}

// MARK: - C-8: Supporting Value Types

/// A single turn in the Listening Mode transcript.
struct BereanTranscriptTurn: Identifiable {
    let id: UUID
    let speaker: BereanSpeaker
    let text: String
    let scriptureReference: String?  // nil if Berean did not cite scripture in this turn
}

enum BereanSpeaker {
    case user
    case berean
}

/// A single prayer journal entry.
struct BereanPrayerEntry: Identifiable {
    let id: UUID
    var text: String
    var isAnswered: Bool
    var dateCreated: Date
}

// MARK: - C-9: Screen ViewModel Protocols

@MainActor
protocol BereanHomeViewModelProtocol: AnyObject {
    var greeting: String { get }
    var contextLine: String { get }
    var continueStudyTitle: String? { get }  // nil → hide Continue card
    var chips: [BereanHomeChip] { get }
    var inputText: String { get set }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    func onChipTapped(_ chip: BereanHomeChip)
    func onContinueStudyTapped()
    func submitInput()
}

@MainActor
protocol BereanListeningViewModelProtocol: AnyObject {
    /// Consent must be explicitly granted before any capture begins.
    var hasMicConsent: Bool { get }
    var orbState: BereanOrbState { get }
    var transcript: [BereanTranscriptTurn] { get }
    var isRecording: Bool { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    func requestMicConsent() async
    func toggleRecording()
    func pause()
    func saveToNotes()
    func convertTranscript(to action: BereanAIAction)
    func endSession()
}

@MainActor
protocol BereanNotesEditorViewModelProtocol: AnyObject {
    var title: String { get set }
    var body: String { get set }
    var isSyncing: Bool { get }
    var hasPendingOfflineChanges: Bool { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    func triggerAction(_ action: BereanAIAction)
    func save()
}

@MainActor
protocol BereanScriptureReaderViewModelProtocol: AnyObject {
    var passageTitle: String { get }
    var verseText: String { get }
    var isActionRowCollapsed: Bool { get }
    var selectedVerseRange: String? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    func triggerAction(_ action: BereanAIAction)
    func shareWithConfirmation()
    func onScrolled(velocity: CGFloat)
}

@MainActor
protocol BereanPrayerJournalViewModelProtocol: AnyObject {
    var todayEntry: String { get set }
    var answeredPrayers: [BereanPrayerEntry] { get }
    var prayerList: [BereanPrayerEntry] { get }
    var scriptureToPray: String? { get }
    /// Journals are private by default. isPrivate = true unless user explicitly shares.
    var isPrivate: Bool { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    /// Invokes confirmation sheet before any Guard routing.
    func requestShare()
    func triggerAction(_ action: BereanAIAction)
    func saveEntry()
    func markAnswered(_ entry: BereanPrayerEntry)
}

// MARK: - C-10: Toolbar Item Model

/// A single action item in LiquidGlassToolbar.
struct BereanToolbarItem: Identifiable {
    let id: String
    let icon: String
    let label: String
    let action: () -> Void
}
