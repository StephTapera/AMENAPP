//
//  AntiHarassmentEngineTests.swift
//  AMENAPPTests
//
//  Unit tests for AntiHarassmentEngine pure-Swift logic:
//  — Idempotency key construction
//  — Escalation rule thresholds (no Firebase required)
//  — Appeal reason validation
//  — RestrictionType doc ID format
//  — EnforcementRecord deserialization helpers
//
//  Tests that require Firestore are documented as manual integration checklists.
//

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Idempotency Key Construction

@Suite("AntiHarassmentEngine — Idempotency Keys")
struct EnforcementIdempotencyKeyTests {

    // Mirror the engine's idempotency key logic in pure Swift for unit testing.
    // AntiHarassmentEngine.recordEnforcement() builds the key as:
    //   contentId != nil  → "\(contentId)_\(violation.rawValue)_\(action.rawValue)"
    //   contentId == nil  → "\(userId)_\(violation.rawValue)_\(action.rawValue)_\(5min bucket)"

    private func keyWithContent(
        contentId: String,
        violation: PolicyViolation,
        action: EnforcementAction
    ) -> String {
        "\(contentId)_\(violation.rawValue)_\(action.rawValue)"
    }

    private func keyWithoutContent(
        userId: String,
        violation: PolicyViolation,
        action: EnforcementAction,
        atDate: Date = Date()
    ) -> String {
        let bucket = Int(atDate.timeIntervalSince1970 / 300)
        return "\(userId)_\(violation.rawValue)_\(action.rawValue)_\(bucket)"
    }

    @Test("Key with contentId is stable across two calls with same args")
    func keyWithContentIsStable() {
        let k1 = keyWithContent(contentId: "post_abc", violation: .harassment, action: .blockAndReview)
        let k2 = keyWithContent(contentId: "post_abc", violation: .harassment, action: .blockAndReview)
        #expect(k1 == k2, "Same inputs must produce the same idempotency key")
    }

    @Test("Key with contentId differs for different violations")
    func differentViolationProducesDifferentKey() {
        let k1 = keyWithContent(contentId: "post_abc", violation: .harassment, action: .blockAndReview)
        let k2 = keyWithContent(contentId: "post_abc", violation: .hateSpeech, action: .blockAndReview)
        #expect(k1 != k2)
    }

    @Test("Key with contentId differs for different actions")
    func differentActionProducesDifferentKey() {
        let k1 = keyWithContent(contentId: "post_abc", violation: .harassment, action: .blockAndReview)
        let k2 = keyWithContent(contentId: "post_abc", violation: .harassment, action: .restrictPosting)
        #expect(k1 != k2)
    }

    @Test("Key with contentId differs for different content IDs")
    func differentContentIdProducesDifferentKey() {
        let k1 = keyWithContent(contentId: "post_abc", violation: .harassment, action: .blockAndReview)
        let k2 = keyWithContent(contentId: "post_xyz", violation: .harassment, action: .blockAndReview)
        #expect(k1 != k2)
    }

    @Test("Key without contentId uses 5-minute bucket — same bucket within window")
    func noContentKeyIsStableWithinFiveMinuteBucket() {
        let now = Date()
        let k1 = keyWithoutContent(userId: "user1", violation: .harassment, action: .warnAndAllow, atDate: now)
        // A moment later in the same 5-minute window
        let k2 = keyWithoutContent(userId: "user1", violation: .harassment, action: .warnAndAllow,
                                    atDate: now.addingTimeInterval(10))
        #expect(k1 == k2, "Two calls within the same 5-min window must produce the same key")
    }

    @Test("Key without contentId differs across bucket boundaries")
    func noContentKeyDiffersAcrossBuckets() {
        let now = Date()
        let k1 = keyWithoutContent(userId: "user1", violation: .harassment, action: .warnAndAllow, atDate: now)
        // Jump to the next 5-minute bucket
        let k2 = keyWithoutContent(userId: "user1", violation: .harassment, action: .warnAndAllow,
                                    atDate: now.addingTimeInterval(300))
        #expect(k1 != k2, "Calls in different 5-min windows must produce different keys")
    }
}

