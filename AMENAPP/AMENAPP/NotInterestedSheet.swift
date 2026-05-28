// NotInterestedSheet.swift
// AMENAPP
//
// Bottom sheet shown when a user taps "Not interested" on a media item.
// Collects a structured reason, calls the `notInterestedMedia` Cloud Function,
// and tracks analytics before invoking the caller's onSubmit closure.

import FirebaseFunctions
import SwiftUI

struct NotInterestedSheet: View {

    // MARK: Inputs

    let postId: String
    let reason: NotInterestedReason?
    let onSubmit: (NotInterestedReason) -> Void
    let onDismiss: () -> Void

    // MARK: Nested Types

    enum NotInterestedReason: String, CaseIterable, Identifiable {
        case notRelevant
        case alreadySeen
        case tooLong
        case sensitiveContent
        case wrongTopic
        case dontLikeCreator

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notRelevant:      return "Not relevant to me"
            case .alreadySeen:      return "Already seen it"
            case .tooLong:          return "Too long"
            case .sensitiveContent: return "Sensitive content"
            case .wrongTopic:       return "Wrong topic"
            case .dontLikeCreator:  return "Not interested in this creator"
            }
        }

        var icon: String {
            switch self {
            case .notRelevant:      return "hand.thumbsdown"
            case .alreadySeen:      return "eye.slash"
            case .tooLong:          return "clock"
            case .sensitiveContent: return "exclamationmark.shield"
            case .wrongTopic:       return "tag.slash"
            case .dontLikeCreator:  return "person.slash"
            }
        }
    }

    // MARK: State

    @State private var selectedReason: NotInterestedReason?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Init

    init(
        postId: String,
        reason: NotInterestedReason? = nil,
        onSubmit: @escaping (NotInterestedReason) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.postId = postId
        self.reason = reason
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
        self._selectedReason = State(initialValue: reason)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            handle
                .padding(.top, 8)

            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .opacity(0.3)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(NotInterestedReason.allCases) { reasonOption in
                        reasonRow(reasonOption)
                    }

                    if let errorMessage {
                        errorBanner(errorMessage)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            actionButtons
                .padding(.horizontal, 20)
                .padding(.bottom, max(20, 0))
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.regularMaterial)
    }

    // MARK: Subviews

    private var handle: some View {
        Capsule()
            .fill(Color(.tertiaryLabel))
            .frame(width: 36, height: 4)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Why aren't you interested?")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Your feedback improves your feed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Cancel")
        }
    }

    private func reasonRow(_ option: NotInterestedReason) -> some View {
        let isSelected = selectedReason == option
        return Button {
            if reduceMotion {
                selectedReason = option
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedReason = option
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                Text(option.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiaryLabel)))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Done
            Button {
                guard let chosen = selectedReason else { return }
                submit(reason: chosen)
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Done")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(selectedReason != nil ? Color.accentColor : Color(.tertiarySystemFill))
                )
                .foregroundStyle(selectedReason != nil ? .white : Color(.tertiaryLabel))
            }
            .buttonStyle(.plain)
            .disabled(selectedReason == nil || isSubmitting)
            .accessibilityLabel("Submit feedback")

            // Cancel
            Button(action: onDismiss) {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 12)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color(.systemRed))
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color(.systemRed))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemRed).opacity(0.08))
        )
    }

    // MARK: Submission

    private func submit(reason: NotInterestedReason) {
        isSubmitting = true
        errorMessage = nil

        AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "not_interested"))

        Task {
            do {
                _ = try await Functions.functions().httpsCallable("notInterestedMedia").call([
                    "postId": postId,
                    "reason": reason.rawValue
                ])
                onSubmit(reason)
            } catch {
                errorMessage = "Something went wrong. Please try again."
            }
            isSubmitting = false
        }
    }
}
