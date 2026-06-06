// CreatorCameraSafetyScoreView.swift
// AMENAPP — Camera OS
// Creator-only private safety score: Privacy · Child Safety · Authenticity · Disclosure · Future Impact.
// Private, non-comparative, non-blocking (except Severe tier).
// Never shown to other users. Never a number to optimize. Framed as awareness + reflection.

import SwiftUI

// MARK: - CreatorCameraSafetyScore + Compute

extension CreatorCameraSafetyScore {
    /// Derives a `CreatorCameraSafetyScore` from a pre-publish scan result.
    static func compute(from scanResult: CameraPrePublishScanResult) -> CreatorCameraSafetyScore {
        let items = scanResult.detectedItems

        // Privacy axis — deduct for detected PII signals
        var privacy = 1.0
        if items.contains(.homeAddress)   { privacy -= 0.40 }
        if items.contains(.screenContent) { privacy -= 0.20 }
        if items.contains(.phoneNumber)   { privacy -= 0.20 }
        if items.contains(.badge)         { privacy -= 0.10 }
        privacy = max(0.0, min(1.0, privacy))

        // Child safety axis
        var childSafety: Double
        if !scanResult.containsMinor {
            childSafety = 1.0
        } else if scanResult.recommendedAudience == .some(.privateOnly) {
            childSafety = 0.9
        } else {
            childSafety = 0.5
        }

        let authenticity = 1.0
        let disclosure = 1.0
        let futureImpact = max(0.0, min(1.0, 1.0 - Double(items.count) * 0.08))

        return CreatorCameraSafetyScore(
            privacyScore: privacy,
            childSafetyScore: childSafety,
            authenticityScore: authenticity,
            disclosureScore: disclosure,
            futureImpactScore: futureImpact,
            computedAt: Date()
        )
    }
}

// MARK: - CreatorCameraSafetyScoreView

/// Full-screen private reflection sheet showing the creator's content safety score.
/// This view is intentionally NOT accessible from any public surface.
struct CreatorCameraSafetyScoreView: View {

    // MARK: - Props

    let score: CreatorCameraSafetyScore
    let onDismiss: () -> Void

    // MARK: - State

    @State private var isExplanationExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dark gradient backdrop to keep the glass surfaces legible
            LinearGradient(
                colors: [Color(white: 0.07), Color(white: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    overallCardSection
                    scoreAxesSection
                    explanationSection
                    Spacer(minLength: 0)
                    doneButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("Your Content Safety")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Text("Private reflection — only visible to you.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Overall Card

    private var overallCardSection: some View {
        HStack(spacing: 14) {
            overallIndicatorDot
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(score.overallLabel)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Overall safety reflection")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Overall safety: \(score.overallLabel)")
    }

    @ViewBuilder
    private var overallIndicatorDot: some View {
        Circle()
            .fill(overallDotColor)
            .frame(width: 14, height: 14)
            .shadow(color: overallDotColor.opacity(0.6), radius: 6)
    }

    private var overallDotColor: Color {
        switch score.overallLabel {
        case "Excellent":        return Color.green
        case "Good":             return Color(red: 1.0, green: 0.75, blue: 0.0) // amber
        case "Fair":             return Color.orange
        default:                 return Color.red
        }
    }

    // MARK: - Score Axes

    private var scoreAxesSection: some View {
        VStack(spacing: 14) {
            scoreRow(
                label: "Privacy",
                value: score.privacyScore,
                accessibilityHint: "How well private information is protected"
            )
            scoreRow(
                label: "Child Safety",
                value: score.childSafetyScore,
                accessibilityHint: "Safety considerations related to minors"
            )
            scoreRow(
                label: "Authenticity",
                value: score.authenticityScore,
                accessibilityHint: "How well the content origin is attested"
            )
            scoreRow(
                label: "Disclosure",
                value: score.disclosureScore,
                accessibilityHint: "Whether AI or edit labels are applied"
            )
            scoreRow(
                label: "Future Impact",
                value: score.futureImpactScore,
                accessibilityHint: "Potential long-term sharing considerations"
            )
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func scoreRow(
        label: String,
        value: Double,
        accessibilityHint: String
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 6)

                    // Fill — amber
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 1.0, green: 0.75, blue: 0.0))
                        .frame(
                            width: max(0, geo.size.width * value),
                            height: 6
                        )
                        .animation(
                            reduceMotion ? .none : .easeOut(duration: 0.5),
                            value: value
                        )
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int(value * 100)) percent")
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Explanation

    private var explanationSection: some View {
        DisclosureGroup(
            isExpanded: $isExplanationExpanded,
            content: {
                Text(
                    "This score reflects safety patterns in your recent captures. " +
                    "It's a private reflection tool, not a grade. No one else sees it."
                )
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 10)
            },
            label: {
                Text("What does this mean?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
        )
        .tint(.white)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button(action: onDismiss) {
            Text("Done")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
        .accessibilityHint("Dismisses the safety reflection sheet")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("CreatorCameraSafetyScoreView — Excellent") {
    CreatorCameraSafetyScoreView(
        score: CreatorCameraSafetyScore(
            privacyScore: 1.0,
            childSafetyScore: 1.0,
            authenticityScore: 1.0,
            disclosureScore: 1.0,
            futureImpactScore: 1.0,
            computedAt: Date()
        ),
        onDismiss: {}
    )
}

#Preview("CreatorCameraSafetyScoreView — Needs Attention") {
    CreatorCameraSafetyScoreView(
        score: CreatorCameraSafetyScore(
            privacyScore: 0.3,
            childSafetyScore: 0.5,
            authenticityScore: 1.0,
            disclosureScore: 1.0,
            futureImpactScore: 0.44,
            computedAt: Date()
        ),
        onDismiss: {}
    )
}

#Preview("compute(from:) — scan with minors + PII") {
    let scan = CameraPrePublishScanResult(
        riskLevel: .high,
        detectedItems: [.badge, .phoneNumber, .minorFace],
        redactionSuggestions: [],
        safetyProfile: .standard,
        requiresHumanReview: false,
        blocksPublish: false,
        nudgeMessage: "Some sensitive details were detected.",
        recommendedAudience: .privateOnly,
        sceneType: .church,
        containsMinor: true
    )
    let computed = CreatorCameraSafetyScore.compute(from: scan)
    CreatorCameraSafetyScoreView(score: computed, onDismiss: {})
}
#endif
