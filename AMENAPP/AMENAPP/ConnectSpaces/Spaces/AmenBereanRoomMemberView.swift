// AmenBereanRoomMemberView.swift
// AMEN Spaces — Agent 4: Spaces Intelligence
//
// Berean as a distinct room participant in the chat list.
// Glass rules: avatar bubble + AI badge may be glass (chrome).
//              Message body text is always matte (never glass-on-glass).
//              Scripture provenance chips are matte.
// Aegis rule: scripture citations must show ≥1 provenance chip; empty → "Verifying…" shimmer.

import SwiftUI
import FirebaseFirestore

// MARK: - Berean Message Model

/// A Berean-generated chat message with optional scripture provenance.
struct AmenBereanMessage: Identifiable, Hashable {
    let id: String
    var body: String
    /// Scripture references cited in this message. Empty means provenance not yet resolved.
    var scriptureRefs: [AmenConnectSpacesScriptureRefProvenance]
    var createdAt: Date
}

// MARK: - Provenance Chip Row (scripture-only, matte)

private struct BereanRoomProvenanceChipRow: View {
    let refs: [AmenConnectSpacesScriptureRefProvenance]
    let isVerifying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isVerifying {
            // Aegis rule: empty provenance → matte shimmer, never hide
            VerifyingShimmer(reduceMotion: reduceMotion)
                .accessibilityLabel("Verifying scripture provenance")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(refs) { ref in
                        ProvenanceChip(ref: ref)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ProvenanceChip: View {
    let ref: AmenConnectSpacesScriptureRefProvenance

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: layerIcon(ref.sourceLayer))
                .font(.systemScaled(8, weight: .semibold))
            Text(chipLabel(ref))
                .font(.systemScaled(9, weight: .bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            // Matte — never glass-on-glass
            RoundedRectangle(cornerRadius: 999)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .foregroundStyle(Color.white.opacity(0.70))
        .accessibilityLabel(accessibilityLabel(ref))
    }

    private func layerIcon(_ layer: AmenConnectSpacesScriptureProvenanceLayer) -> String {
        switch layer {
        case .canonicalReference: return "book.closed"
        case .translationSource:  return "character.book.closed"
        case .contextWindow:      return "text.magnifyingglass"
        case .bereanStudySheet:   return "checkmark.seal"
        }
    }

    private func chipLabel(_ ref: AmenConnectSpacesScriptureRefProvenance) -> String {
        switch ref.sourceLayer {
        case .canonicalReference: return ref.reference
        case .translationSource:  return ref.translation
        case .contextWindow:      return "Context"
        case .bereanStudySheet:   return "Study Sheet"
        }
    }

    private func accessibilityLabel(_ ref: AmenConnectSpacesScriptureRefProvenance) -> String {
        "Provenance: \(ref.sourceLayer.rawValue), \(ref.reference), \(ref.translation)"
    }
}

private struct VerifyingShimmer: View {
    let reduceMotion: Bool
    @State private var opacity: Double = 0.4

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color.white.opacity(opacity))
                    .frame(width: 64, height: 18)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                opacity = 0.12
            }
        }
    }
}

// MARK: - Berean Avatar

private struct BereanAvatarBubble: View {
    var body: some View {
        ZStack {
            // Glass avatar bubble — chrome surface, allowed
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(hex: "#D9A441").opacity(0.50), lineWidth: 1)
                )
                .shadow(color: Color(hex: "#D9A441").opacity(0.20), radius: 8, y: 0)
            Text("B")
                .font(.systemScaled(14, weight: .black))
                .foregroundStyle(Color(hex: "#D9A441"))
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

// MARK: - Berean AI Badge

private struct BereanAIBadge: View {
    var body: some View {
        // Glass pill — chrome, allowed
        HStack(spacing: 3) {
            Text("✦")
                .font(.systemScaled(8, weight: .bold))
            Text("AI")
                .font(.systemScaled(9, weight: .bold))
                .kerning(0.5)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color(hex: "#6E4BB5").opacity(0.45), lineWidth: 1)
                )
        )
        .foregroundStyle(Color(hex: "#6E4BB5"))
        .accessibilityLabel("Berean AI")
    }
}

