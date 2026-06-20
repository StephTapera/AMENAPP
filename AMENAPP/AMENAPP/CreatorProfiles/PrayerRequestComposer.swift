// PrayerRequestComposer.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3 UI
//
// Compose a prayer request for a creator's moderated prayer board.
//
// CRITICAL HONESTY: every submission is moderated server-side before it becomes public.
// After a successful submit we show a clear "Pending review — not yet public" confirmation.
// We NEVER echo the just-submitted request back as if it were live on the public board.
//
// Conventions: white bg / black text; single translucent glass input area (no glass-on-glass);
// AmenTheme.Colors.* tokens; Dynamic Type; VoiceOver labels; reduce-motion safe.

import SwiftUI

struct PrayerRequestComposer: View {
    let creatorId: String
    /// Called after a successful submit so the host can dismiss / refresh.
    var onSubmitted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var body_: String = ""
    @State private var isPrivate = false
    @State private var phase: Phase = .editing
    @State private var errorMessage: String?

    private enum Phase: Equatable { case editing, submitting, submitted }

    private var trimmed: String {
        body_.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .editing, .submitting: editor
                case .submitted:            pendingConfirmation
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle("Request prayer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .submitted ? "Done" : "Cancel") { dismiss() }
                        .accessibilityLabel(phase == .submitted ? "Done" : "Cancel")
                }
            }
        }
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share what you'd like prayer for")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            TextEditor(text: $body_)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(10)
                .amenGlassInputBar(cornerRadius: 16)
                .accessibilityLabel("Prayer request")
                .accessibilityHint("Describe what you would like prayer for.")

            Toggle(isOn: $isPrivate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep private")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("Only the ministry sees private requests.")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
            .tint(AmenTheme.Colors.amenGoldText)
            .accessibilityLabel("Keep private")
            .accessibilityHint("When on, only the ministry sees this request.")

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(AmenTheme.Colors.statusError)
                    .accessibilityLabel("Error. \(errorMessage)")
            }

            // Honest expectation set BEFORE submit too.
            Label("Requests are reviewed before they appear publicly.",
                  systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            Spacer(minLength: 0)

            submitButton
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                Spacer()
                if phase == .submitting {
                    ProgressView().tint(AmenTheme.Colors.buttonPrimaryText)
                } else {
                    Text("Submit for review")
                        .font(.headline)
                }
                Spacer()
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AmenTheme.Colors.buttonPrimary.opacity(trimmed.isEmpty ? 0.4 : 1))
        )
        .disabled(trimmed.isEmpty || phase == .submitting)
        .accessibilityLabel("Submit prayer request for review")
    }

    // MARK: Pending confirmation (honest)

    private var pendingConfirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(AmenTheme.Colors.statusSuccess)

            Text("Pending review — not yet public")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text(isPrivate
                 ? "Your private request was sent to the ministry. It will not appear on the public board."
                 : "Thank you. Your request was received and will appear on the board once it's reviewed and approved.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onSubmitted()
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AmenTheme.Colors.buttonPrimary)
            )
            .padding(.top, 8)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pending review. Not yet public.")
    }

    // MARK: Submit

    private func submit() async {
        guard !trimmed.isEmpty else { return }
        phase = .submitting
        errorMessage = nil
        do {
            try await CreatorHubService.shared.submitPrayer(
                creatorId: creatorId, body: trimmed, isPrivate: isPrivate
            )
            phase = .submitted
        } catch {
            phase = .editing
            errorMessage = "Couldn't submit your request. Please try again."
        }
    }
}

#if DEBUG
#Preview("PrayerRequestComposer") {
    PrayerRequestComposer(creatorId: "demo")
}
#endif
