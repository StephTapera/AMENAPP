// TimestampedCommentComposer.swift
// AMENAPP
//
// Compact bottom-sheet composer for leaving a comment tied to a specific
// video timestamp, carousel slide index, or scripture reference.
//
// Gated: AMENFeatureFlags.shared.mediaTimestampedCommentsEnabled

import SwiftUI

// MARK: - TimestampedCommentTarget

/// Identifies the media anchor point a comment is attached to.
enum TimestampedCommentTarget: Equatable {
    case videoTime(seconds: TimeInterval)
    case carouselIndex(index: Int)
    case scriptureRef(reference: String)
    case keyMoment(id: String, label: String)
}

// MARK: - TimestampedCommentTarget Formatting

extension TimestampedCommentTarget {

    /// Human-readable label shown in the glass pill, e.g. "At 1:40" or "On slide 3".
    var displayLabel: String {
        switch self {
        case .videoTime(let seconds):
            return "At \(formattedTime(seconds))"
        case .carouselIndex(let index):
            return "On slide \(index + 1)"
        case .scriptureRef(let reference):
            return "On \(reference)"
        case .keyMoment(_, let label):
            return "At \(label) moment"
        }
    }

    /// Accessibility-friendly version of the same label.
    var accessibilityLabel: String { displayLabel }

    /// Formats a raw TimeInterval into "M:SS" or "H:MM:SS" string.
    private func formattedTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - TimestampedCommentComposer

/// Compact bottom-sheet style composer for a timestamped comment.
///
/// Present this inside a `.sheet` or inline above the keyboard.
/// The view is entirely self-contained: it owns its text state and
/// delegates results via `onSubmit` / `onCancel`.
struct TimestampedCommentComposer: View {

    // MARK: Inputs

    let postId: String
    let mediaId: String
    let target: TimestampedCommentTarget
    /// Called with the trimmed comment text and the original target on submit.
    let onSubmit: (String, TimestampedCommentTarget) -> Void
    let onCancel: () -> Void

    // MARK: Constants

    private let characterLimit = 280

    // MARK: State

    @State private var text: String = ""
    @State private var isSubmitting: Bool = false
    @FocusState private var fieldFocused: Bool

    // MARK: Derived

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { !trimmed.isEmpty && !isSubmitting }
    private var remaining: Int { characterLimit - text.count }
    private var isOverLimit: Bool { text.count > characterLimit }

    // MARK: Body

    var body: some View {
        guard AMENFeatureFlags.shared.mediaTimestampedCommentsEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(composerContent)
    }

    // MARK: Composer Content

    private var composerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            anchorPill
            inputRow
            footerRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color(.systemBackground))
        .onAppear { fieldFocused = true }
    }

    // MARK: Anchor Pill

    private var anchorPill: some View {
        Text(target.displayLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityLabel("Comment anchor: \(target.accessibilityLabel)")
    }

    // MARK: Input Row

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            textField
            submitButton
        }
    }

    private var textField: some View {
        TextField("Add a comment…", text: $text, axis: .vertical)
            .font(.body)
            .lineLimit(1...3)
            .focused($fieldFocused)
            .onChange(of: text) { _, newValue in
                // Hard-cap at characterLimit to prevent over-entry
                if newValue.count > characterLimit {
                    text = String(newValue.prefix(characterLimit))
                }
            }
            .accessibilityLabel("Comment text field")
            .accessibilityHint("Type your timestamped comment here")
    }

    // MARK: Submit Button

    private var submitButton: some View {
        Button {
            submitComment()
        } label: {
            Group {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.primary)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(canSubmit ? .primary : .tertiary)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityLabel("Submit comment")
        .animation(.easeInOut(duration: 0.15), value: canSubmit)
    }

    // MARK: Footer Row

    private var footerRow: some View {
        HStack {
            Button {
                fieldFocused = false
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .accessibilityLabel("Cancel comment")

            Spacer()

            Text("\(remaining)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(isOverLimit ? .red : .secondary)
                .accessibilityLabel("\(remaining) characters remaining")
        }
    }

    // MARK: Submit

    private func submitComment() {
        let finalText = trimmed
        guard !finalText.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        fieldFocused = false
        AMENAnalyticsService.shared.track(
            .feedMeaningfulInteraction(type: "timestamped_comment")
        )
        onSubmit(finalText, target)
        // Reset state — caller is responsible for dismissal if desired
        text = ""
        isSubmitting = false
    }
}
