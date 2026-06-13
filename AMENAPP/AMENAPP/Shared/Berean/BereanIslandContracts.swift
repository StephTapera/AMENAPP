// BereanIslandContracts.swift
// AMEN — Berean Island frozen type contracts (Wave 0)
//
// FROZEN after W0-GATE. No agent may add, remove, rename, or retype
// anything in this file. File a Class C blocker if a contract change
// is needed; only the human amends this file.
//
// Naming-conflict deviations from spec (Class A self-resolved, 2026-06-13):
//   AmenSurface    → BereanSurface         (conflicts with AmenSurface design-token namespace)
//   GlassCard      → IslandCard            (BereanGlassCard<Content:View> & GlassCard<Content:View> both exist)
//   ContextSignal  → BereanSignalKind      (conflicts with ContextSignal struct in Shared/Contracts)
//   LiveSession    → IslandLiveSession     (conflicts with LiveSession struct in LiveChurchModeService)
//   Citation       → IslandCitation        (BereanCitation already exists in BereanAnswerEngine)
//   SafetyFlag     → IslandSafetyFlag      (BereanSafetyFlag already exists in BereanCoreService)
//   QuickAction    → IslandAction          (struct QuickAction already exists in ModerationConsoleModels)

import Foundation

// MARK: - Island State Machine

enum IslandState: Equatable, Codable {
    case hidden
    case compact(whisper: String?)                 // whisper ≤ 24 chars, nil = glyph only
    case expanded(context: IslandContext)
    case live(session: IslandLiveSession)
    case actionReady(suggestion: IslandSuggestion)
}

struct IslandContext: Equatable, Codable {
    var surface: BereanSurface
    var prefill: String?                            // e.g. selected verse text
    var quickActions: [IslandAction]                // exactly ≤ 4 shown; rest overflow
    var lastAnswerID: String?
}

/// Routing surface for Berean Island. Named BereanSurface to avoid conflict
/// with the existing AmenSurface design-token namespace enum.
enum BereanSurface: String, Codable {
    case feed, post, messages, spaces, churchNotes, bibleStudy, search, lens, none
}

/// Named IslandAction to avoid conflict with struct QuickAction in ModerationConsoleModels.
enum IslandAction: String, Codable, CaseIterable {
    case askBerean, saveNote, openBible, prayNow, shareToAmen,
         messageGroup, createReminder, planVisit, startStudy, compareTranslations
}

struct IslandSuggestion: Equatable, Codable, Identifiable {
    let id: String                                  // trigger id; consumed once, never re-fires
    var message: String                             // ≤ 60 chars
    var action: IslandAction
    var contextChips: [BereanContextChip]
    var expiresAfterSeconds: Int                    // default 12
}

/// Named IslandLiveSession to avoid conflict with LiveSession in LiveChurchModeService.
struct IslandLiveSession: Equatable, Codable, Identifiable {
    let id: String
    var kind: LiveSessionKind
    var startedAt: Date
    var statusLine: String                          // "Sermon Companion · 14 verses"
    var progress: Double?                           // nil = indeterminate quiet ring
}

enum LiveSessionKind: String, Codable {
    case sermonCompanion, guidedStudy, prayerTimer, eventInProgress
}

// MARK: - Context Engine

struct ContextPacket: Codable {
    var intent: BereanIntent
    var surface: BereanSurface
    var fields: [ContextField]                      // ONLY fields the intent requires
    var assembledAt: Date
}

struct ContextField: Codable {
    var signal: BereanSignalKind
    var value: String                               // minimized, pre-serialized on device
    var chip: BereanContextChip                     // user-facing legibility label
}

/// Signal registry kind for Berean Island context assembly. Named BereanSignalKind
/// to avoid conflict with the existing ContextSignal struct in Shared/Contracts.
enum BereanSignalKind: String, Codable, CaseIterable {
    case timeOfDay, amenActivity, savedSermons, preferences,      // default ON
         calendar, locationCoarse, reminders, churchAttendance,   // grant required (Tier C)
         recentConversations                                      // grant required (Tier S rules)
}

