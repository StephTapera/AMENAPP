// BereanFeedbackView.swift
// AMENAPP
//
// Trust Layer 4 — Compact inline multi-select feedback strip for Berean AI responses.
// Collapsed state: icon-only chip row. Expanded state: labeled chips with multi-select.
// "Unsafe" or "Misleading" selections trigger GUARDIAN review via bereanReportUnsafe CF.
// All ratings write to Firestore: berean_feedback/{auto-id}.
// Feature flag: berean_feedback_enabled (default true for beta).
// No force-unwrap. Reduce Motion honored. Dynamic Type honored.

import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth
import FirebaseRemoteConfig

// MARK: - BereanFeedbackRating

/// Rating options for a Berean AI response. Distinct from BereanFeedbackOption
/// (single-select sheet variant) — this enum drives the multi-select inline strip.
enum BereanFeedbackRating: String, CaseIterable, Identifiable {
    case accurate       = "Accurate"
    case inaccurate     = "Inaccurate"
    case helpful        = "Helpful"
    case misleading     = "Misleading"
    case missingContext = "Missing Context"
    case biased         = "Biased"
    case unsafe         = "Unsafe"
    case excellent      = "Excellent"

    var id: String { rawValue }

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
        case .excellent:      return Color(red: 0.95, green: 0.77, blue: 0.06)
        }
    }

    /// True for ratings that route to the GUARDIAN trust-and-safety queue.
    var isHighRisk: Bool { self == .unsafe || self == .misleading }
}

// MARK: - BereanFeedbackView

/// Compact inline feedback strip. Renders as a collapsed icon row by default;
/// expands to labeled chips on tap. Supports multi-select. Unsafe/Misleading
/// selections immediately trigger GUARDIAN review and show a disclosure banner.
struct BereanFeedbackView: View {

    // MARK: Public inputs

    /// The trace ID of the Berean response being rated.
    let traceId: String
    /// Authenticated user ID. Pass Auth.auth().currentUser?.uid ?? "".
    let userId: String

    // MARK: State

    @State private var isExpanded: Bool = false
    @State private var selectedRatings: Set<BereanFeedbackRating> = []
    @State private var isSubmitting: Bool = false
    @State private var submitted: Bool = false
    @State private var showGuardianBanner: Bool = false
    @State private var submitError: String? = nil

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Feature flag

    private var feedbackEnabled: Bool {
        let rc = RemoteConfig.remoteConfig()
        let val = rc.configValue(forKey: "berean_feedback_enabled")
        // Default true for beta: if no remote value is set the raw string is "",
        // so we treat missing as true.
        guard val.source != .default || !val.stringValue.isEmpty else { return true }
        return val.boolValue
    }

    // MARK: Body