// MARK: - Escalation Rule Thresholds

@Suite("AntiHarassmentEngine — Escalation Rule Logic")
struct EscalationRuleTests {

    // We test the raw threshold constants embedded in the escalation rules.
    // shouldEscalateEnforcement() requires Firestore; these tests verify the
    // threshold logic without Firebase using a pure-Swift reimplementation.

    // Escalation rules (mirrored from shouldEscalateEnforcement):
    //   Rule 1: criticalCount > 0  → escalate
    //   Rule 2: severeCount >= 2   → escalate
    //   Rule 3: moderateCount >= 5 → escalate
    //   Rule 4: targetedCount >= 3 → escalate (same target)

    enum Severity: String, Comparable {
        case low = "low", moderate = "moderate", severe = "severe", critical = "critical"
        static func < (lhs: Severity, rhs: Severity) -> Bool {
            let order: [Severity] = [.low, .moderate, .severe, .critical]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }

    private func shouldEscalate(
        criticalCount: Int,
        severeCount: Int,
        moderateCount: Int,
        targetedCount: Int = 0
    ) -> (escalate: Bool, reason: String) {
        if criticalCount > 0 {
            return (true, "User has prior critical violations")
        }
        if severeCount >= 2 {
            return (true, "User has \(severeCount) severe violations in 30 days")
        }
        if moderateCount >= 5 {
            return (true, "User has \(moderateCount) moderate violations in 30 days")
        }
        if targetedCount >= 3 {
            return (true, "User has targeted same person \(targetedCount) times")
        }
        return (false, "")
    }

    // ── Rule 1: Any critical ─────────────────────────────────────────────────

    @Test("One critical violation triggers escalation")
    func oneCriticalEscalates() {
        let result = shouldEscalate(criticalCount: 1, severeCount: 0, moderateCount: 0)
        #expect(result.escalate == true)
        #expect(result.reason.contains("critical"))
    }

    @Test("Zero critical violations do not trigger Rule 1")
    func zeroCriticalNoRule1() {
        let result = shouldEscalate(criticalCount: 0, severeCount: 0, moderateCount: 0)
        #expect(result.escalate == false)
    }

    // ── Rule 2: 2+ severe ────────────────────────────────────────────────────

    @Test("Two severe violations trigger escalation")
    func twoSevereEscalates() {
        let result = shouldEscalate(criticalCount: 0, severeCount: 2, moderateCount: 0)
        #expect(result.escalate == true)
        #expect(result.reason.contains("severe"))
    }

    @Test("One severe violation does not trigger escalation")
    func oneSevereNoEscalation() {
        let result = shouldEscalate(criticalCount: 0, severeCount: 1, moderateCount: 0)
        #expect(result.escalate == false)
    }

    @Test("Three severe violations trigger escalation (above threshold)")
    func threeSevereEscalates() {
        let result = shouldEscalate(criticalCount: 0, severeCount: 3, moderateCount: 0)
        #expect(result.escalate == true)
    }

    // ── Rule 3: 5+ moderate ──────────────────────────────────────────────────

    @Test("Five moderate violations trigger escalation")
    func fiveModerateEscalates() {
        let result = shouldEscalate(criticalCount: 0, severeCount: 0, moderateCount: 5)
        #expect(result.escalate == true)
        #expect(result.reason.contains("moderate"))
    }

    @Test("Four moderate violations do not trigger escalation")
    func fourModerateNoEscalation() {
        let result = shouldEscalate(criticalCount: 0, severeCount: 0, moderateCount: 4)
        #expect(result.escalate == false)
    }

    // ── Rule 4: Targeting same person ────────────────────────────────────────

    @Test("Three incidents targeting same person triggers escalation")
    func threeTargetedEscalates() {
        let result = shouldEscalate(criticalCount: 0, severeCount: 0, moderateCount: 0, targetedCount: 3)
        #expect(result.escalate == true)
    }

