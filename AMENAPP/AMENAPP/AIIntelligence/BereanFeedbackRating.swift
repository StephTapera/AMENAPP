// BereanFeedbackRating.swift
// AMENAPP
//
// Layer 4 feedback loop: in-app response rating UI for Berean AI responses.
// Unsafe and Misleading ratings trigger GUARDIAN review (handled backend via
// the bereanSubmitFeedback callable). Liquid Glass design. Respects Reduce Motion
// and Dynamic Type throughout.

import SwiftUI

// MARK: - BereanFeedbackOption

/// All rating options a user may apply to a Berean response.
enum BereanFeedbackOption: String, CaseIterable, Identifiable {
    case accurate
    case inaccurate
    case helpful
    case misleading
    case missingContext
    case biased
    case unsafe
    case excellent

    var id: String { rawValue }

    // MARK: Display

    var label: String {
        switch self {
        case .accurate:       return "Accurate"
        case .inaccurate:     return "Inaccurate"
        case .helpful:        return "Helpful"
        case .misleading:     return "Misleading"
        case .missingContext: return "Missing Context"
        case .biased:         return "Biased"
        case .unsafe:         return "Unsafe"
        case .excellent:      return "Excellent"
        }
    }

    var icon: String {
        switch self {
        case .accurate:       return "checkmark"
        case .inaccurate:     return "xmark"
        case .helpful:        return "hand.thumbsup"
        case .misleading:     return "exclamationmark.triangle"
        case .missingContext: return "questionmark.circle"
        case .biased:         return "scale.3d"
        case .unsafe:         return "shield.slash"
        case .excellent:      return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .accurate:       return .green
        case .inaccurate:     return .red
        case .helpful:        return .green
        case .misleading:     return .red
        case .missingContext: return .orange
        case .biased:         return .orange
        case .unsafe:         return .red
        case .excellent:      return .yellow
        }
    }

    /// True for ratings that indicate a problematic response.
    var isNegative: Bool {
        switch self {
        case .inaccurate, .misleading, .biased, .unsafe: return true
        default: return false
        }
    }

    /// True for ratings that require GUARDIAN trust-and-safety review.
    var requiresGuardianReview: Bool {
        self == .unsafe || self == .misleading
    }
}

// MARK: - BereanFeedbackRatingView

/// Full feedback sheet allowing users to select a rating, optionally add a
/// comment (surfaced for negative ratings), and submit.
struct BereanFeedbackRatingView: View {

    @Binding var selectedRating: BereanFeedbackOption?
    @State var comment: String = ""
    @State var isSubmitting = false
    @State var submitted = false

    let traceId: String
    /// Called with the chosen rating and optional comment once the user taps Submit.
    let onSubmit: (BereanFeedbackOption, String?) async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Layout constants

