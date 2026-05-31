// ProvenanceBadgeView.swift
// AMEN Trust Layer — T1 Provenance
// Liquid Glass capsule badges that surface content origin state on any media card.
// Flag-gated behind TrustAccessibilityFeatureFlags.provenanceBadgesEnabled.

import SwiftUI

// MARK: - Badge Config

private struct BadgeConfig {
    let symbol: String
    let label: String
    let tint: Color
}

private extension ContentOriginState {
    var badgeConfig: BadgeConfig {
        switch self {
        case .verifiedOriginal:
            return BadgeConfig(symbol: "checkmark.seal.fill",
                               label: "Original Capture",
                               tint: .green)
        case .edited:
            return BadgeConfig(symbol: "pencil.circle.fill",
                               label: "Edited Media",
                               tint: .blue)
        case .aiAssisted:
            return BadgeConfig(symbol: "sparkles",
                               label: "AI Assisted",
                               tint: .purple)
        case .aiGenerated:
            return BadgeConfig(symbol: "wand.and.stars",
                               label: "AI Generated",
                               tint: .orange)
        case .unverified:
            return BadgeConfig(symbol: "questionmark.circle",
                               label: "Unverified",
                               tint: .gray)
        }
    }
}

// MARK: - C2PAProvenanceBadge

/// A single Liquid Glass capsule that displays one ContentOriginState.
/// Tapping it presents a ProvenanceDetailSheet with the full C2PAMediaCredential.
struct C2PAProvenanceBadge: View {

    let credential: C2PAMediaCredential
    @State private var showDetail = false
    @ObservedObject private var flags = TrustAccessibilityFeatureFlags.shared

    var body: some View {
        if flags.provenanceBadgesEnabled {
            let config = credential.originState.badgeConfig
            Button {
                showDetail = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: config.symbol)
                        .font(.system(size: 11, weight: .semibold))
                    Text(config.label)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(config.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if #available(iOS 26.0, *) {
                        Capsule()
                            .glassEffect()
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(config.label). Tap for details.")
            .sheet(isPresented: $showDetail) {
                ProvenanceDetailSheet(credential: credential)
            }
        }
    }
}

// MARK: - C2PAProvenanceBadgeRow

/// A horizontal row combining a C2PAProvenanceBadge with an optional authenticity score pill.
struct C2PAProvenanceBadgeRow: View {

    let credential: C2PAMediaCredential
    var score: MediaAuthenticityScore?

    var body: some View {
        HStack(spacing: 8) {
            C2PAProvenanceBadge(credential: credential)

            if let score {
                MediaAuthenticityScorePill(score: score)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let credential = C2PAMediaCredential(
        mediaId: "preview-001",
        originState: .verifiedOriginal,
        c2paManifestPresent: true,
        signerType: .amenAppSigned,
        captureAttestation: nil,
        editChain: [],
        aiContributions: [],
        sourceVerified: true,
        metadataIntact: true
    )

    VStack(spacing: 16) {
        ForEach([
            ContentOriginState.verifiedOriginal,
            .edited,
            .aiAssisted,
            .aiGenerated,
            .unverified
        ], id: \.rawValue) { state in
            let c = C2PAMediaCredential(
                mediaId: "prev-\(state.rawValue)",
                originState: state,
                c2paManifestPresent: true,
                signerType: .amenAppSigned,
                captureAttestation: nil,
                editChain: [],
                aiContributions: [],
                sourceVerified: true,
                metadataIntact: true
            )
            C2PAProvenanceBadge(credential: c)
        }
    }
    .padding()
}
#endif