    var body: some View {
        guard feedbackEnabled else { return AnyView(EmptyView()) }
        return AnyView(content)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if submitted {
                submittedConfirmation
            } else {
                feedbackStrip
            }
        }
    }

    // MARK: - Feedback Strip

    private var feedbackStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Toggle row: collapsed icon strip or labeled chips
            if isExpanded {
                expandedChips
            } else {
                collapsedIcons
            }

            // GUARDIAN banner
            if showGuardianBanner {
                guardianBanner
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            // Submit row (visible when expanded and at least one rating selected)
            if isExpanded && !selectedRatings.isEmpty {
                submitRow
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }

            // Inline error (best-effort; non-blocking)
            if let err = submitError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.8))
                    .dynamicTypeSize(.small ... .accessibility2)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: selectedRatings)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showGuardianBanner)
    }

    // MARK: - Collapsed Icon Strip

    private var collapsedIcons: some View {
        HStack(spacing: 4) {
            ForEach(BereanFeedbackRating.allCases) { rating in
                Button {
                    expandAndSelect(rating)
                } label: {
                    Image(systemName: rating.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            selectedRatings.contains(rating)
                                ? rating.color
                                : Color(.tertiaryLabel)
                        )
                        .frame(width: 26, height: 26)
                        .background(
                            selectedRatings.contains(rating)
                                ? rating.color.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rating.rawValue)
                .accessibilityHint(
                    selectedRatings.contains(rating)
                        ? "Selected. Double-tap to deselect."
                        : "Double-tap to select this rating."
                )
                .accessibilityAddTraits(.isButton)
            }

            Spacer(minLength: 4)

            // Chevron to expand
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded = true
                }
            } label: {
                Image(systemName: "chevron.right.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand feedback options")
            .accessibilityHint("Double-tap to see labeled rating chips.")
        }
    }

    // MARK: - Expanded Labeled Chips

    private var expandedChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rate this response")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(.small ... .accessibility2)

                Spacer(minLength: 4)

                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.up.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse feedback options")
            }

            // 2-column adaptive chip grid
            let columns: [GridItem] = [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ]

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(BereanFeedbackRating.allCases) { rating in
                    LabeledFeedbackChip(
                        rating: rating,
                        isSelected: selectedRatings.contains(rating),
                        reduceMotion: reduceMotion
                    ) {
                        toggle(rating)
                    }
                }
            }
        }
    }

    // MARK: - GUARDIAN Banner

    private var guardianBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Thank you — this is being reviewed by our trust & safety team.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(.small ... .accessibility2)
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
        .accessibilityLabel("This rating has been flagged for trust and safety review. Thank you.")
    }

    // MARK: - Submit Row

    private var submitRow: some View {
        Button {
            Task { await submitFeedback() }
        } label: {
            HStack(spacing: 6) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.75)
                        .tint(.white)
                } else {
                    Text("Submit")
                        .font(.caption.weight(.semibold))
                        .dynamicTypeSize(.small ... .accessibility2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.indigo, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .accessibilityLabel(isSubmitting ? "Submitting feedback" : "Submit feedback")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Submitted Confirmation

    private var submittedConfirmation: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Feedback received")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .dynamicTypeSize(.small ... .accessibility2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feedback submitted. Thank you.")
    }

    // MARK: - Actions

    private func expandAndSelect(_ rating: BereanFeedbackRating) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded = true
        }
        toggle(rating)
    }

    private func toggle(_ rating: BereanFeedbackRating) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7)) {
            if selectedRatings.contains(rating) {
                selectedRatings.remove(rating)
            } else {
                selectedRatings.insert(rating)
            }
        }
        // Show GUARDIAN banner whenever a high-risk rating is in the selection set
        let hasHighRisk = selectedRatings.contains { $0.isHighRisk }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            showGuardianBanner = hasHighRisk
        }
        // Immediately call GUARDIAN CF on high-risk selection (best-effort)
        if rating.isHighRisk && selectedRatings.contains(rating) {
            Task { await reportUnsafe(rating: rating) }
        }
    }

    // MARK: - Async Operations

    /// Writes feedback to Firestore and submits to GUARDIAN if needed.
    private func submitFeedback() async {
        guard !selectedRatings.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        submitError = nil

        let ratings = selectedRatings.map(\.rawValue)
        let payload: [String: Any] = [
            "ratings": ratings,
            "traceId": traceId,
            "userId": userId.isEmpty ? (Auth.auth().currentUser?.uid ?? "anonymous") : userId,
            "timestamp": FieldValue.serverTimestamp()
        ]

        do {
            try await Firestore.firestore()
                .collection("berean_feedback")
                .addDocument(data: payload)
        } catch {
            // Best-effort — log but do not block submission UX
            print("[BereanFeedbackView] Firestore write failed: \(error.localizedDescription)")
            submitError = "Could not save feedback. Please try again."
            isSubmitting = false
            return
        }

        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
            submitted = true
            isSubmitting = false
        }
    }

    /// Calls bereanReportUnsafe Cloud Function for high-risk ratings (best-effort).
    private func reportUnsafe(rating: BereanFeedbackRating) async {
        let payload: [String: Any] = [
            "rating": rating.rawValue,
            "traceId": traceId,
            "userId": userId.isEmpty ? (Auth.auth().currentUser?.uid ?? "anonymous") : userId,
        ]
        do {
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("bereanReportUnsafe")
                .call(payload)
        } catch {
            // Best-effort — silently log
            print("[BereanFeedbackView] bereanReportUnsafe CF failed (silently): \(error.localizedDescription)")
        }
    }
}

// MARK: - LabeledFeedbackChip

/// A single labeled chip for the expanded multi-select grid.
private struct LabeledFeedbackChip: View {
    let rating: BereanFeedbackRating
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: rating.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? rating.color : Color(.secondaryLabel))
                    .symbolRenderingMode(.hierarchical)

                Text(rating.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? rating.color : Color(.secondaryLabel))
                    .dynamicTypeSize(.xSmall ... .accessibility1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                isSelected
                    ? rating.color.opacity(0.12)
                    : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isSelected ? rating.color.opacity(0.5) : Color(.separator).opacity(0.35),
                        lineWidth: isSelected ? 1.0 : 0.5
                    )
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rating.rawValue)
        .accessibilityHint(isSelected ? "Selected. Double-tap to deselect." : "Double-tap to select this rating.")
        .accessibilityAddTraits(.isButton)
        .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Previews

#Preview("Collapsed strip") {
    VStack(alignment: .leading, spacing: 16) {
        Text("Berean response text would appear here.")
            .font(.body)
            .foregroundStyle(.primary)

        BereanFeedbackView(traceId: "preview-trace-001", userId: "preview-user-001")
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}

#Preview("Expanded strip") {
    @Previewable @State var view = BereanFeedbackView(traceId: "preview-trace-002", userId: "preview-user-002")

    VStack(alignment: .leading, spacing: 16) {
        Text("Berean response text would appear here.")
            .font(.body)
            .foregroundStyle(.primary)

        BereanFeedbackView(traceId: "preview-trace-002", userId: "preview-user-002")
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
