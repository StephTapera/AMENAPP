import SwiftUI

struct PrivacySafetyCenterView: View {
    private let toggles = SocialV2AIPrivacyToggles(
        recommendationsEnabled: false,
        personalizationEnabled: false,
        assistantsEnabled: false,
        searchEnabled: false
    )

    private let decisions = PrivacySafetySampleData.decisions

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                aiControls
                locationControls
                accountStatus
                moderationExplanations
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("Privacy & Safety")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy Center")
                .font(.title2.weight(.semibold))
            Text("Every AI use is independently controlled, and sensitive content fails closed while review is pending.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var aiControls: some View {
        SocialV2GlassCard(tintContext: .interactive) {
            VStack(alignment: .leading, spacing: 12) {
                Text("AI Controls")
                    .font(.headline)
                PrivacyToggleRow(title: "Recommendations", isEnabled: toggles.recommendationsEnabled)
                PrivacyToggleRow(title: "Personalization", isEnabled: toggles.personalizationEnabled)
                PrivacyToggleRow(title: "Assistants", isEnabled: toggles.assistantsEnabled)
                PrivacyToggleRow(title: "Search", isEnabled: toggles.searchEnabled)
            }
        }
    }

    private var locationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location Privacy")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(SocialV2LocationScope.allCases) { scope in
                    SocialV2GlassPill(tintContext: scope == .hidden ? .state : .interactive, isSelected: scope == .region) {
                        Label(scope.rawValue.capitalized, systemImage: scope == .hidden ? "eye.slash" : "location")
                    }
                }
            }
            Text("Exact GPS is not an available Social V2 scope.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accountStatus: some View {
        SocialV2GlassCard(tintContext: .state, isActive: true) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Account Status")
                        .font(.headline)
                    Text("No active restrictions. Account health is categorical and never shown as a numeric person score.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var moderationExplanations: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Content Review")
                .font(.headline)

            ForEach(decisions) { decision in
                SocialV2GlassCard(tintContext: decision.isReadable ? .state : .alert) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(decision.status.rawValue.capitalized)
                            .font(.headline)
                        Text(decision.explanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Policy: \(decision.policyReference)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct PrivacyToggleRow: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            SocialV2GlassPill(tintContext: isEnabled ? .state : .neutral, isSelected: isEnabled) {
                Label(isEnabled ? "On" : "Off", systemImage: isEnabled ? "checkmark" : "minus")
            }
        }
    }
}

private enum PrivacySafetySampleData {
    static let decisions = [
        SocialV2ModerationDecision(
            id: "privacy-review-1",
            status: .approved,
            policyReference: "community-care",
            explanation: "The post is visible after review.",
            decidedAt: Date()
        ),
        SocialV2ModerationDecision(
            id: "privacy-review-2",
            status: .held,
            policyReference: "harassment-review",
            explanation: "This content remains hidden while evidence and appeal options are prepared.",
            decidedAt: Date()
        )
    ]
}
