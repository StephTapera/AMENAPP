// BereanCitationTile.swift
// AMEN App — Expandable glass citation chips for Berean AI message bubbles.
//
// Replaces the previous boxed file-card citation style with inline glass chips
// that expand into a detail sheet on tap.
//
// Usage:
//   // Inline chip (collapsed, in message bubble):
//   BereanCitationTile(source: source)
//
//   // Horizontal row below the message bubble:
//   BereanCitationRow(sources: message.provenance?.sources ?? [])
//
// BereanProvenanceSource is declared here since it is not yet part of
// BereanProvenanceRecord — it will be wired up in a future model update.

import SwiftUI

// MARK: - BereanProvenanceSource

/// An individual citation source attached to a Berean AI response.
/// Declared here until it is promoted into BereanGrokModels.swift.
struct BereanProvenanceSource: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Human-readable reference, e.g. "John 3:16" or "Westminster Confession, Ch. 8"
    let reference: String
    /// Category of source: "verse", "doc", or "memory"
    let type: String
    /// Verification confidence in [0, 1]
    let confidence: Double
    /// Optional full text of the passage (may be nil when fetched lazily)
    var fullText: String?
    /// Optional cross-references for expanded sheet
    var crossReferences: [BereanProvenanceSource]?

    init(
        id: UUID = UUID(),
        reference: String,
        type: String,
        confidence: Double,
        fullText: String? = nil,
        crossReferences: [BereanProvenanceSource]? = nil
    ) {
        self.id = id
        self.reference = reference
        self.type = type
        self.confidence = confidence
        self.fullText = fullText
        self.crossReferences = crossReferences
    }
}

// MARK: - BereanCitationTile

/// A single expandable citation chip.
/// `compact: true` renders as an inline glass chip (default).
/// `compact: false` renders as the full sheet content body.
struct BereanCitationTile: View {

    let source: BereanProvenanceSource
    var compact: Bool = true

    @State private var isSheetPresented = false

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let tileSpring = Animation.spring(response: 0.32, dampingFraction: 0.80)

    var body: some View {
        if compact {
            chipView
        } else {
            sheetContentView
        }
    }

    // MARK: - Chip (collapsed inline)

