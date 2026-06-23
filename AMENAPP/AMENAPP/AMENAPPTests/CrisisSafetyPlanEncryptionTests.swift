import Testing
import Foundation
@testable import AMENAPP

// CrisisSafetyPlanEncryptionTests — G-2 / red line `crisis_data_unencrypted`.
//
// Asserts the crisis safety plan is encrypted AT REST and that no plaintext
// copy survives on disk. Covers the cipher round-trip, tamper rejection,
// encrypted persistence, and the one-time plaintext→ciphertext migration.
//
// NOTE: this is a NEW file — it must be added to the AMENAPPTests target
// membership before it will compile/run (synced-folder caveat). The cipher
// uses the iOS Keychain, so these run under a test HOST app (Keychain is not
// available to host-less unit bundles). Build is HUMAN-PENDING.

struct CrisisSafetyPlanEncryptionTests {

    // ── Cipher: round-trip ──────────────────────────────────────────────────

    @Test func cipherRoundTripsData() throws {
        let secret = "warning sign: isolation; trusted: Mom 555-0100".data(using: .utf8)!
        let sealed = try CrisisSafetyPlanCipher.encrypt(secret)
        // Ciphertext must not equal plaintext.
        #expect(sealed != secret)
        let opened = try CrisisSafetyPlanCipher.decrypt(sealed)
        #expect(opened == secret)
    }

    // ── Cipher: tampering is rejected (AES-GCM auth tag) ────────────────────

    @Test func cipherRejectsTamperedBlob() throws {
        let secret = "coping: call sponsor".data(using: .utf8)!
        var sealed = try CrisisSafetyPlanCipher.encrypt(secret)
        sealed[sealed.count - 1] ^= 0xFF  // flip a bit in the tag
        #expect(throws: (any Error).self) {
            _ = try CrisisSafetyPlanCipher.decrypt(sealed)
        }
    }

    // ── Store: persists ciphertext, never plaintext ─────────────────────────

    @MainActor
    @Test func storePersistsEncryptedAndNeverPlaintext() throws {
        let suite = "test.safetyPlan.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SafetyPlanStore(defaults: defaults)
        store.plan.trustedPeopleToCall = [TrustedPerson(name: "Pastor", phone: "555-0150")]

        // The write is encrypted...
        #expect(store.isPersistedEncrypted == true)
        // ...no legacy plaintext key exists...
        #expect(defaults.data(forKey: "amen.safetyPlan") == nil)
        // ...and the on-disk blob does NOT decode as a SafetyPlan (i.e. not plaintext JSON).
        let blob = try #require(defaults.data(forKey: "amen.safetyPlan.enc"))
        #expect((try? JSONDecoder().decode(SafetyPlan.self, from: blob)) == nil)
        // It DOES decrypt back to the saved content.
        let clear = try CrisisSafetyPlanCipher.decrypt(blob)
        let decoded = try JSONDecoder().decode(SafetyPlan.self, from: clear)
        #expect(decoded.trustedPeopleToCall.first?.phone == "555-0150")
    }

    // ── Store: migrates a legacy plaintext plan, then removes it ────────────

    @MainActor
    @Test func storeMigratesLegacyPlaintextAndStripsIt() throws {
        let suite = "test.safetyPlan.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // Seed an older-build PLAINTEXT plan.
        var legacy = SafetyPlan()
        legacy.warningSignsINotice = ["can't sleep"]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "amen.safetyPlan")

        let store = SafetyPlanStore(defaults: defaults)

        // Loaded the legacy content...
        #expect(store.plan.warningSignsINotice == ["can't sleep"])
        // ...stripped the plaintext copy...
        #expect(defaults.data(forKey: "amen.safetyPlan") == nil)
        // ...and re-persisted encrypted.
        #expect(store.isPersistedEncrypted == true)
        #expect(defaults.data(forKey: "amen.safetyPlan.enc") != nil)
    }
}