struct BereanContextChip: Codable, Equatable {
    var label: String                               // "calendar (tonight)"
    var signal: BereanSignalKind
}

enum BereanIntent: String, Codable {
    case ask, discern, build, guard_, reflect       // routes to existing five modes
    case action                                     // local-only quick action, no model call
}

// MARK: - Glass Cards

/// Berean Island glass card data model. Named IslandCard to avoid conflict with
/// both BereanGlassCard<Content:View> (BereanGlassSystem) and GlassCard<Content:View> (SOSharedComponents).
struct IslandCard: Codable, Identifiable {
    let id: String
    var kind: IslandCardKind
    var header: String
    var body: String
    var sourceLine: String?                         // "John 15:5 · BSB"
    var citations: [IslandCitation]                 // mandatory non-empty for .answer w/ theological claims
    var actions: [IslandCardAction]
    var aiAssisted: Bool                            // drives C2PA signing on share
    var payload: IslandCardPayload?
}

enum IslandCardKind: String, Codable {
    case verse, answer, event, sermon, music, link
}

enum IslandCardAction: String, Codable {
    case save, share, askFollowUp, addToCalendar, rsvp, openNote, compareTranslations
}

enum IslandCardPayload: Codable {
    case verse(reference: String, translation: String)
    case event(title: String, startsAt: Date, location: String?)
    case sermon(noteID: String)
    case link(url: URL)
}

/// Named IslandCitation to avoid conflict with BereanCitation in BereanAnswerEngine.
struct IslandCitation: Codable, Equatable {
    var reference: String
    var translation: String
    var verified: Bool                              // from existing verification pipeline
}

// MARK: - Lens

enum LensMode: String, Codable, CaseIterable {
    case bible, sermon, flyer, study, safety, fellowship
}

struct LensResult: Codable {
    var mode: LensMode
    var card: IslandCard
    var safetyFlags: [IslandSafetyFlag]             // from GUARDIAN pre-check
    var extracted: LensExtraction?
}

enum LensExtraction: Codable {
    case verse(reference: String)
    case event(title: String, startsAt: Date?, location: String?)
    case text(ocr: String)
}

// MARK: - Safety (pre-post)

/// Named IslandSafetyFlag to avoid conflict with BereanSafetyFlag in BereanCoreService.
struct IslandSafetyFlag: Codable, Equatable {
    var check: IslandSafetyCheck
    var severity: IslandSafetySeverity
    var explanation: String                          // user-facing, educational tone
    var suggestion: String?                          // diffed alternative when applicable
}

enum IslandSafetyCheck: String, Codable {
    case scriptureMisuse, harshTone, gossipRisk, privateInfo,
         manipulativeLanguage, aiReligiousClaim, missingContext,
         minorsInfo, faceConsent
}

enum IslandSafetySeverity: String, Codable {
    case note          // inline education, never blocks
    case friction      // requires explicit confirm
    case block         // hard stop (minorsInfo, aiReligiousClaim generation)
}

// MARK: - Component API Contracts (from spec Part 2.3)

// GlassPill — the in-app Island. ActivityKit mirror reads the same state machine.
// GlassPill(state: Binding<IslandState>, onAction: (IslandAction) -> Void,
//           onQuery: (String) -> Void)
// Rules: 44pt compact height; matchedGeometry morph id "berean.island";
// ALL animation through Motion.adaptive; one glass layer (contents flat).

// IslandCardView(card: IslandCard, onAction: (IslandCardAction) -> Void)
// Rules: 24pt corner radius; flattened (non-glass) rendering when exporting
// for share; VoiceOver custom actions rotor for the action row.

// IslandStateMachine: @Observable final class
//   var state: IslandState
//   func fire(trigger: IslandSuggestion)   // enforces ≤3 self-promotions/day,
//                                          // quiet hours, Sabbath mode, consumed ids
//   func startSession(_: LiveSessionKind) / endSession()
//   Persistence: restores across launches from on-device store.