    @Test("Two incidents targeting same person do not trigger Rule 4")
    func twoTargetedNoEscalation() {
        let result = shouldEscalate(criticalCount: 0, severeCount: 0, moderateCount: 0, targetedCount: 2)
        #expect(result.escalate == false)
    }

    // ── Rule priority ordering ────────────────────────────────────────────────

    @Test("Critical rule takes priority over severe rule")
    func criticalPriority() {
        // If critical fires, reason must mention critical (not severe)
        let result = shouldEscalate(criticalCount: 1, severeCount: 3, moderateCount: 6)
        #expect(result.reason.contains("critical"),
                "Critical rule must fire first — takes priority over severe/moderate")
    }

    @Test("Severe rule takes priority over moderate rule")
    func severePriority() {
        let result = shouldEscalate(criticalCount: 0, severeCount: 2, moderateCount: 6)
        #expect(result.reason.contains("severe"),
                "Severe rule must fire before moderate rule")
    }
}

// MARK: - Appeal Reason Validation

@Suite("AntiHarassmentEngine — Appeal Reason Validation")
struct AppealReasonValidationTests {

    // Mirror the reason-length validation from submitAppeal():
    //   trimmedReason.count >= 10 && trimmedReason.count <= 1000

    private func isValidReason(_ reason: String) -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 10 && trimmed.count <= 1000
    }

    @Test("Reason of exactly 10 characters is valid")
    func exactMinimumLength() {
        #expect(isValidReason("1234567890"))
    }

    @Test("Reason of exactly 1000 characters is valid")
    func exactMaximumLength() {
        let reason = String(repeating: "a", count: 1000)
        #expect(isValidReason(reason))
    }

    @Test("Reason of 9 characters is invalid")
    func belowMinimumLength() {
        #expect(!isValidReason("123456789"),
                "Reason of 9 characters must be rejected — too short for meaningful appeal")
    }

    @Test("Reason of 1001 characters is invalid")
    func aboveMaximumLength() {
        let reason = String(repeating: "a", count: 1001)
        #expect(!isValidReason(reason),
                "Reason of 1001 characters must be rejected — exceeds max length")
    }

    @Test("Empty string is invalid")
    func emptyReasonInvalid() {
        #expect(!isValidReason(""))
    }

    @Test("Whitespace-only string is invalid after trimming")
    func whitespaceOnlyInvalid() {
        #expect(!isValidReason("           "))
    }

    @Test("Reason with leading/trailing whitespace is valid if core is long enough")
    func whitespaceTrimmingWorks() {
        let reason = "  " + String(repeating: "x", count: 10) + "  "
        #expect(isValidReason(reason), "Trimming should yield a valid 10-char reason")
    }

    @Test("Reason of 500 characters is valid (within bounds)")
    func midRangeLengthValid() {
        let reason = String(repeating: "a", count: 500)
        #expect(isValidReason(reason))
    }
}

// MARK: - Restriction Doc ID Format

@Suite("AntiHarassmentEngine — Restriction Document IDs")
struct RestrictionDocIDTests {

    // Mirror the doc ID logic from applyRestriction():
    //   noContact → "\(userId)_no_contact_\(targetUserId ?? "all")"
    //   other     → "\(userId)_\(type.rawValue)"

    private func docId(
        userId: String,
        type: AntiHarassmentEngine.RestrictionType,
        targetUserId: String? = nil
    ) -> String {
        type == .noContact
            ? "\(userId)_no_contact_\(targetUserId ?? "all")"
            : "\(userId)_\(type.rawValue)"
    }

    @Test("Commenting restriction doc ID has correct format")
    func commentingDocId() {
        let id = docId(userId: "user1", type: .commenting)
        #expect(id == "user1_commenting")
    }

    @Test("Posting restriction doc ID has correct format")
    func postingDocId() {
        let id = docId(userId: "user1", type: .posting)
        #expect(id == "user1_posting")
    }

    @Test("Messaging restriction doc ID has correct format")
    func messagingDocId() {
        let id = docId(userId: "user1", type: .messaging)
        #expect(id == "user1_messaging")
    }

