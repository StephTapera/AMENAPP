//
//  SelahHandoff.swift
//  AMENAPP
//
//  NSUserActivity-based Handoff for the Selah Scripture Reader. When the
//  user is reading on iPhone, the same passage advertised via Handoff
//  becomes resumable on iPad or Mac (and on visionOS once that target ships).
//
//  Setup checklist for the team — must be done in the app target settings:
//   1. Add `NSUserActivityTypes` to Info.plist as an array containing
//      `app.amen.selah.read.scripture`.
//   2. Confirm the app target's "Handoff" capability is enabled.
//   3. The receiving side reads `userActivity.userInfo` keys defined below
//      and constructs the reader on launch.
//
//  This file is the code side — it can be wired today without Info.plist
//  changes, but Handoff itself only activates when the activity type is
//  declared in Info.plist.
//

import Foundation
import SwiftUI

enum SelahHandoff {
    /// Activity type advertised when the reader is on screen.
    static let readScriptureActivityType = "app.amen.selah.read.scripture"

    /// User-info keys for resuming on another device.
    enum Keys {
        static let bookId = "bookId"
        static let chapter = "chapter"
        static let verse = "verse"
        static let translationId = "translationId"
    }

    /// Build a fresh NSUserActivity advertising the user's current reading
    /// position. Caller (the reader view) attaches this via `.userActivity(...)`.
    static func makeReadingActivity(
        bookId: String,
        chapter: Int,
        verse: Int?,
        translationId: String,
        bookDisplayName: String
    ) -> NSUserActivity {
        let activity = NSUserActivity(activityType: readScriptureActivityType)
        activity.title = "Read \(bookDisplayName) \(chapter)"
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.requiredUserInfoKeys = [Keys.bookId, Keys.chapter, Keys.translationId]
        activity.addUserInfoEntries(from: [
            Keys.bookId: bookId,
            Keys.chapter: chapter,
            Keys.translationId: translationId,
            Keys.verse: verse ?? NSNull() as Any
        ])
        return activity
    }

    /// Decode a previously-advertised activity into a reference the reader
    /// can use to open the right page on resume.
    static func reference(from activity: NSUserActivity) -> (SelahScriptureReference, String)? {
        guard activity.activityType == readScriptureActivityType,
              let info = activity.userInfo,
              let bookId = info[Keys.bookId] as? String,
              let chapter = info[Keys.chapter] as? Int,
              let translationId = info[Keys.translationId] as? String
        else { return nil }
        let verse = info[Keys.verse] as? Int
        let ref = SelahScriptureReference(
            bookId: bookId,
            chapter: chapter,
            startVerse: verse,
            endVerse: nil
        )
        return (ref, translationId)
    }
}
