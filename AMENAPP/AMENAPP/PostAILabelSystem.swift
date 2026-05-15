import SwiftUI
import FirebaseAnalytics

// MARK: - PostAILabelPill
// Small, non-punitive disclosure capsule shown in the post metadata row.
// Tap opens AILabelDetailSheet with plain-language explanation.

struct PostAILabelPill: View {

    let aiUsage: PostAIUsage

    @State private var showDetail = false

    private var label: AIPublicLabel? {
        aiUsage.primaryLabel == .toneChecked && !aiUsage.usedAI ? nil : aiUsage.primaryLabel
    }

    var body: some View {
        if let label {
            Button {
                showDetail = true
                Analytics.logEvent("post_ai_label_tapped", parameters: [
                    "label": label.rawValue
                ])
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9, weight: .medium))
                    Text(label.displayText)
                        .font(AMENFont.semiBold(10))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.thinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .onAppear {
                Analytics.logEvent("post_ai_label_rendered", parameters: [
                    "label": label.rawValue
                ])
            }
            .sheet(isPresented: $showDetail) {
                AILabelDetailSheet(label: label, aiUsage: aiUsage)
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - AILabelDetailSheet
// Liquid Glass bottom sheet. Explains what AI helped with.
// No blame language — builds trust, not shame.

struct AILabelDetailSheet: View {

    let label: AIPublicLabel
    let aiUsage: PostAIUsage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dragHandle

            VStack(alignment: .leading, spacing: 20) {
                labelHeader
                disclosureBody
                toneScoreRow
                authorControlLine
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)

            Spacer()

            closeButton
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .onAppear {
            Analytics.logEvent("ai_label_detail_opened", parameters: [
                "label": label.rawValue
            ])
        }
    }

    // MARK: - Subviews

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 20)
    }

    private var labelHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.primary)

            Text(label.displayText)
                .font(AMENFont.semiBold(18))
                .foregroundStyle(.primary)
        }
    }

    private var disclosureBody: some View {
        Text(label.disclosureCopy)
            .font(AMENFont.regular(15))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var toneScoreRow: some View {
        if label == .toneChecked || label == .aiAssistedTone,
           let summary = aiUsage.toneCheckSummary {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tone check")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .kerning(0.5)

                HStack(spacing: 12) {
                    ToneScorePill(label: "Kindness", score: summary.kindnessScore)
                    ToneScorePill(label: "Clarity", score: summary.clarityScore)
                    ToneScorePill(label: "Humility", score: summary.humilityScore)
                    ToneScorePill(label: "Peace", score: summary.peaceScore)
                }
            }
        }
    }

    private var authorControlLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("The author stayed in control of the final post.")
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
        }
    }

    private var closeButton: some View {
        Button("Done") { dismiss() }
            .font(AMENFont.semiBold(15))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .buttonStyle(.plain)
    }
}

// MARK: - ToneScorePill

private struct ToneScorePill: View {
    let label: String
    let score: Double  // 0.0 – 1.0

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Int(score * 100))")
                .font(AMENFont.semiBold(13))
            Text(label)
                .font(AMENFont.regular(10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Convenience modifier for PostCard

extension View {
    /// Adds an AI label pill to any view if aiUsage is non-nil and AI was actually used.
    func amenAILabel(_ aiUsage: PostAIUsage?) -> some View {
        Group {
            if let usage = aiUsage, usage.usedAI {
                HStack(spacing: 6) {
                    self
                    PostAILabelPill(aiUsage: usage)
                }
            } else {
                self
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let usage = PostAIUsage(
        usedAI: true,
        aiUseTypes: [.toneCheck],
        primaryLabel: .toneChecked,
        secondaryDetail: nil,
        userAcceptedSuggestion: false,
        aiGeneratedPercentageEstimate: nil,
        toneCheckSummary: ToneCheckSummary(
            kindnessScore: 0.88,
            clarityScore: 0.92,
            humilityScore: 0.76,
            peaceScore: 0.94,
            truthfulnessScore: 0.90,
            scriptureIntegrityScore: nil,
            shameFlagged: false,
            encouragementScore: 0.85,
            manipulationRisk: 0.04,
            pastoralSensitivity: 0.80
        ),
        disclosureRequired: false,
        rawPromptStored: false,
        rawUserTextStored: false,
        modelVersion: "claude-sonnet-4-6"
    )
    AILabelDetailSheet(label: .toneChecked, aiUsage: usage)
}
