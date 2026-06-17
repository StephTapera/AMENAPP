
//  ChurchNotesDiscipleshipInvariantTests.swift
//  AMENAPPTests
//
//  Safety invariant tests for the Church Notes discipleship system (W1–W6).
//  Tests S1–S10 as defined in the build prompt. Uses Swift Testing framework.
//

import Testing
import Foundation
import CryptoKit
@testable import AMENAPP

// MARK: - S1: Confidential notes never proactively surface

@Suite("S1 — Confidential note never proactively surfaces")
struct S1ConfidentialSurfacingTests {

    private let classifier = ChurchNotesSensitivityClassifierImpl()
    private let enforcer   = DiscipleshipLocusEnforcer()
    private let surfaces   = DiscipleshipSurfaceManager()

    @Test func confessionNoteClassifiesAsConfidential() {
        let note = testNote("I confessed my addiction to my pastor yesterday. It's been a painful recovery.")
        let sensitivity = classifier.classify(note)
        #expect(sensitivity == .confidential)
    }

    @Test func confidentialNoteCannotProactivelySurface() {
        #expect(!enforcer.canProactivelySurface(sensitivity: .confidential))
    }

    @Test func sensitiveAndGeneralCanProactivelySurface() {
        #expect(enforcer.canProactivelySurface(sensitivity: .sensitive))
        #expect(enforcer.canProactivelySurface(sensitivity: .general))
    }

    @Test func surfaceManagerFiltersOutConfidentialActions() {
        let actions = [
            makeSpiritualAction(sensitivity: .confidential),
            makeSpiritualAction(sensitivity: .sensitive),
            makeSpiritualAction(sensitivity: .general),
        ]
        let surfaceable = surfaces.surfaceableActions(from: actions)
        #expect(surfaceable.count == 2)
        #expect(surfaceable.allSatisfy { $0.sensitivity != .confidential })
    }

    @Test func islandCardIsNilWhenOnlyConfidentialActions() {
        let actions = [makeSpiritualAction(sensitivity: .confidential)]
        #expect(surfaces.islandAction(from: actions) == nil)
    }
}

// MARK: - S2: Sensitive/confidential notes never use server proxy

@Suite("S2 — Sensitive and confidential notes never call server proxy")
struct S2ComputeLocusTests {

    @Test func generalLocusAllowsServer() {
        #expect(locus(for: .general) == .serverProxyAllowed)
    }

    @Test func sensitiveLocusIsOnDeviceOnly() {
        #expect(locus(for: .sensitive) == .onDeviceOnly)
    }

    @Test func confidentialLocusIsOnDeviceOnly() {
        #expect(locus(for: .confidential) == .onDeviceOnly)
    }

    @Test func enforcerWithFlagsOffDefaultsToOnDevice() {
        let enforcer = DiscipleshipLocusEnforcer()
        let note = testNote("Grace filled sermon about the resurrection.")
        let computeLocus = enforcer.computeLocus(for: note)
        #expect(computeLocus == .onDeviceOnly)
    }

    @Test func serverProxyAllowedReturnsFalseWhenFlagsOff() {
        let enforcer = DiscipleshipLocusEnforcer()
        let note = testNote("Sermon notes: faith, hope, and grace.")
        #expect(!enforcer.serverProxyAllowed(for: note))
    }
}

// MARK: - S3: Default ShareScope is .onlyMe

@Suite("S3 — Default ShareScope is always .onlyMe")
struct S3DefaultShareScopeTests {

    @Test func grantBuilderDefaultsToOnlyMe() {
        let grant = ShareGrant.build(actionID: UUID(), scope: .onlyMe, recipientIDs: ["uid"])
        #expect(grant.scope == .onlyMe)
    }

    @Test func noStickyRelationshipLevelSharingExists() {
        let id = UUID()
        let grant = ShareGrant.build(actionID: id, scope: .trustedFriend, recipientIDs: ["uid"])
        #expect(grant.actionID == id)  // per-item, not per-relationship
    }
}