    @Test("No-contact restriction with target has correct format")
    func noContactWithTarget() {
        let id = docId(userId: "user1", type: .noContact, targetUserId: "user2")
        #expect(id == "user1_no_contact_user2")
    }

    @Test("No-contact restriction without target uses 'all'")
    func noContactWithoutTarget() {
        let id = docId(userId: "user1", type: .noContact)
        #expect(id == "user1_no_contact_all")
    }

    @Test("Two users get different doc IDs for same restriction type")
    func differentUsersHaveDifferentDocIDs() {
        let id1 = docId(userId: "userA", type: .posting)
        let id2 = docId(userId: "userB", type: .posting)
        #expect(id1 != id2)
    }

    @Test("DMFreeze restriction doc ID uses raw value 'dm_freeze'")
    func dmFreezeRawValue() {
        #expect(AntiHarassmentEngine.RestrictionType.dmFreeze.rawValue == "dm_freeze")
        let id = docId(userId: "user1", type: .dmFreeze)
        #expect(id == "user1_dm_freeze")
    }
}

// MARK: - EnforcementSource and ContentSurface Raw Values

@Suite("AntiHarassmentEngine — Codable Raw Values")
struct EnforcementCodableRawValueTests {

    // Verify raw values are stable — changing them would corrupt Firestore documents.

    @Test("EnforcementSource raw values are stable")
    func enforcementSourceRawValues() {
        #expect(AntiHarassmentEngine.EnforcementSource.ai.rawValue == "ai")
        #expect(AntiHarassmentEngine.EnforcementSource.keywords.rawValue == "keywords")
        #expect(AntiHarassmentEngine.EnforcementSource.userReport.rawValue == "user_report")
        #expect(AntiHarassmentEngine.EnforcementSource.moderator.rawValue == "moderator")
        #expect(AntiHarassmentEngine.EnforcementSource.hybrid.rawValue == "hybrid")
        #expect(AntiHarassmentEngine.EnforcementSource.pattern.rawValue == "pattern")
    }

    @Test("ContentSurface raw values are stable")
    func contentSurfaceRawValues() {
        #expect(AntiHarassmentEngine.ContentSurface.post.rawValue == "post")
        #expect(AntiHarassmentEngine.ContentSurface.comment.rawValue == "comment")
        #expect(AntiHarassmentEngine.ContentSurface.dm.rawValue == "dm")
        #expect(AntiHarassmentEngine.ContentSurface.prayerRequest.rawValue == "prayer_request")
        #expect(AntiHarassmentEngine.ContentSurface.churchNote.rawValue == "church_note")
    }

    @Test("RestrictionType raw values are stable")
    func restrictionTypeRawValues() {
        #expect(AntiHarassmentEngine.RestrictionType.commenting.rawValue == "commenting")
        #expect(AntiHarassmentEngine.RestrictionType.posting.rawValue == "posting")
        #expect(AntiHarassmentEngine.RestrictionType.messaging.rawValue == "messaging")
        #expect(AntiHarassmentEngine.RestrictionType.noContact.rawValue == "no_contact")
        #expect(AntiHarassmentEngine.RestrictionType.replyOnly.rawValue == "reply_only")
        #expect(AntiHarassmentEngine.RestrictionType.dmFreeze.rawValue == "dm_freeze")
        #expect(AntiHarassmentEngine.RestrictionType.frictionPrompt.rawValue == "friction_prompt")
    }

    @Test("Current policy version has expected date format")
    func policyVersionFormat() {
        let version = AntiHarassmentEngine.currentPolicyVersion
        // Expected format: "YYYY-MM-DD"
        #expect(version.count == 10, "Policy version must be in YYYY-MM-DD format")
        let components = version.split(separator: "-")
        #expect(components.count == 3, "Must have year, month, day components")
        #expect(components[0].count == 4, "Year must be 4 digits")
        #expect(components[1].count == 2, "Month must be 2 digits")
        #expect(components[2].count == 2, "Day must be 2 digits")
    }
}

// MARK: - Severity Trend Detection