    private let gridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        if submitted {
            successView
        } else {
            ratingForm
        }
    }

    // MARK: - Rating Form

    private var ratingForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            Text("How was this response?")
                .font(.headline)
                .foregroundStyle(.primary)
                .dynamicTypeSize(.small ... .accessibility3)
                .padding(.horizontal, 4)

            // 4 × 2 grid of rating chips
            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(BereanFeedbackOption.allCases) { option in
                    RatingChip(
                        option: option,
                        isSelected: selectedRating == option,
                        reduceMotion: reduceMotion
                    ) {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75)) {
                            selectedRating = (selectedRating == option) ? nil : option
                        }
                    }
                }
            }

            // GUARDIAN disclosure (shown when unsafe or misleading is selected)
            if let rating = selectedRating, rating.requiresGuardianReview {
                guardianDisclosure
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            // Optional comment field (negative ratings only)
            if let rating = selectedRating, rating.isNegative {
                commentField
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            // Submit button
            submitButton
        }
        .padding(.horizontal, 4)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: selectedRating)
    }

    // MARK: - GUARDIAN Disclosure

    private var guardianDisclosure: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            Text("This will be reviewed by our trust & safety team.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(.small ... .accessibility3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This rating will be reviewed by our trust and safety team.")
    }

    // MARK: - Comment Field

    private var commentField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tell us more (optional)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .dynamicTypeSize(.small ... .accessibility3)

            TextField("Add details about your rating…", text: $comment, axis: .vertical)
                .lineLimit(3...5)
                .font(.subheadline)
                .dynamicTypeSize(.small ... .accessibility3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
                .accessibilityLabel("Optional comment. Tell us more about your rating.")
        }
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            guard let rating = selectedRating, !isSubmitting else { return }
            Task {
                isSubmitting = true
                let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                await onSubmit(rating, trimmed.isEmpty ? nil : trimmed)
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                    submitted = true
                    isSubmitting = false
                }
            }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.85)
                        .tint(.white)
                } else {
                    Text("Submit Feedback")
                        .font(.subheadline.weight(.semibold))
                        .dynamicTypeSize(.small ... .accessibility3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                selectedRating == nil
                    ? Color(.systemFill)
                    : Color.indigo,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .foregroundStyle(selectedRating == nil ? Color(.secondaryLabel) : .white)
        }
        .disabled(selectedRating == nil || isSubmitting)
        .buttonStyle(.plain)
        .accessibilityLabel(isSubmitting ? "Submitting feedback" : "Submit feedback")
        .accessibilityAddTraits(selectedRating == nil ? [.isButton] : [.isButton])
    }

    // MARK: - Success State

    private var successView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Thank you for your feedback")
                .font(.headline)
                .foregroundStyle(.primary)
                .dynamicTypeSize(.small ... .accessibility3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feedback submitted. Thank you for your feedback.")
    }
}

// MARK: - RatingChip

/// Individual rating chip with icon and label. Highlights with the option's color when selected.
private struct RatingChip: View {
    let option: BereanFeedbackOption
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: option.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? option.color : Color(.secondaryLabel))
                    .symbolRenderingMode(.hierarchical)

                Text(option.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? option.color : Color(.secondaryLabel))
                    .dynamicTypeSize(.xSmall ... .accessibility1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? option.color.opacity(0.12)
                    : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? option.color.opacity(0.5) : Color(.separator).opacity(0.4),
                        lineWidth: isSelected ? 1.0 : 0.5
                    )
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityHint(isSelected ? "Selected. Double-tap to deselect." : "Double-tap to select this rating.")
        .accessibilityAddTraits(.isButton)
        .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - BereanFeedbackButton

/// Compact inline "Rate this response" button. Presents `BereanFeedbackRatingView` as a sheet.
struct BereanFeedbackButton: View {

    @State private var showFeedback = false
    @State private var submitted = false
    @State private var selectedRating: BereanFeedbackOption? = nil

    let traceId: String
    let userId: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            guard !submitted else { return }
            showFeedback = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: submitted ? "checkmark.circle.fill" : "hand.thumbsup")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(submitted ? .green : Color(.secondaryLabel))

                Text(submitted ? "Rated" : "Rate this response")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(submitted ? .green : Color(.secondaryLabel))
                    .dynamicTypeSize(.xSmall ... .accessibility1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                submitted
                    ? Color.green.opacity(0.08)
                    : Color(.secondarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    submitted ? Color.green.opacity(0.3) : Color(.separator).opacity(0.4),
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(submitted)
        .accessibilityLabel(submitted ? "Response rated" : "Rate this response")
        .accessibilityHint(submitted ? "" : "Double-tap to open feedback rating sheet.")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet(
                showFeedback: $showFeedback,
                submitted: $submitted,
                selectedRating: $selectedRating,
                traceId: traceId,
                userId: userId,
                reduceMotion: reduceMotion
            )
        }
    }
}

// MARK: - FeedbackSheet (internal helper)

/// Sheet wrapper that owns the submit logic, keeping `BereanFeedbackButton` lightweight.
private struct FeedbackSheet: View {