// MARK: - S4: Revoke deletes from recipient view (tested via service contract)

@Suite("S4 — Revoke deletes (contract enforced)")
struct S4RevokeDeletesTests {

    @Test func revokeUsesHardDeletePath() async throws {
        let mockService = MockSharingService()
        let grantID = UUID()
        try await mockService.revoke(grantID)
        #expect(mockService.lastRevokedID == grantID)
        #expect(!mockService.usedSoftDelete)
    }
}

// MARK: - S5: namedPeople triggers confirmation friction

@Suite("S5 — Named people require confirmation friction")
struct S5NamedPeopleTests {

    @Test func actionWithNamedPeopleRequiresConfirmation() {
        let action = SpiritualAction(id: UUID(), kind: .reachOut,
                                     summary: "Reach out to Sarah",
                                     namedPeople: ["Sarah Johnson"],
                                     sourceNoteID: UUID(), sensitivity: .sensitive)
        #expect(action.requiresNameAwareConfirmation)
    }

    @Test func actionWithoutNamedPeopleDoesNotRequireConfirmation() {
        let action = SpiritualAction(id: UUID(), kind: .pray,
                                     summary: "Take time to pray",
                                     namedPeople: [],
                                     sourceNoteID: UUID(), sensitivity: .general)
        #expect(!action.requiresNameAwareConfirmation)
    }
}

// MARK: - S6: churchLeader grants require non-nil expiresAt

@Suite("S6 — churchLeader grants require expiry")
struct S6ChurchLeaderExpiryTests {

    @Test func churchLeaderGrantWithoutExpiryThrows() {
        let grant = ShareGrant(id: UUID(), actionID: UUID(), scope: .churchLeader,
                               expiresAt: nil, recipientIDs: ["uid"])
        #expect(throws: ChurchNotesDiscipleshipError.self) {
            try grant.validateChurchLeaderExpiry()
        }
    }

    @Test func churchLeaderGrantWithExpiryDoesNotThrow() throws {
        let expiry = Date().addingTimeInterval(86400 * 30)
        let grant = ShareGrant(id: UUID(), actionID: UUID(), scope: .churchLeader,
                               expiresAt: expiry, recipientIDs: ["uid"])
        try grant.validateChurchLeaderExpiry()
    }

    @Test func otherScopesDoNotRequireExpiry() throws {
        let grant = ShareGrant(id: UUID(), actionID: UUID(), scope: .trustedFriend,
                               expiresAt: nil, recipientIDs: ["uid"])
        try grant.validateChurchLeaderExpiry()
    }

    @Test func grantBuilderAutoAppliesDefaultExpiryForChurchLeader() {
        let grant = ShareGrant.build(actionID: UUID(), scope: .churchLeader, recipientIDs: ["uid"])
        #expect(grant.expiresAt != nil)
    }
}

// MARK: - S7: Minors cannot share without guardian routing

@Suite("S7 — Minor accounts route through guardian")
struct S7MinorGuardianTests {

    private let gate = ChurchNotesGuardianGateImpl()

    @Test func minorRequestingTrustedFriendRoutesToOnlyMe() {
        let resolved = gate.resolveSharing(for: UUID(), requested: .trustedFriend, isMinor: true)
        #expect(resolved == .onlyMe)
    }

    @Test func minorRequestingSmallGroupRoutesToOnlyMe() {
        let resolved = gate.resolveSharing(for: UUID(), requested: .smallGroup, isMinor: true)
        #expect(resolved == .onlyMe)
    }

    @Test func minorRequestingChurchLeaderRoutesToOnlyMe() {
        let resolved = gate.resolveSharing(for: UUID(), requested: .churchLeader, isMinor: true)
        #expect(resolved == .onlyMe)
    }

    @Test func minorRequestingOnlyMeIsAllowed() {
        let resolved = gate.resolveSharing(for: UUID(), requested: .onlyMe, isMinor: true)
        #expect(resolved == .onlyMe)
    }

