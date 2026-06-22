// AmbientContracts.swift
// AMENAPP — Ambient OS Layer
//
// FROZEN v1 · 2026-06-01
// Orchestrator owns this file. Workers MUST NOT edit contracts directly.
// File a change request back to the Orchestrator; workers consume only.
//
// §2.1  AmbientContext       — server-assembled snapshot (one CF call)
// §2.2  AmbientSummary       — Berean-generated prose + ranked actions
// §2.3  PriorityAction       — shared atom for Home + Priority Actions
// §2.4  GlassToolRailItem    — reusable floating action rail component
// §2.5  SmartComposerIntent  — intent-aware composer suggestion chips

import SwiftUI

// MARK: - §2.1 AmbientContext

/// Read-only, server-assembled snapshot. One CF call (`getAmbientContext`)
/// aggregates it. Consumers MUST NOT read raw Firestore for context —
/// they consume this struct or its derived `AmbientSummary`.
struct AmbientContext: Codable, Sendable {
    let generatedAt: String          // ISO 8601
    let user: AmbientUser
    let prayer: AmbientPrayer
    let notes: AmbientNotes
    let messages: AmbientMessages
    let calendar: AmbientCalendar
    let church: AmbientChurch
    let selah: AmbientSelah
    let arise: AmbientArise
    let bereanSuggestion: AmbientBereanSuggestion?
    /// Explicit-signal mode only. NEVER inferred from background sensors in v1.
    let mode: AmbientMode
}

enum AmbientMode: String, Codable, Sendable {
    case `default`
    case driving
    case atChurch
}

// MARK: User

struct AmbientUser: Codable, Sendable {
    let id: String
    let firstName: String
    let localTime: String            // ISO 8601 in user's tz
    let tz: String                   // IANA timezone identifier
}

// MARK: Prayer (aggregated counts — never raw request bodies)

struct AmbientPrayer: Codable, Sendable {
    let awaitingResponse: [PrayerRef]
    let openRequests: Int            // private to this user
}

struct PrayerRef: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let deepLink: String
    let createdAt: String            // ISO 8601
}

// MARK: Notes

struct AmbientNotes: Codable, Sendable {
    let unfinished: [NoteRef]
    let lastEditedAt: String?        // ISO 8601
}

struct NoteRef: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let deepLink: String
    let editedAt: String             // ISO 8601
}

// MARK: Messages

struct AmbientMessages: Codable, Sendable {
    let needingFollowUp: [ThreadRef]
    let unreadThreads: Int           // private to this user
}

struct ThreadRef: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let deepLink: String
    let lastMessageAt: String        // ISO 8601
}

// MARK: Calendar

struct AmbientCalendar: Codable, Sendable {
    let today: [EventRef]
    let nextEvent: EventRef?
}

struct EventRef: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let deepLink: String
    let startsAt: String             // ISO 8601
    let endsAt: String?              // ISO 8601
}

// MARK: Church

struct AmbientChurch: Codable, Sendable {
    let upcomingEvents: [EventRef]
    let nextService: EventRef?
}

// MARK: Selah

struct AmbientSelah: Codable, Sendable {
    let streakDays: Int
    let resumeAt: SelahResumeRef?
}

struct SelahResumeRef: Codable, Sendable {
    let book: String
    let chapter: Int
    let deepLink: String
}

// MARK: Arise Broadcasts

struct AmbientArise: Codable, Sendable {
    let upcomingBroadcasts: [BroadcastRef]
}

struct BroadcastRef: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let deepLink: String
    let scheduledAt: String          // ISO 8601
}

// MARK: Berean Suggestion (advisory — never an auto-action)

struct AmbientBereanSuggestion: Codable, Sendable {
    let kind: BereanSuggestionKind
    let label: String
    let deepLink: String
}

enum BereanSuggestionKind: String, Codable, Sendable {
    case study
    case pray
    case reflect
}

// MARK: - §2.2 AmbientSummary

/// `summarizeAmbientContext` (callable, Anthropic proxy) produces this.
/// Same call drives BOTH the prose Home header and the Priority Actions timeline.
struct AmbientSummary: Codable, Sendable {
    let greetingProse: String        // "Good morning, Steph. You have 2 prayer requests…"
    let actions: [PriorityAction]    // ranked; see §2.3
}

// MARK: - §2.3 PriorityAction

/// Shared atom used by: Ambient Home, Priority Actions timeline,
/// notification-replacement surfaces.
struct PriorityAction: Codable, Sendable, Identifiable {
    let id: String
    let tier: ActionTier
    let title: String
    let source: ActionSource
    let deepLink: String
    /// Present → timeline slot; absent → "Unscheduled" bucket.
    let scheduledAt: String?         // ISO 8601
}

enum ActionTier: String, Codable, Sendable {
    case high
    case medium
    case low
}

enum ActionSource: String, Codable, Sendable {
    case prayer
    case note
    case message
    case church
    case selah
    case berean
}

// MARK: - §2.4 GlassToolRailItem

/// Reusable floating-action-rail component.
/// Renders as `.glassEffect` capsules over matte content.
/// Ship to: Scripture (Pray/Save/Ask Berean/Share),
///          Notes (Summarize/Task/Ask Berean),
///          Messages (Save/Translate/Reminder).
///
/// NOT Codable — this is a pure UI contract; closures are not serialisable.
struct GlassToolRailItem: Identifiable {
    let id: String
    let sfSymbol: String
    let label: String
    let action: () -> Void
    let isDestructive: Bool

    init(id: String,
         sfSymbol: String,
         label: String,
         isDestructive: Bool = false,
         action: @escaping () -> Void) {
        self.id = id
        self.sfSymbol = sfSymbol
        self.label = label
        self.isDestructive = isDestructive
        self.action = action
    }
}

// MARK: - §2.5 SmartComposerIntent

/// Berean Build classifies free text → offered attachment chips.
/// Advisory only — user taps to add. Server-side callable returns this.
struct SmartComposerIntent: Codable, Sendable {
    let chips: [ComposerChip]
    let postType: ComposerPostType?
}

enum ComposerChip: String, Codable, Sendable {
    case photo
    case churchNote
    case event
    case prayerRequest
    case sermon
    case scripture
}

enum ComposerPostType: String, Codable, Sendable {
    case prayerRequest = "PrayerRequest"
    case testimony     = "Testimony"
    case churchNote    = "ChurchNote"
}

// MARK: - Contract Validation (compile-time assertions)

// Ensure all *Ref types conform to Identifiable & Codable at compile time.
private func _contractAssertions() {
    let _: any (Identifiable & Codable) = PrayerRef(id: "", title: "", deepLink: "", createdAt: "")
    let _: any (Identifiable & Codable) = NoteRef(id: "", title: "", deepLink: "", editedAt: "")
    let _: any (Identifiable & Codable) = ThreadRef(id: "", title: "", deepLink: "", lastMessageAt: "")
    let _: any (Identifiable & Codable) = EventRef(id: "", title: "", deepLink: "", startsAt: "", endsAt: nil)
    let _: any (Identifiable & Codable) = BroadcastRef(id: "", title: "", deepLink: "", scheduledAt: "")
    let _: any (Identifiable & Codable) = PriorityAction(id: "", tier: .high, title: "", source: .prayer, deepLink: "", scheduledAt: nil)
}
