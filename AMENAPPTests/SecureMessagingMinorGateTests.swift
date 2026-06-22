import Testing
@testable import AMENAPP

/// GAP BOARD P0-4 — the iOS DM minor-gate must use the real ageTier vocabulary.
///
/// Before the fix, AMENSecureMessagingService blocked only the strings
/// 'under_minimum' / 'minor', neither of which the age system ever emits
/// (real vocab: blocked / tierB / tierC / tierD). The gate was dead, so an
/// under-13 'blocked' account could initiate DMs client-side. These tests pin
/// the gate to each real tier string.
@MainActor
@Suite("Secure messaging — COPPA DM gate (P0-4)")
struct SecureMessagingMinorGateTests {

    @Test("under-13 'blocked' tier is barred from initiating DMs")
    func blockedTierIsBarred() {
        #expect(AMENSecureMessagingService.isDMBlockedTier("blocked") == true)
    }

    @Test("13–17 minors (tierB/tierC) are permitted client-side; server enforces minor-safe DM")
    func minorTiersPermittedClientSide() {
        #expect(AMENSecureMessagingService.isDMBlockedTier("tierB") == false)
        #expect(AMENSecureMessagingService.isDMBlockedTier("tierC") == false)
    }

    @Test("adults (tierD) and empty/unknown claims are not barred")
    func adultAndUnknownNotBarred() {
        #expect(AMENSecureMessagingService.isDMBlockedTier("tierD") == false)
        #expect(AMENSecureMessagingService.isDMBlockedTier("") == false)
        #expect(AMENSecureMessagingService.isDMBlockedTier("garbage") == false)
    }

    @Test("legacy claim strings still fail closed")
    func legacyStringsFailClosed() {
        #expect(AMENSecureMessagingService.isDMBlockedTier("under_minimum") == true)
        #expect(AMENSecureMessagingService.isDMBlockedTier("minor") == true)
    }
}