// MARK: - Berean Room Member View (single message entry)

struct AmenBereanRoomMemberView: View {
    let message: AmenBereanMessage

    /// True when the message cites scripture but provenance is still empty (Aegis rule).
    private var needsVerification: Bool {
        containsScriptureCitation && message.scriptureRefs.isEmpty
    }

    /// Heuristic: treat any message with refs array present as scripture-citing.
    /// In production this flag should come from the Berean output payload.
    private var containsScriptureCitation: Bool {
        // If scriptureRefs was populated or the body contains a reference marker.
        !message.scriptureRefs.isEmpty ||
        message.body.contains(":") // lightweight heuristic (e.g. "John 3:16")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: avatar + name + badge
            HStack(alignment: .center, spacing: 8) {
                BereanAvatarBubble()

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Berean")
                            .font(.systemScaled(13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.92))
                        BereanAIBadge()
                    }
                    Text(message.createdAt.formatted(.relative(presentation: .named)))
                        .font(.systemScaled(10))
                        .foregroundStyle(Color.white.opacity(0.38))
                }
                Spacer()
            }

            // Message body — always matte text, never glass-on-glass
            Text(message.body)
                .font(.systemScaled(13))
                .foregroundStyle(Color.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(
                    // Matte surface per design rule
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "#1A161E"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
                .accessibilityLabel("Berean says: \(message.body)")

            // Scripture provenance chip row — matte, shown when scripture is cited
            if containsScriptureCitation || needsVerification {
                BereanRoomProvenanceChipRow(
                    refs: message.scriptureRefs,
                    isVerifying: needsVerification
                )
                .padding(.leading, 44) // indent under avatar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 0) {
            AmenBereanRoomMemberView(
                message: AmenBereanMessage(
                    id: "b1",
                    body: "Based on John 3:16, God's love is unconditional. Let's examine the Greek word 'agape' here.",
                    scriptureRefs: [
                        AmenConnectSpacesScriptureRefProvenance(
                            id: "r1",
                            reference: "John 3:16",
                            translation: "KJV", // TODO(legal): was ESV (Crossway, copyrighted) — changed to KJV per AMEN-CONTENT-001
                            sourceLayer: .canonicalReference,
                            verifiedAt: Date(),
                            confidence: 0.98
                        ),
                        AmenConnectSpacesScriptureRefProvenance(
                            id: "r2",
                            reference: "John 3:16",
                            translation: "KJV", // TODO(legal): was ESV (Crossway, copyrighted) — changed to KJV per AMEN-CONTENT-001
                            sourceLayer: .translationSource,
                            verifiedAt: Date(),
                            confidence: 0.95
                        ),
                        AmenConnectSpacesScriptureRefProvenance(
                            id: "r3",
                            reference: "John 3:16",
                            translation: "KJV", // TODO(legal): was ESV (Crossway, copyrighted) — changed to KJV per AMEN-CONTENT-001
                            sourceLayer: .contextWindow,
                            verifiedAt: Date(),
                            confidence: 0.91
                        ),
                        AmenConnectSpacesScriptureRefProvenance(
                            id: "r4",
                            reference: "John 3:16",
                            translation: "KJV", // TODO(legal): was ESV (Crossway, copyrighted) — changed to KJV per AMEN-CONTENT-001
                            sourceLayer: .bereanStudySheet,
                            verifiedAt: Date(),
                            confidence: 0.88
                        )
                    ],
                    createdAt: Date()
                )
            )

            Divider().opacity(0.1)

            // Verifying shimmer state
            AmenBereanRoomMemberView(
                message: AmenBereanMessage(
                    id: "b2",
                    body: "Romans 8:28 reminds us that God works all things together for good.",
                    scriptureRefs: [], // empty → triggers verifying shimmer
                    createdAt: Date().addingTimeInterval(-300)
                )
            )
        }
    }
    .background(Color(hex: "#070607"))
}
#endif