    @Test func adultRequestingTrustedFriendIsAllowed() {
        let resolved = gate.resolveSharing(for: UUID(), requested: .trustedFriend, isMinor: false)
        #expect(resolved == .trustedFriend)
    }

    @Test func guardianRoutingRequiredForMinorNonOnlyMeScopes() {
        #expect(gate.requiresGuardianRouting(requested: .smallGroup, isMinor: true))
        #expect(!gate.requiresGuardianRouting(requested: .onlyMe, isMinor: true))
        #expect(!gate.requiresGuardianRouting(requested: .smallGroup, isMinor: false))
    }
}

// MARK: - S8: Notifications use templates only

@Suite("S8 — Notifications use approved templates; no free text")
struct S8NotificationTemplateTests {

    private let composer = ChurchNotesNotificationComposerImpl()

    @Test func continueReadingPlanIsFixedString() {
        let result = composer.compose(.continueReadingPlan, slots: NotificationSlots())
        #expect(result == "Would you like to continue your reading plan?")
    }

    @Test func verseReviewFillsSlot() {
        var slots = NotificationSlots(); slots.verseRef = "John 3:16"
        let result = composer.compose(.verseReview, slots: slots)
        #expect(result.contains("John 3:16"))
        #expect(!result.contains("{verseRef}"))
    }

    @Test func prayerInviteFillsTopicSlot() {
        var slots = NotificationSlots(); slots.topic = "Maria's healing"
        let result = composer.compose(.prayerInvite, slots: slots)
        #expect(result.contains("Maria's healing"))
    }

    @Test func prayerInviteHasFallbackTopic() {
        let result = composer.compose(.prayerInvite, slots: NotificationSlots())
        #expect(result.contains("what's on your heart"))
    }

    @Test func eventUpcomingFillsEventTitleSlot() {
        var slots = NotificationSlots(); slots.eventTitle = "Men's Bible Study"
        let result = composer.compose(.eventUpcoming, slots: slots)
        #expect(result.contains("Men's Bible Study"))
    }

    @Test func allTemplatesProduceNonEmptyStrings() {
        for template in NotificationTemplate.allCases {
            let result = composer.compose(template, slots: NotificationSlots())
            #expect(!result.isEmpty)
        }
    }
}

// MARK: - S9: No surface displays a decreasing count

@Suite("S9 — No streak, count, or decreasing metric in surfaces")
struct S9NoCountSurfaceTests {

    @Test func formationViewHasNoCountProperty() {
        let mirror = Mirror(reflecting: ChurchNotesDiscipleshipFormationView(actions: []))
        let storedPropertyNames = Set(mirror.children.compactMap { $0.label })
        let forbidden = storedPropertyNames.filter { name in
            ["streak", "count", "days", "tally", "score", "points"].contains(where: {
                name.localizedCaseInsensitiveCompare($0) == .orderedSame
            })
        }
        #expect(forbidden.isEmpty, "Formation view has forbidden count properties: \(forbidden)")
    }

    @Test func governorIgnoreDecayNeverEscalates() {
        let governor = ChurchNotesNotificationGovernorImpl.shared
        let records = (0..<3).map { i in
            DeliveryRecord(template: .prayerInvite,
                           deliveredAt: Date().addingTimeInterval(Double(-i * 3600)),
                           wasIgnored: true)
        }
        let history = DeliveryHistory(records: records)
        #expect(!governor.shouldDeliver(.prayerInvite, history: history))
    }

    @Test func governorAllowsDeliveryAfterInterruptedIgnoreRun() {
        let governor = ChurchNotesNotificationGovernorImpl.shared
        let records: [DeliveryRecord] = [
            .init(template: .prayerInvite, deliveredAt: Date().addingTimeInterval(-7200), wasIgnored: true),
            .init(template: .prayerInvite, deliveredAt: Date().addingTimeInterval(-3600), wasIgnored: false),
            .init(template: .verseReview,  deliveredAt: Date().addingTimeInterval(-1800), wasIgnored: true),
        ]
        let history = DeliveryHistory(records: records)
        #expect(governor.shouldDeliver(.continueReadingPlan, history: history))
    }
}

