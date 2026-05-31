// AegisPrivacyModeService.swift — C40–C43 Privacy Modes
// Capabilities: familyPrivacyMode, churchSafetyMode, minorProtectionMode, highRiskRegionMode

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class AegisPrivacyModeService: ObservableObject {

    static let shared = AegisPrivacyModeService()

    @Published var activeMode: AegisCapability? = nil   // C40/C41/C42/C43 or nil
    @Published var modeConfigs: [AegisPrivacyModeConfig] = []

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private init() {
        // Seed configs for all four privacy mode capabilities
        modeConfigs = [
            AegisPrivacyModeConfig(capability: .familyPrivacyMode,  isActive: false, rules: Self.rulesFor(.familyPrivacyMode)),
            AegisPrivacyModeConfig(capability: .churchSafetyMode,   isActive: false, rules: Self.rulesFor(.churchSafetyMode)),
            AegisPrivacyModeConfig(capability: .minorProtectionMode, isActive: false, rules: Self.rulesFor(.minorProtectionMode)),
            AegisPrivacyModeConfig(capability: .highRiskRegionMode,  isActive: false, rules: Self.rulesFor(.highRiskRegionMode)),
        ]
        Task { await loadUserMode() }
    }

    // MARK: - Activate

    func activateMode(_ mode: AegisCapability) async {
        guard mode.lane == .privacyModes else { return }
        guard AegisFeatureFlags.shared.isEnabled(mode) else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            try await db
                .collection("aegisProfiles")
                .document(uid)
                .setData(["activeMode": mode.rawValue, "updatedAt": FieldValue.serverTimestamp()], merge: true)

            activeMode = mode
            updateConfigActiveStates(activeMode: mode)

            // Fan-out mode application via callable so server-side rules are enforced
            let payload: [String: Any] = [
                "userId": uid,
                "action": AegisPrivacyActionRequest.AegisPrivacyActionType.applyMode.rawValue,
                "modeId": mode.rawValue,
                "targetPaths": [],
            ]
            _ = try? await functions.callWithTimeout("aegisPrivacyAction", data: payload, timeout: 15)
        } catch {
            // Non-fatal: UI state remains unchanged; caller should surface error
        }
    }

    // MARK: - Deactivate

    func deactivateCurrentMode() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            try await db
                .collection("aegisProfiles")
                .document(uid)
                .setData(["activeMode": FieldValue.delete(), "updatedAt": FieldValue.serverTimestamp()], merge: true)

            activeMode = nil
            updateConfigActiveStates(activeMode: nil)
        } catch {
            // Non-fatal
        }
    }

    // MARK: - Load

    func loadUserMode() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let doc = try await db
                .collection("aegisProfiles")
                .document(uid)
                .getDocument()

            if let raw = doc.data()?["activeMode"] as? String,
               let capability = AegisCapability(rawValue: raw),
               capability.lane == .privacyModes {
                activeMode = capability
                updateConfigActiveStates(activeMode: capability)
            } else {
                activeMode = nil
                updateConfigActiveStates(activeMode: nil)
            }
        } catch {
            // Non-fatal: keep previously seeded defaults
        }
    }

    // MARK: - Rules

    static func rulesFor(_ mode: AegisCapability) -> [AegisPrivacyRule] {
        switch mode {

        case .familyPrivacyMode: // C40
            return [
                AegisPrivacyRule(
                    ruleId: "C40-R1",
                    description: "Hide daily routine patterns from public profile and feed analytics.",
                    enforcement: .autoApply
                ),
                AegisPrivacyRule(
                    ruleId: "C40-R2",
                    description: "Require explicit consent before another user can tag a family member in posts or comments.",
                    enforcement: .requireConsent
                ),
                AegisPrivacyRule(
                    ruleId: "C40-R3",
                    description: "Restrict real-time and approximate location sharing to close connections only.",
                    enforcement: .block
                ),
                AegisPrivacyRule(
                    ruleId: "C40-R4",
                    description: "Automatically restrict content featuring minors to connections-only audience.",
                    enforcement: .autoApply
                ),
            ]

        case .churchSafetyMode: // C41
            return [
                AegisPrivacyRule(
                    ruleId: "C41-R1",
                    description: "Verify church affiliation before allowing admin actions in church spaces.",
                    enforcement: .requireConsent
                ),
                AegisPrivacyRule(
                    ruleId: "C41-R2",
                    description: "Restrict sensitive pastoral content (counseling notes, discipline matters) to verified church members only.",
                    enforcement: .autoApply
                ),
                AegisPrivacyRule(
                    ruleId: "C41-R3",
                    description: "Flag and review external donation requests from accounts not verified to the church.",
                    enforcement: .softPrompt
                ),
            ]

        case .minorProtectionMode: // C42
            return [
                AegisPrivacyRule(
                    ruleId: "C42-R1",
                    description: "Force all communication through communal (group/public) channels; disable private DMs from non-connections.",
                    enforcement: .block
                ),
                AegisPrivacyRule(
                    ruleId: "C42-R2",
                    description: "Restrict visible content to age-appropriate material only.",
                    enforcement: .autoApply
                ),
                AegisPrivacyRule(
                    ruleId: "C42-R3",
                    description: "Block content flagged as adult-only from appearing in this account's feed or search.",
                    enforcement: .block
                ),
            ]

        case .highRiskRegionMode: // C43
            return [
                AegisPrivacyRule(
                    ruleId: "C43-R1",
                    description: "Hide real name and location from public profile; show display alias only.",
                    enforcement: .autoApply
                ),
                AegisPrivacyRule(
                    ruleId: "C43-R2",
                    description: "Delay publication of location-tagged posts by 24 hours.",
                    enforcement: .autoApply
                ),
                AegisPrivacyRule(
                    ruleId: "C43-R3",
                    description: "Suppress social graph visibility — follower/following counts and lists are hidden from public view.",
                    enforcement: .autoApply
                ),
                AegisPrivacyRule(
                    ruleId: "C43-R4",
                    description: "Route media uploads through a privacy proxy to prevent direct-IP exposure.",
                    enforcement: .autoApply
                ),
            ]

        default:
            return []
        }
    }

    // MARK: - Private Helpers

    private func updateConfigActiveStates(activeMode: AegisCapability?) {
        modeConfigs = modeConfigs.map { config in
            var updated = config
            updated.isActive = (config.capability == activeMode)
            return updated
        }
    }
}
