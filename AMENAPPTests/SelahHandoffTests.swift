// SelahHandoffTests.swift
// AMENAPPTests
//
// Round-trip + decoding contract for the NSUserActivity-based handoff
// helper. These guarantee that the activity advertised by the iPhone is
// resumable on the iPad/Mac side without ambiguity.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@MainActor
@Suite("SelahHandoff")
struct SelahHandoffTests {

    @Test("makeReadingActivity is eligible for Handoff and Search")
    func activityIsEligible() {
        let activity = SelahHandoff.makeReadingActivity(
            bookId: "romans", chapter: 8, verse: 28,
            translationId: "kjv", bookDisplayName: "Romans"
        )
        #expect(activity.isEligibleForHandoff)
        #expect(activity.isEligibleForSearch)
        #expect(activity.isEligibleForPrediction)
    }

    @Test("Activity title contains the book and chapter")
    func activityTitle() {
        let activity = SelahHandoff.makeReadingActivity(
            bookId: "psalms", chapter: 23, verse: nil,
            translationId: "kjv", bookDisplayName: "Psalms"
        )
        let title = activity.title ?? ""
        #expect(title.contains("Psalms"))
        #expect(title.contains("23"))
    }

    @Test("Round-trip restores the reference and translation")
    func roundTrip() {
        let activity = SelahHandoff.makeReadingActivity(
            bookId: "john", chapter: 3, verse: 16,
            translationId: "kjv", bookDisplayName: "John"
        )
        let decoded = SelahHandoff.reference(from: activity)
        #expect(decoded?.0.bookId == "john")
        #expect(decoded?.0.chapter == 3)
        #expect(decoded?.0.startVerse == 16)
        #expect(decoded?.1 == "kjv")
    }

    @Test("Missing required keys decode to nil")
    func decodeRequiresKeys() {
        let bad = NSUserActivity(activityType: SelahHandoff.readScriptureActivityType)
        // No userInfo at all
        #expect(SelahHandoff.reference(from: bad) == nil)
    }

    @Test("Activity with a different activity type decodes to nil")
    func decodeWrongTypeReturnsNil() {
        let other = NSUserActivity(activityType: "some.other.type")
        other.addUserInfoEntries(from: [
            SelahHandoff.Keys.bookId: "romans",
            SelahHandoff.Keys.chapter: 5,
            SelahHandoff.Keys.translationId: "kjv"
        ])
        #expect(SelahHandoff.reference(from: other) == nil)
    }

    @Test("Whole-chapter activity (no verse) round-trips with nil startVerse")
    func roundTripWholeChapter() {
        let activity = SelahHandoff.makeReadingActivity(
            bookId: "matthew", chapter: 5, verse: nil,
            translationId: "kjv", bookDisplayName: "Matthew"
        )
        let decoded = SelahHandoff.reference(from: activity)
        #expect(decoded?.0.bookId == "matthew")
        #expect(decoded?.0.chapter == 5)
        #expect(decoded?.0.startVerse == nil)
    }
}

#endif
