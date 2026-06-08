// AmenReplayRecapCard.swift
// AMEN Connect + Spaces — AI Recap Card
// Built 2026-06-02

import SwiftUI
import FirebaseFunctions

// MARK: - Shimmer modifier

private struct AmenShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0), location: 0),
                        .init(color: Color.white.opacity(0.12), location: 0.45),
                        .init(color: Color.white.opacity(0.25), location: 0.50),
                        .init(color: Color.white.opacity(0.12), location: 0.55),
                        .init(color: Color.white.opacity(0), location: 1)
                    ]),
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint: UnitPoint(x: phase + 0.6, y: 0.5)
                )
                .allowsHitTesting(false)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

private extension View {
    func amenShimmer() -> some View {
        modifier(AmenShimmerModifier())
    }
}

// MARK: - Scripture chip

private struct ScriptureChip: View {
    let ref: AmenConnectSpacesScriptureRefProvenance

    var body: some View {
        Group {
            // Hard rule: noScriptureWithoutProvenance — never render ref below threshold
            if ref.confidence < 0.8 {
                Text("Verifying…")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule().fill(.ultraThinMaterial)
                            .overlay { Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                    }
                    .amenShimmer()
            } else {
                Text(ref.reference)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule().fill(.ultraThinMaterial)
                            .overlay {
                                Capsule().strokeBorder(Color(hex: "D9A441").opacity(0.4), lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("Scripture: \(ref.reference), \(ref.translation)")
            }
        }
    }
}

// MARK: - Pending review state

private struct RecapPendingReviewView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.checkmark")
                .font(.systemScaled(32))
                .foregroundStyle(Color(hex: "6E4BB5").opacity(0.8))
                .accessibilityHidden(true)
            Text("This recap is being reviewed")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.primary)
            Text("AI-generated content passes through a review process before it appears here.")
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .amenShimmer()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recap pending review. AI content is being checked before display.")
    }
}

// MARK: - Main card

struct AmenReplayRecapCard: View {
    let recap: AmenAIRecap
    let onViewFullTranscript: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var durationLabel: String {
        let minutes = recap.durationEstimateSecs / 60
        let seconds = recap.durationEstimateSecs % 60
        if minutes > 0 {
            return "~\(minutes)-minute read"
        } else {
            return "~\(seconds)-second read"
        }
    }

    var body: some View {
        // Content stays matte — glass design rule
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)

            // Hard gate: never render unreviewed AI output
            if recap.aegisReviewedAt == nil {
                RecapPendingReviewView()
            } else {
                reviewedContent
            }
        }
        .background(Color(hex: "070607"))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recap.sourceTitle)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(Self.dateFormatter.string(from: recap.generatedAt))
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(durationLabel)
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            // Chrome pill — glass per design rule
            Text("AI Recap")
                .font(.systemScaled(10, weight: .semibold, design: .monospaced))
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(Color(hex: "6E4BB5"))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule().fill(.thinMaterial)
                        .overlay {
                            Capsule().strokeBorder(Color(hex: "6E4BB5").opacity(0.45), lineWidth: 1)
                        }
                }
                .accessibilityLabel("AI generated recap")
        }
        .padding(16)
    }

    // MARK: - Reviewed content

    private var reviewedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !recap.keyPoints.isEmpty {
                keyPointsSection
            }

            if !recap.scriptureRefs.isEmpty {
                scriptureSection
            }

            if !recap.actionItems.isEmpty {
                actionItemsSection
            }

            if let excerpt = recap.quotedExcerpt, !excerpt.isEmpty {
                excerptSection(excerpt)
            }

            transcriptButton
        }
        .padding(16)
    }

    // MARK: - Key Points

    private var keyPointsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Key Points")
            ForEach(Array(recap.keyPoints.enumerated()), id: \.offset) { index, point in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.systemScaled(11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "6E4BB5"))
                        .frame(width: 18, alignment: .trailing)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    Text(point)
                        .font(.systemScaled(14))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Key point \(index + 1): \(point)")
            }
        }
    }

    // MARK: - Scriptures

    private var scriptureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Scriptures Referenced")
            FlexibleWrap(spacing: 6) {
                ForEach(recap.scriptureRefs) { ref in
                    ScriptureChip(ref: ref)
                }
            }
        }
    }

    // MARK: - Action Items

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Action Items")
            ForEach(Array(recap.actionItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(.systemScaled(14))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Action item: \(item)")
            }
        }
    }

    // MARK: - Quoted Excerpt

    private func excerptSection(_ excerpt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Excerpt")
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(hex: "D9A441").opacity(0.6))
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .accessibilityHidden(true)
                Text(excerpt)
                    .font(.systemScaled(14, weight: .light).italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
            }
            .accessibilityLabel("Quoted excerpt: \(excerpt)")
        }
    }

    // MARK: - Transcript Button

    private var transcriptButton: some View {
        Button(action: onViewFullTranscript) {
            HStack {
                Spacer()
                Text("View Full Transcript")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color(hex: "6E4BB5"))
                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color(hex: "6E4BB5"))
                Spacer()
            }
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "6E4BB5").opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(hex: "6E4BB5").opacity(0.3), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View full transcript")
    }

    // MARK: - Section Label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.systemScaled(11, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Simple flex wrap layout

private struct FlexibleWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
    }
}

// MARK: - Preview

#Preview("Reviewed recap") {
    ScrollView {
        AmenReplayRecapCard(
            recap: AmenAIRecap(
                id: "r1",
                spaceId: "s1",
                sourceRef: "video-001",
                sourceTitle: "Sunday Morning Teaching: Walking in Faith",
                keyPoints: [
                    "Faith requires active obedience, not passive belief.",
                    "Abraham's journey illustrates trust before understanding.",
                    "Community accountability strengthens individual faith."
                ],
                scriptureRefs: [
                    AmenConnectSpacesScriptureRefProvenance(
                        id: "sr1", reference: "Hebrews 11:1", translation: "ESV",
                        sourceLayer: .canonicalReference, verifiedAt: Date(), confidence: 0.97
                    ),
                    AmenConnectSpacesScriptureRefProvenance(
                        id: "sr2", reference: "Genesis 12:1-4", translation: "NIV",
                        sourceLayer: .translationSource, verifiedAt: Date(), confidence: 0.65
                    )
                ],
                actionItems: [
                    "Journal one area where you're waiting on God this week.",
                    "Share your next step with an accountability partner."
                ],
                quotedExcerpt: "\"The great act of faith is when a man decides he is not God.\"",
                durationEstimateSecs: 90,
                generatedAt: Date(),
                aegisReviewedAt: Date()
            ),
            onViewFullTranscript: {}
        )
        .padding()
    }
    .background(Color(hex: "1A1A1A"))
}

#Preview("Pending review") {
    ScrollView {
        AmenReplayRecapCard(
            recap: AmenAIRecap(
                id: "r2",
                spaceId: "s1",
                sourceRef: "video-002",
                sourceTitle: "Wednesday Night Study",
                keyPoints: ["Hidden — pending review"],
                scriptureRefs: [],
                actionItems: [],
                quotedExcerpt: nil,
                durationEstimateSecs: 90,
                generatedAt: Date(),
                aegisReviewedAt: nil   // triggers pending state
            ),
            onViewFullTranscript: {}
        )
        .padding()
    }
    .background(Color(hex: "1A1A1A"))
}