    @Binding var showFeedback: Bool
    @Binding var submitted: Bool
    @Binding var selectedRating: BereanFeedbackOption?

    let traceId: String
    let userId: String
    let reduceMotion: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                BereanFeedbackRatingView(
                    selectedRating: $selectedRating,
                    traceId: traceId,
                    onSubmit: handleSubmit
                )
                .padding(20)
            }
            .navigationTitle("Rate Response")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showFeedback = false
                    }
                    .accessibilityLabel("Cancel feedback")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
    }

    private func handleSubmit(_ rating: BereanFeedbackOption, _ comment: String?) async {
        await BereanConstitutionalPipeline.shared.submitFeedback(
            rating: rating.rawValue,
            comment: comment
        )
        submitted = true
        // Small delay so the user sees the success state before the sheet dismisses.
        try? await Task.sleep(nanoseconds: 900_000_000)
        showFeedback = false
    }
}

// MARK: - BereanResponseFooter

/// Reusable footer row to append below any Berean response bubble.
/// Composes: BereanFeedbackButton + EvidenceChipButton + TrustBadgeRow.
struct BereanResponseFooter: View {

    let traceId: String
    let evidence: [EvidenceChunk]
    let trustScore: Double
    let confidence: String
    let userId: String

    private var trustLevel: BereanResponseTrustLevel {
        BereanResponseTrustLevel.from(score: trustScore)
    }

    private var trustExplanation: String {
        switch trustLevel {
        case .verified:
            return "Multiple cross-referenced sources confirm this response."
        case .mostlyVerified:
            return "Mainstream consensus with minor variance across traditions noted."
        case .partiallyVerified:
            return "Some supporting evidence; competing interpretations exist."
        case .unverified:
            return "Insufficient scriptural support found; treat with discernment."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Trust badge row
            TrustBadgeRow(
                trustLevel: trustLevel,
                score: trustScore,
                explanation: trustExplanation
            )

            // Evidence chip + feedback button on the same row
            HStack(spacing: 8) {
                EvidenceChipButton(
                    evidence: evidence,
                    confidence: confidence,
                    traceId: traceId
                )

                BereanFeedbackButton(
                    traceId: traceId,
                    userId: userId
                )

                Spacer(minLength: 0)
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Previews

#Preview("Rating View — Interactive") {
    @Previewable @State var rating: BereanFeedbackOption? = nil

    NavigationStack {
        ScrollView {
            BereanFeedbackRatingView(
                selectedRating: $rating,
                traceId: "preview-trace-abc123",
                onSubmit: { selectedRating, comment in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    print("Submitted: \(selectedRating.rawValue), comment: \(comment ?? "none")")
                }
            )
            .padding(20)
        }
        .navigationTitle("Rate Response")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Feedback Button") {
    VStack(spacing: 24) {
        Text("Berean response text goes here…")
            .font(.body)
            .foregroundStyle(.primary)

        BereanFeedbackButton(
            traceId: "preview-trace-abc123",
            userId: "preview-user-001"
        )
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}

#Preview("Response Footer") {
    let sampleEvidence: [EvidenceChunk] = [
        EvidenceChunk(
            id: "e1",
            citation: "John 3:16",
            content: "For God so loved the world that he gave his one and only Son.",
            source: "scripture"
        ),
        EvidenceChunk(
            id: "e2",
            citation: "Westminster Confession, Ch. 3",
            content: "God from all eternity did freely and unchangeably ordain whatsoever comes to pass.",
            source: "theology"
        ),
    ]

    VStack(alignment: .leading, spacing: 0) {
        Text("This response reflects the mainstream Reformed understanding of God's sovereignty…")
            .font(.body)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        BereanResponseFooter(
            traceId: "preview-trace-xyz789",
            evidence: sampleEvidence,
            trustScore: 0.84,
            confidence: "High Confidence",
            userId: "preview-user-001"
        )
        .padding(.top, 8)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