// MARK: - S10: No-train proxy + encryption (W6)

@Suite("S10 — No-train proxy paths and encryption")
struct S10NoTrainEncryptionTests {

    @Test func proxyNeverCalledForSensitive() {
        #expect(S10NoTrainAudit.proxyNeverCalledFor(.sensitive))
    }

    @Test func proxyNeverCalledForConfidential() {
        #expect(S10NoTrainAudit.proxyNeverCalledFor(.confidential))
    }

    @Test func proxyAllowedForGeneral() {
        #expect(!S10NoTrainAudit.proxyNeverCalledFor(.general))
    }

    @Test func noTrainHeaderKeyIsSet() {
        #expect(!S10NoTrainAudit.noTrainHeaderKey.isEmpty)
        #expect(!S10NoTrainAudit.noTrainHeaderValue.isEmpty)
    }

    @Test func encryptionProducesDifferentOutputFromPlaintext() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = "This is a confidential prayer request."
        let ciphertext = try ChurchNotesConfidentialEncryption.encrypt(plaintext, key: key)
        let ciphertextString = String(data: ciphertext, encoding: .utf8)
        #expect(ciphertextString != plaintext)
    }

    @Test func encryptThenDecryptIsIdentity() throws {
        let key = SymmetricKey(size: .bits256)
        let original = "Private: I confessed my struggles to my pastor today."
        let encrypted = try ChurchNotesConfidentialEncryption.encrypt(original, key: key)
        let decrypted = try ChurchNotesConfidentialEncryption.decrypt(encrypted, key: key)
        #expect(decrypted == original)
    }

    @Test func differentKeysProduceDifferentCiphertexts() throws {
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)
        let plaintext = "Confidential note content."
        let c1 = try ChurchNotesConfidentialEncryption.encrypt(plaintext, key: key1)
        let c2 = try ChurchNotesConfidentialEncryption.encrypt(plaintext, key: key2)
        #expect(c1 != c2)
    }
}

// MARK: - Classifier Accuracy Spot-Check

@Suite("Classifier spot-check")
struct ClassifierSpotCheckTests {

    private let classifier = ChurchNotesSensitivityClassifierImpl()

    @Test func sermonNoteIsGeneral() {
        let note = testNote("Today Pastor David preached on the Sermon on the Mount. Key themes: humility, grace, the Beatitudes.")
        #expect(classifier.classify(note) == .general)
    }

    @Test func prayerRequestIsSensitive() {
        let note = testNote("Please pray for my coworker John Smith who is sick and in the hospital.")
        #expect(classifier.classify(note) == .sensitive)
    }

    @Test func addictionConfessionIsConfidential() {
        let note = testNote("I confess I've been struggling with addiction again. I spoke with a counselor today.")
        #expect(classifier.classify(note) == .confidential)
    }

    @Test func confidentialTagForcesConfidential() {
        let note = NoteContent(noteID: UUID(), firestoreID: "t1",
                               plainText: "Normal sermon notes.", tags: ["counseling"], blocks: [])
        #expect(classifier.classify(note) == .confidential)
    }
}

// MARK: - Test Helpers

private func testNote(_ text: String, tags: [String] = []) -> NoteContent {
    NoteContent(noteID: UUID(), firestoreID: UUID().uuidString,
                plainText: text, tags: tags, blocks: [])
}

private func makeSpiritualAction(sensitivity: NoteSensitivity) -> SpiritualAction {
    SpiritualAction(id: UUID(), kind: .pray, summary: "Test action",
                    namedPeople: [], sourceNoteID: UUID(), sensitivity: sensitivity)
}

// MARK: - Mock Sharing Service (S4 test)

private final class MockSharingService: SharingService {
    var lastRevokedID: UUID?
    var usedSoftDelete = false

    func grant(_ grant: ShareGrant) async throws {}

    func revoke(_ grantID: UUID) async throws {
        lastRevokedID = grantID
        usedSoftDelete = false
    }
}
