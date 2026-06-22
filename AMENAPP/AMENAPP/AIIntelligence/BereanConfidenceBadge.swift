// BereanConfidenceBadge.swift
// AMENAPP
//
// Trust Layer 4 — Confidence badge for individual Berean AI responses.
// Shows a small colored dot + label (High / Moderate / Low / Unknown).
// Tappable to expand BereanEvidenceSheet. Respects Reduce Motion and Dynamic Type.
//
// Note: This file defines ResponseConfidenceLevel, which models per-response
// confidence (High/Moderate/Low/Unknown) and is distinct from the memory-entry
// BereanConfidenceLevel enum in BereanOS/BereanOSModels.swift.

import SwiftUI

// MARK: - ResponseConfidenceLevel

/// Four-tier confidence descriptor for an individual Berean AI response.
enum ResponseConfidenceLevel: String, CaseIterable, Identifiable {
    case high     = "High"
    case moderate = "Moderate"
    case low      = "Low"
    case unknown  = "Unknown"

    var id: String { rawValue }

    // MARK: Display

    var label: String { rawValue }

    /// Semantic dot color following the spec: green / yellow / orange / gray.
    var dotColor: Color {
        switch self {
        case .high:     return .green
        case .moderate: return Color(red: 0.98, green: 0.82, blue: 0.10)   // yellow
        case .low:      return .orange
        case .unknown:  return Color(.systemGray)
        }
    }

    /// VoiceOver-friendly full label.
    var accessibilityDescription: String {
        "Response confidence: \(rawValue)"
    }

    // MARK: Factory

    /// Derives a ResponseConfidenceLevel from a 0.0–1.0 confidence score.
    static func from(score: Double) -> ResponseConfidenceLevel {
        switch score {
        case 0.75...: return .high
        case 0.50...: return .moderate
        case 0.25...: return .low
        default:      return .unknown
        }
    }

    /// Derives a ResponseConfidenceLevel from the string labels used by
    /// BereanEvidenceSheet (e.g. "High Confidence", "Moderate Confidence").
    static func from(confidenceString: String) -> ResponseConfidenceLevel {
        let lower = confidenceString.lowercased()
        if lower.contains("high") { return .high }
        if lower.contains("moderate") { return .moderate }
        if lower.contains("low") { return .low }
        return .unknown
    }
}

// MARK: - BereanConfidenceBadge

/// Compact badge displaying the confidence level of a Berean AI response.
/// Tap to open the full evidence sheet (`BereanEvidenceSheet`).
/// Conforms to the AIIntelligence Trust Layer 4 spec.
struct BereanConfidenceBadge: View {

    // MARK: Inputs

    let level: ResponseConfidenceLevel
    /// Evidence chunks forwarded to BereanEvidenceSheet.
    let evidence: [EvidenceChunk]
    /// Confidence string forwarded to BereanEvidenceSheet (e.g. "High Confidence").
    let confidenceString: String
    /// Trace ID forwarded to BereanEvidenceSheet.
    let traceId: String

    // MARK: State

    @State private var showEvidence: Bool = false

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        Button {
            showEvidence = true
        } label: {
            badgeLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel(level.accessibilityDescription)
        .accessibilityHint("Double-tap to view evidence sources for this response.")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showEvidence) {
            BereanEvidenceSheet(
                isPresented: $showEvidence,
                evidence: evidence,
                confidence: confidenceString,
                traceId: traceId
            )
        }
    }

    // MARK: - Badge Label

    private var badgeLabel: some View {
        HStack(spacing: 5) {
            // Colored dot — no animation when Reduce Motion is on
            Circle()
                .fill(level.dotColor)
                .frame(width: 7, height: 7)
                .opacity(reduceMotion ? 1.0 : 1.0)  // pulse disabled per spec

            Text(level.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(level.dotColor)
                .dynamicTypeSize(.small ... .accessibility3)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(level.dotColor.opacity(0.30), lineWidth: 0.5)
        )
    }
}

// MARK: - BereanConfidenceBadgeRow

/// Horizontal row that pairs a "Confidence" prefix label with `BereanConfidenceBadge`.
/// Drop this into any Berean response footer.
struct BereanConfidenceBadgeRow: View {

    let level: ResponseConfidenceLevel
    let evidence: [EvidenceChunk]
    let confidenceString: String
    let traceId: String

    var body: some View {
        HStack(spacing: 8) {
            Text("Confidence")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(Color(.tertiaryLabel))
                .dynamicTypeSize(.small ... .accessibility3)

            BereanConfidenceBadge(
                level: level,
                evidence: evidence,
                confidenceString: confidenceString,
                traceId: traceId
            )

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Score-initialised convenience

extension BereanConfidenceBadge {
    /// Convenience initialiser that derives the level from a 0.0–1.0 score.
    init(score: Double, evidence: [EvidenceChunk], confidenceString: String, traceId: String) {
        self.init(
            level: ResponseConfidenceLevel.from(score: score),
            evidence: evidence,
            confidenceString: confidenceString,
            traceId: traceId
        )
    }
}

extension BereanConfidenceBadgeRow {
    /// Convenience initialiser that derives the level from a 0.0–1.0 score.
    init(score: Double, evidence: [EvidenceChunk], confidenceString: String, traceId: String) {
        self.init(
            level: ResponseConfidenceLevel.from(score: score),
            evidence: evidence,
            confidenceString: confidenceString,
            traceId: traceId
        )
    }
}

// MARK: - Previews

#Preview("All confidence levels") {
    let sampleEvidence: [EvidenceChunk] = [
        EvidenceChunk(
            id: "1",
            citation: "John 3:16",
            content: "For God so loved the world that he gave his one and only Son.",
            source: "scripture"
        ),
        EvidenceChunk(
            id: "2",
            citation: "Westminster Confession, Ch. 5",
            content: "God the great Creator of all things doth uphold, direct, dispose, and govern all creatures.",
            source: "theology"
        ),
    ]

    VStack(alignment: .leading, spacing: 16) {
        ForEach(ResponseConfidenceLevel.allCases) { level in
            BereanConfidenceBadgeRow(
                level: level,
                evidence: sampleEvidence,
                confidenceString: "\(level.label) Confidence",
                traceId: "preview-trace-\(level.rawValue)"
            )
        }
    }
    .padding(24)
    .background(Color(.systemGroupedBackground))
}

#Preview("Score-based badge") {
    let evidence: [EvidenceChunk] = [
        EvidenceChunk(id: "s1", citation: "Psalm 23:1", content: "The LORD is my shepherd; I shall not want.", source: "scripture")
    ]

    VStack(spacing: 12) {
        BereanConfidenceBadge(score: 0.92, evidence: evidence, confidenceString: "High Confidence", traceId: "trace-high")
        BereanConfidenceBadge(score: 0.61, evidence: evidence, confidenceString: "Moderate Confidence", traceId: "trace-moderate")
        BereanConfidenceBadge(score: 0.38, evidence: evidence, confidenceString: "Low Confidence", traceId: "trace-low")
        BereanConfidenceBadge(score: 0.10, evidence: evidence, confidenceString: "Unknown Confidence", traceId: "trace-unknown")
    }
    .padding(24)
    .background(Color(.systemGroupedBackground))
}
