#if canImport(Testing)
import Foundation
import Testing
@testable import AMENAPP

@Suite("Church Study Companion Bridge")
struct ChurchStudyCompanionBridgeTests {
    @Test("After-service reflection trims values and keeps note private")
    func afterServiceReflectionAppliesPrivateFields() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(ISO8601DateFormatter().date(from: "2026-05-17T12:00:00Z"))
        let note = ChurchNote(
            id: "note-1",
            userId: "user-1",
            title: "Sunday Notes",
            content: "Sermon notes",
            permission: .privateNote,
            sharedWith: [],
            scriptureReferences: ["John 3:16"]
        )

        let draft = AfterServiceReflectionDraft(
            stoodOut: "  Grace stood out  ",
            application: "  Call my small group leader  ",
            prayer: "  Pray for Maya  ",
            continueStudy: true
        )

        let updated = draft.applying(to: note, now: now, calendar: calendar)

        #expect(updated.permission == .privateNote)
        #expect(updated.sharedWith.isEmpty)
        #expect(updated.scriptureReferences == ["John 3:16"])
        #expect(updated.growthReflection == "Grace stood out")
        #expect(updated.actionStepThisWeek == "Call my small group leader")
        #expect(updated.prayerFromSermon == "Pray for Maya")
        #expect(updated.shouldRevisit)
        #expect(updated.revisitDate == calendar.date(byAdding: .day, value: 7, to: now))
    }

    @Test("Blank after-service reflection fields clear optional private fields")
    func blankReflectionFieldsClearPrivateFields() {
        let note = ChurchNote(
            id: "note-2",
            userId: "user-1",
            title: "Sunday Notes",
            content: "Sermon notes",
            permission: .privateNote,
            actionStepThisWeek: "Existing action",
            prayerFromSermon: "Existing prayer",
            shouldRevisit: true,
            growthReflection: "Existing reflection"
        )

        let draft = AfterServiceReflectionDraft(
            stoodOut: "   ",
            application: "\n",
            prayer: "\t",
            continueStudy: false
        )

        let updated = draft.applying(to: note)

        #expect(updated.permission == .privateNote)
        #expect(updated.growthReflection == nil)
        #expect(updated.actionStepThisWeek == nil)
        #expect(updated.prayerFromSermon == nil)
        #expect(!updated.shouldRevisit)
    }

    @Test("Public highlight posting is hidden by default behind group bridge flag")
    @MainActor
    func publicHighlightPostingDefaultsOff() {
        #expect(!ChurchStudyHighlightSharingPolicy.canPostPublicHighlight)
        #expect(ChurchStudyHighlightSharingPolicy.publicHighlightLabel.contains("publicly"))
    }

    @Test("Release feature flags default to completed bridges only")
    @MainActor
    func releaseFeatureFlagsDefaultToCompletedBridgesOnly() {
        let flags = AMENFeatureFlags.shared

        #expect(flags.churchStudyCompanionEnabled)
        #expect(flags.churchNotesScriptureBridgeEnabled)
        #expect(flags.selahAddToChurchNotesEnabled)
        #expect(flags.findChurchStudyActionsEnabled)
        #expect(flags.afterServiceReflectionEnabled)
        #expect(!flags.churchStudyGroupBridgeEnabled)
    }

    @Test("Church Study analytics events use approved names")
    func churchStudyAnalyticsEventsUseApprovedNames() {
        let eventNames = [
            AMENAnalyticsEvent.churchStudyCompanionOpened(source: "church_detail").name,
            AMENAnalyticsEvent.churchNotesStartedFromChurch.name,
            AMENAnalyticsEvent.scriptureAddedToChurchNote(source: "church_notes").name,
            AMENAnalyticsEvent.selahVerseAddedToChurchNotes.name,
            AMENAnalyticsEvent.churchStudySessionStarted(source: "selah").name,
            AMENAnalyticsEvent.afterServiceReflectionStarted.name,
            AMENAnalyticsEvent.afterServiceReflectionSaved.name,
            AMENAnalyticsEvent.prayerVisibilitySelected(visibility: "only_me").name,
            AMENAnalyticsEvent.bereanStudyActionStarted(action: "ask_later").name,
            AMENAnalyticsEvent.bereanStudyActionCompleted(action: "ask_later").name,
            AMENAnalyticsEvent.churchContextAttachedToNote.name
        ]

        #expect(eventNames == [
            "church_study_companion_opened",
            "church_notes_started_from_church",
            "scripture_added_to_church_note",
            "selah_verse_added_to_church_notes",
            "church_study_session_started",
            "after_service_reflection_started",
            "after_service_reflection_saved",
            "prayer_visibility_selected",
            "berean_study_action_started",
            "berean_study_action_completed",
            "church_context_attached_to_note"
        ])
    }

    @Test("Church Study analytics payloads never include private text fields")
    func churchStudyAnalyticsPayloadsNeverIncludePrivateTextFields() {
        let events: [AMENAnalyticsEvent] = [
            .churchStudyCompanionOpened(source: "church_detail"),
            .churchNotesStartedFromChurch,
            .scriptureAddedToChurchNote(source: "church_notes"),
            .selahVerseAddedToChurchNotes,
            .churchStudySessionStarted(source: "selah"),
            .afterServiceReflectionStarted,
            .afterServiceReflectionSaved,
            .prayerVisibilitySelected(visibility: "only_me"),
            .bereanStudyActionStarted(action: "ask_later"),
            .bereanStudyActionCompleted(action: "ask_later"),
            .churchContextAttachedToNote
        ]

        let disallowedKeys: Set<String> = [
            "body",
            "content",
            "note",
            "note_body",
            "prayer",
            "prayer_text",
            "reflection",
            "reflection_text",
            "scripture_text",
            "verse",
            "verse_text",
            "raw_prompt"
        ]
        let allowedKeys: Set<String> = ["source", "visibility", "action"]

        for event in events {
            let keys = Set(event.properties.keys)
            #expect(keys.isSubset(of: allowedKeys))
            #expect(keys.isDisjoint(with: disallowedKeys))
        }
    }
}
#endif