@Suite("AntiHarassmentEngine — Severity Escalation Trend")
struct SeverityTrendTests {

    // Mirror Rule 5 logic from shouldEscalateEnforcement():
    //   recentHistory.prefix(5) sorted descending by timestamp
    //   severityTrend = map { $0.violation.severity.rawValue }
    //   isEscalating = zip(trend, trend.dropFirst()).allSatisfy { $0 <= $1 }

    // We test the allSatisfy(<=) pattern that detects non-decreasing severity.

    private func isEscalatingSeverityTrend(_ values: [Int]) -> Bool {
        guard values.count >= 3 else { return false }
        return zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
    }

    @Test("Strictly increasing severity trend triggers Rule 5")
    func increasingTrendEscalates() {
        #expect(isEscalatingSeverityTrend([1, 2, 3]))
    }

    @Test("Non-decreasing trend (with equal severity) triggers Rule 5")
    func flatThenIncreaseTriggers() {
        #expect(isEscalatingSeverityTrend([1, 1, 2]))
    }

    @Test("Flat (all same severity) trend triggers Rule 5 by allSatisfy(<=)")
    func flatTrendAlsoTriggers() {
        // Note: all-equal satisfies <= so this is the current engine behavior.
        #expect(isEscalatingSeverityTrend([2, 2, 2]))
    }

    @Test("Decreasing trend does NOT trigger Rule 5")
    func decreasingTrendNoEscalation() {
        #expect(!isEscalatingSeverityTrend([3, 2, 1]))
    }

    @Test("Two entries are not enough to trigger Rule 5 (needs >= 3)")
    func twoEntriesInsufficient() {
        #expect(!isEscalatingSeverityTrend([1, 2]))
    }

    @Test("Empty array does not trigger Rule 5")
    func emptyArrayNoTrigger() {
        #expect(!isEscalatingSeverityTrend([]))
    }
}

// MARK: - Manual Integration Checklists

// The following tests document what manual/integration tests MUST verify.
// They cannot be automated here because they require Firebase Auth + Firestore.

struct AntiHarassmentIntegrationChecklist {

    // 1. UNAUTHENTICATED recordEnforcement IS REJECTED
    //    Steps: Call recordEnforcement() with no signed-in user
    //    Expected: Throws NSError with code 401 (domain: AntiHarassmentEngine)
    //    Pass criterion: No Firestore write occurs; error propagates to caller
    //
    // 2. DUPLICATE SUPPRESSION WITHIN 5 MIN WINDOW
    //    Steps: Call recordEnforcement() twice with the same contentId + violation + action
    //           within 5 minutes
    //    Expected: First call creates Firestore document; second call is suppressed
    //    Pass criterion: Only one document exists in enforcementHistory with the given
    //                   idempotency key
    //
    // 3. CROSS-USER HISTORY READ IS REJECTED
    //    Steps: Sign in as userA; call getEnforcementHistory(userId: userB_id)
    //    Expected: Throws NSError with code 403
    //    Pass criterion: No Firestore query is made for userB's data
    //
    // 4. APPEAL RATE LIMIT — ONE PER ENFORCEMENT RECORD
    //    Steps: Submit an appeal for enforcementId X; try to submit a second appeal for X
    //    Expected: Second submitAppeal() throws NSError with code 409
    //    Pass criterion: Only one appeal document exists for enforcementId X
    //
    // 5. enableUserProtection IDEMPOTENCY — NEVER SHORTENS EXPIRY
    //    Steps: Enable protection for 7 days; then call enableUserProtection for 3 days
    //    Expected: Firestore document retains the original 7-day expiry
    //    Pass criterion: enhancedProtectionExpiresAt unchanged after second call
    //
    // 6. applyRestriction IDEMPOTENCY — NEVER SHORTENS EXISTING RESTRICTION
    //    Steps: Apply posting restriction for 24 hours; then call applyRestriction for 12 hours
    //    Expected: endDate in Firestore is unchanged (still 24h from first call)
    //    Pass criterion: Restriction not shortened by subsequent shorter-duration call
}
