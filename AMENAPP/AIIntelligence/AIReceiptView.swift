// AIReceiptView.swift
// AMENAPP
//
// Wave 1 — Transparency: the "AI Receipt" surface that expands under a Berean
// answer. Renders the REAL AIReceipt derived by AIReceiptService from the actual
// pipeline response: retrieved sources + locators, a confidence band with its
// basis, explicit unknowns, and the safety checks that actually passed.
//
// Two-accent contract: BLUE = affordance (the expand control), GREEN = state
// (a passed safety check). Confidence bands are rendered as neutral text + an
// SF Symbol, never as a decorative color, so the accent contract stays honest.
//
// Liquid Glass surface uses .ultraThinMaterial — the same glass treatment the
// Berean chat bubble in this module already uses — to stay visually consistent
// and avoid the glassEffect() shadowing landmine.
//
// Gated by AMENFeatureFlags.shared.aiReceiptEnabled (default OFF).

import SwiftUI

struct AIReceiptView: View {
    let receipt: AIReceipt
    /// Real backend interpretations; when more than one, Uncertainty Mode shows
    /// them as alternative grounded readings instead of a single answer.
    var interpretations: [String] = []

    @State private var expanded = false

    private var showsUncertainty: Bool {
        receipt.confidence.band == .low || interpretations.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 12 : 0) {
            header

            if expanded {
                Divider().opacity(0.4)
                confidenceSection
                if !receipt.sources.isEmpty { sourcesSection }
                if showsUncertainty && !interpretations.isEmpty { interpretationsSection }
                if !receipt.unknowns.isEmpty { unknownsSection }
                safetyChecksSection
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: expanded)
    }

    // MARK: - Header (the blue affordance)

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                Text("AI Receipt")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                confidenceBadge

                Spacer(minLength: 4)

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(.blue) // affordance accent
        .accessibilityLabel("AI Receipt, confidence \(receipt.confidence.band.rawValue)")
        .accessibilityHint(expanded ? "Collapses the receipt" : "Expands sources, confidence, and safety checks")
    }

    private var confidenceBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: bandSymbol)
                .font(.caption2)
            Text(receipt.confidence.band.rawValue.capitalized)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }

    private var bandSymbol: String {
        switch receipt.confidence.band {
        case .high: return "checkmark.seal"
        case .medium: return "minus.circle"
        case .low: return "questionmark.circle"
        }
    }

    // MARK: - Sections

    private var confidenceSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionTitle("Confidence")
            HStack(spacing: 6) {
                Text(receipt.confidence.band.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                if let score = receipt.confidence.score {
                    Text("· \(Int((score * 100).rounded()))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(receipt.confidence.basis)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Sources")
            ForEach(receipt.sources) { source in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: sourceSymbol(source.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(source.locator)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceSymbol(_ type: ReceiptSourceType) -> String {
        switch type {
        case .scripture: return "book.closed"
        case .commentary: return "text.quote"
        case .userNote: return "note.text"
        case .web: return "globe"
        }
    }

    private var interpretationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Multiple readings")
            Text("Sources support more than one grounded interpretation:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(interpretations.enumerated()), id: \.offset) { _, interpretation in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(interpretation)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unknownsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Not certain")
            ForEach(Array(receipt.unknowns.enumerated()), id: \.offset) { _, unknown in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(unknown)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // GREEN = state: each check that actually passed.
    private var safetyChecksSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Safety checks passed")
            ForEach(Array(receipt.safetyChecksPassed.enumerated()), id: \.offset) { _, check in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(check)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.4)
    }
}

// MARK: - Convenience attach modifier

extension View {
    /// Attaches an AI Receipt under a Berean answer when the flag is enabled and
    /// a receipt could be derived. No-op otherwise (fail-closed).
    @ViewBuilder
    func aiReceipt(_ receipt: AIReceipt?, interpretations: [String] = []) -> some View {
        if AMENFeatureFlags.shared.aiReceiptEnabled, let receipt {
            VStack(alignment: .leading, spacing: 8) {
                self
                AIReceiptView(receipt: receipt, interpretations: interpretations)
            }
        } else {
            self
        }
    }
}

#if DEBUG
#Preview("AI Receipt — expanded") {
    let receipt = AIReceipt(
        responseId: "trace-123",
        mode: "Discern",
        sources: [
            ReceiptSource(title: "Romans 8:28", type: .scripture, locator: "Romans 8:28", retrievalScore: nil),
            ReceiptSource(title: "Matthew Henry Commentary", type: .commentary, locator: "rom-8-commentary-chunk-4", retrievalScore: nil)
        ],
        confidence: ReceiptConfidence(band: .high, basis: "2 sources agree · trust 82%", score: 0.82),
        unknowns: ["Application to a specific personal circumstance is not addressed."],
        lastUpdated: "2026-06-22T08:00:00Z",
        safetyChecksPassed: ["Crisis pre-screen", "Constitutional review"]
    )
    return AIReceiptView(
        receipt: receipt,
        interpretations: ["A providential reading: God works all things toward good.",
                          "A covenantal reading: the promise is to those called according to purpose."]
    )
    .padding()
}
#endif
