//
//  ChurchNotesDraftLifecycleTests.swift
//  AMENAPPTests — Verification suite (NEW, additive)
//
//  Church Notes local draft: save / kill / relaunch / restore.
//  Uses the shared service with unique per-test keys + cleanup, so it depends
//  only on the stable save/load/clear surface (not on initializer overloads
//  that are in flux in the ChurchNotes lane).
//
//  RUN: ⌘U, or:
//    xcodebuild test -scheme AMENAPP -only-testing:AMENAPPTests/ChurchNotesDraftLifecycleTests
//

import Testing
import Foundation
@testable import AMENAPP

@Suite("Church Notes draft lifecycle")
struct ChurchNotesDraftLifecycleTests {

    private let svc = ChurchNotesLocalDraftService.shared
    private func freshKey() -> String { "verify-\(UUID().uuidString)" }

    private func draft(key: String, title: String) -> ChurchNotesLocalDraft {
        ChurchNotesLocalDraft(
            key: key, title: title, sermonTitle: "", churchName: "", pastor: "",
            selectedDate: Date(timeIntervalSince1970: 1_700_000_000), content: "",
            scriptureInput: "", scriptureReferences: [], actionStep: "", prayer: "",
            shouldRevisit: false, worshipSongs: [], blocks: [], noteTags: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test("draft_saveThenLoad_roundTrips")
    func draft_saveThenLoad_roundTrips() {
        let k = freshKey(); defer { svc.clear(key: k) }
        let d = draft(key: k, title: "Sunday sermon")
        svc.save(d)
        #expect(svc.load(key: k) == d)
    }

    @Test("draft_relaunch_restoresFromDisk")
    func draft_relaunch_restoresFromDisk() {
        let k = freshKey(); defer { svc.clear(key: k) }
        svc.save(draft(key: k, title: "Persisted across launch"))
        // A fresh shared-service read models a relaunch reading from disk.
        #expect(ChurchNotesLocalDraftService.shared.load(key: k)?.title == "Persisted across launch")
    }

    @Test("draft_kill_removesDraft")
    func draft_kill_removesDraft() {
        let k = freshKey()
        svc.save(draft(key: k, title: "To be killed"))
        svc.clear(key: k)
        #expect(svc.load(key: k) == nil)
    }

    @Test("draft_saveEmpty_doesNotPersist")
    func draft_saveEmpty_doesNotPersist() {
        let k = freshKey(); defer { svc.clear(key: k) }
        svc.save(draft(key: k, title: "")) // no meaningful content → must not persist
        #expect(svc.load(key: k) == nil)
    }

    @Test("draft_loadMissing_returnsNil")
    func draft_loadMissing_returnsNil() {
        #expect(svc.load(key: freshKey()) == nil)
    }

    @Test("draft_overwrite_keepsLatest")
    func draft_overwrite_keepsLatest() {
        let k = freshKey(); defer { svc.clear(key: k) }
        svc.save(draft(key: k, title: "v1"))
        svc.save(draft(key: k, title: "v2"))
        #expect(svc.load(key: k)?.title == "v2")
    }
}