    private var chipView: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isSheetPresented = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: sourceIcon)
                    .font(AMENFont.medium(11))
                    .foregroundStyle(BereanColor.textSecondary)

                Text(source.reference)
                    .font(AMENFont.medium(12))
                    .foregroundStyle(Color.amenGold)
                    .lineLimit(1)

                verificationBadge
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 0)
            .frame(height: 32)
            .background(chipBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(BereanColor.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(_CitationChipButtonStyle(reduceMotion: reduceMotion))
        // VoiceOver: announces reference + verification status
        .accessibilityLabel(accessibilityChipLabel)
        .accessibilityHint("Double tap to view full citation details")
        .sheet(isPresented: $isSheetPresented) {
            BereanCitationDetailSheet(source: source)
        }
    }

    // MARK: - Verification badge

    private var verificationBadge: some View {
        Group {
            if source.confidence >= 0.75 {
                Image(systemName: "checkmark")
                    .font(AMENFont.medium(9))
                    .foregroundStyle(Color.amenGold)
            } else {
                Image(systemName: "clock")
                    .font(AMENFont.medium(9))
                    .foregroundStyle(BereanColor.textTertiary)
            }
        }
    }

    // MARK: - Sheet content (compact: false)

    private var sheetContentView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text(source.reference)
                .font(AMENFont.semiBold(22))
                .foregroundStyle(BereanColor.textPrimary)

            // Passage text
            Text(source.fullText ?? source.reference)
                .font(AMENFont.regular(16))
                .foregroundStyle(BereanColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(5)

            // Confidence bar
            confidenceBar

            // Verification status
            verificationStatus

            // Cross-references
            if let refs = source.crossReferences, !refs.isEmpty {
                crossReferencesSection(refs)
            }

            // Strong's / Commentary placeholder
            strongsPlaceholder
        }
    }

    // MARK: - Confidence bar

    private var confidenceBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Confidence")
                .font(AMENFont.medium(12))
                .foregroundStyle(BereanColor.textTertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BereanColor.glassFill)
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.amenGold)
                        .frame(width: geo.size.width * source.confidence, height: 6)
                        .animation(
                            reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.82),
                            value: source.confidence
                        )
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Verification status

    private var verificationStatus: some View {
        HStack(spacing: 8) {
            if source.confidence >= 0.75 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.amenGold)
                Text("Verified by Berean")
                    .font(AMENFont.medium(13))
                    .foregroundStyle(BereanColor.textPrimary)
            } else {
                Image(systemName: "clock.fill")
                    .foregroundStyle(BereanColor.textTertiary)
                Text("Pending verification")
                    .font(AMENFont.medium(13))
                    .foregroundStyle(BereanColor.textSecondary)
            }
        }
    }

    // MARK: - Cross-references section

    @ViewBuilder
    private func crossReferencesSection(_ refs: [BereanProvenanceSource]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cross-references")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(BereanColor.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(refs) { ref in
                        // Non-expandable chips in sheet (sheet-in-sheet avoided)
                        HStack(spacing: 5) {
                            Image(systemName: iconForType(ref.type))
                                .font(AMENFont.medium(10))
                                .foregroundStyle(BereanColor.textSecondary)
                            Text(ref.reference)
                                .font(AMENFont.medium(11))
                                .foregroundStyle(Color.amenGold)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(chipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(BereanColor.glassBorder, lineWidth: 0.5)
                        )
                        .accessibilityLabel("Cross-reference: \(ref.reference)")
                    }
                }
            }
        }
    }

    // MARK: - Strong's placeholder

    private var strongsPlaceholder: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.book.closed")
                .font(AMENFont.medium(16))
                .foregroundStyle(BereanColor.textTertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Strong's / Commentary")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(BereanColor.textTertiary)
                Text("Coming soon — lexicon and commentary integration")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(BereanColor.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BereanColor.glassFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(BereanColor.glassBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private var sourceIcon: String { iconForType(source.type) }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "verse":  return "book.closed"
        case "doc":    return "doc.text"
        case "memory": return "brain"
        default:       return "quote.opening"
        }
    }

    private var accessibilityChipLabel: String {
        let status = source.confidence >= 0.75 ? "verified" : "pending verification"
        return "Citation: \(source.reference), \(status)"
    }

    private var chipBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

// MARK: - BereanCitationDetailSheet

/// Full-height sheet presented when a BereanCitationTile chip is tapped.
private struct BereanCitationDetailSheet: View {

    let source: BereanProvenanceSource
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BereanCitationTile(source: source, compact: false)
                        .padding(20)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(source.reference)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(AMENFont.medium(15))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - BereanCitationRow

/// Horizontal scroll row of BereanCitationTile chips.
/// Drop this below a message bubble to surface all provenance sources.
struct BereanCitationRow: View {

    let sources: [BereanProvenanceSource]

    var body: some View {
        if !sources.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sources) { source in
                        BereanCitationTile(source: source, compact: true)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Citations: \(sources.count) source\(sources.count == 1 ? "" : "s")")
        }
    }
}

// MARK: - Chip button style

private struct _CitationChipButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1.0)
            .animation(
                reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

// MARK: - Previews

private let previewSources: [BereanProvenanceSource] = [
    BereanProvenanceSource(
        reference: "John 3:16",
        type: "verse",
        confidence: 0.97,
        fullText: "For God so loved the world, that he gave his only Son, that whoever believes in him should not perish but have eternal life.",
        crossReferences: [
            BereanProvenanceSource(reference: "Romans 5:8", type: "verse", confidence: 0.91),
            BereanProvenanceSource(reference: "1 John 4:9", type: "verse", confidence: 0.88)
        ]
    ),
    BereanProvenanceSource(
        reference: "Romans 8:28",
        type: "verse",
        confidence: 0.62,
        fullText: "And we know that for those who love God all things work together for good, for those who are called according to his purpose."
    ),
    BereanProvenanceSource(
        reference: "Westminster Confession Ch. 8",
        type: "doc",
        confidence: 0.44
    )
]

#Preview("Citation row — three sources") {
    ZStack {
        Color(uiColor: .systemBackground).ignoresSafeArea()
        VStack(alignment: .leading, spacing: 16) {
            Text("John 3:16 is the foundational verse of the Gospel…")
                .font(AMENFont.regular(16))
                .foregroundStyle(BereanColor.textPrimary)
                .padding(.horizontal, 16)

            BereanCitationRow(sources: previewSources)
                .padding(.horizontal, 16)
        }
        .padding(.top, 120)
    }
}

#Preview("Single tile — chip") {
    ZStack {
        Color(uiColor: .systemBackground).ignoresSafeArea()
        BereanCitationTile(source: previewSources[0], compact: true)
    }
}

#Preview("Single tile — sheet content") {
    ScrollView {
        BereanCitationTile(source: previewSources[0], compact: false)
            .padding(20)
    }
    .background(Color(uiColor: .systemBackground))
}

#Preview("Pending verification tile") {
    ZStack {
        Color(uiColor: .systemBackground).ignoresSafeArea()
        BereanCitationTile(source: previewSources[2], compact: true)
    }
}
