// TestimonyAssistView.swift
// AMEN App — Testimony Integrity + Story Assist (Agent 3)
//
// Helps the user structure their testimony with integrity.
// Voice-to-testimony (reuses existing VoicePrayerAudioEngine),
// refinement suggestions (grammar/clarity ONLY, user approves each),
// sensitive-detail advisory, audience controls, and Berean scripture connections.

import SwiftUI

// MARK: - Assist Step

private enum TestimonyAssistStep: Int, CaseIterable {
    case input       = 0   // enter or record
    case refine      = 1   // review Berean suggestions
    case audience    = 2   // set visibility
    case review      = 3   // final review before publish
}

// MARK: - Main View

struct TestimonyAssistView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called when the user finalizes and is ready to publish the testimony draft.
    let onFinalize: (TestimonyAssistDraft) -> Void

    @StateObject private var service = TestimonyIntegrityService.shared

    @State private var draft = TestimonyAssistDraft(transcript: "")
    @State private var step: TestimonyAssistStep = .input
    @State private var refinements: [TestimonyRefinementSuggestion] = []
    @State private var theme: String = ""
    @State private var suggestedScriptures: [String] = []
    @State private var captionOptions: [String] = []
    @State private var showScripturesSuggestion = false
    @State private var showSensitiveAdvisory = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()

                switch step {
                case .input:
                    inputStep
                case .refine:
                    refineStep
                case .audience:
                    audienceStep
                case .review:
                    reviewStep
                }
            }
            .navigationTitle("Testimony Assist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(TestimonyAssistStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue
                          ? Color(red: 0.56, green: 0.40, blue: 0.85)
                          : Color(uiColor: .systemGray5))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.3), value: step)
            }
        }
    }

    // MARK: - Step 1: Input

    private var inputStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Share Your Testimony")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .padding(.top, 16)

                Text("Type or paste your testimony. Your voice will be preserved — Berean only helps with grammar and structure, never changes your meaning.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $draft.editedText)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .frame(minHeight: 180)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
                    )

                // Integrity reminder
                Label("Berean will only suggest grammar and clarity improvements. Nothing is changed without your approval.", systemImage: "checkmark.shield")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)

                nextButton(label: "Get Suggestions", disabled: draft.editedText.trimmingCharacters(in: .whitespacesAndNewlines).count < 20) {
                    Task { await loadRefinements() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Step 2: Refine

    private var refineStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review Suggestions")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .padding(.top, 16)

                if service.isProcessing {
                    HStack {
                        Spacer()
                        ProgressView("Analyzing…")
                        Spacer()
                    }
                    .padding(.vertical, 24)

                } else if refinements.isEmpty {
                    Label("Your testimony reads clearly — no suggestions needed.", systemImage: "checkmark.circle.fill")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(Color.green)
                        .padding(.vertical, 12)

                } else {
                    ForEach($refinements) { $suggestion in
                        if !suggestion.accepted && !suggestion.rejected {
                            RefinementCard(suggestion: $suggestion)
                        }
                    }
                }

                // Scripture suggestions (dismissible, labeled)
                if !suggestedScriptures.isEmpty {
                    DisclosureGroup(isExpanded: $showScripturesSuggestion) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(suggestedScriptures, id: \.self) { ref in
                                HStack(spacing: 6) {
                                    Image(systemName: "book.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(red: 0.16, green: 0.40, blue: 0.76))
                                    Text(ref)
                                        .font(.custom("OpenSans-Regular", size: 14))
                                }
                            }
                            Text("These are Berean suggestions — not spiritual authority.")
                                .font(.custom("OpenSans-Regular", size: 11))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                .italic()
                        }
                        .padding(.top, 6)
                    } label: {
                        Label("Scripture Connections (\(suggestedScriptures.count))", systemImage: "book.fill")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(Color(red: 0.16, green: 0.40, blue: 0.76))
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                nextButton(label: "Set Audience") {
                    applyAcceptedRefinements()
                    step = .audience
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Step 3: Audience

    private var audienceStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Who Should See This?")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .padding(.top, 16)

                Text("Your testimony audience. You can always change this later.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)

                ForEach(TestimonyAudience.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            draft.audience = option
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: option.systemIcon)
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 28)
                                .foregroundStyle(draft.audience == option
                                    ? Color(red: 0.56, green: 0.40, blue: 0.85)
                                    : Color(uiColor: .secondaryLabel))

                            Text(option.displayName)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.primary)

                            Spacer()

                            if draft.audience == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(red: 0.56, green: 0.40, blue: 0.85))
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(draft.audience == option
                                    ? Color(red: 0.56, green: 0.40, blue: 0.85).opacity(0.08)
                                    : Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    draft.audience == option
                                        ? Color(red: 0.56, green: 0.40, blue: 0.85).opacity(0.4)
                                        : Color(uiColor: .separator).opacity(0.3),
                                    lineWidth: 0.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                nextButton(label: "Review Testimony") {
                    step = .review
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Step 4: Final Review

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Review Your Testimony")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .padding(.top, 16)

                // Caption options
                if !captionOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Caption Ideas")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)

                        ForEach(captionOptions.prefix(3), id: \.self) { caption in
                            Text("\"\(caption)\"")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                                .italic()
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                // Final text
                Text(draft.editedText)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.primary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                // Audience chip
                HStack(spacing: 6) {
                    Image(systemName: draft.audience.systemIcon)
                    Text(draft.audience.displayName)
                }
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)

                // Sensitive detail advisory (if any detected)
                if !draft.sensitiveFlags.filter({ !$0.isDismissed }).isEmpty {
                    SensitiveDetailAdvisoryBanner(flags: draft.sensitiveFlags)
                }

                Button {
                    onFinalize(draft)
                    dismiss()
                } label: {
                    Text("Share Testimony")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color(red: 0.56, green: 0.40, blue: 0.85), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Helpers

    private func nextButton(label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(disabled ? Color(uiColor: .tertiaryLabel) : .white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    disabled
                        ? AnyShapeStyle(Color(uiColor: .systemGray5))
                        : AnyShapeStyle(Color(red: 0.56, green: 0.40, blue: 0.85)),
                    in: RoundedRectangle(cornerRadius: 14)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func loadRefinements() async {
        draft.editedText = draft.editedText
        // Sync raw transcript from first entry
        if draft.rawTranscript.isEmpty { draft.rawTranscript = draft.editedText }

        do {
            refinements = try await service.requestRefinements(for: draft)
            let (t, s, c) = try await service.suggestThemeAndScripture(for: draft)
            theme = t
            suggestedScriptures = s
            captionOptions = c
            draft.suggestedScriptures = s
            draft.captionOptions = c
            step = .refine
        } catch {
            refinements = []
            step = .refine
        }
    }

    private func applyAcceptedRefinements() {
        var text = draft.editedText
        for suggestion in refinements where suggestion.accepted {
            text = text.replacingOccurrences(of: suggestion.original, with: suggestion.suggested)
        }
        draft.editedText = text
    }
}

// MARK: - Refinement Card

private struct RefinementCard: View {
    @Binding var suggestion: TestimonyRefinementSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(suggestion.reason.capitalized, systemImage: "pencil.line")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text("Original: \"\(suggestion.original)\"")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
            Text("Suggestion: \"\(suggestion.suggested)\"")
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        suggestion.accepted = true
                    }
                } label: {
                    Text("Accept")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.16, green: 0.40, blue: 0.76), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        suggestion.rejected = true
                    }
                } label: {
                    Text("Keep Mine")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .systemGray5), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
        )
    }
}

// MARK: - Sensitive Detail Advisory Banner

private struct SensitiveDetailAdvisoryBanner: View {
    let flags: [SensitiveDetailFlag]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Review Before Sharing", systemImage: "shield.lefthalf.filled")
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.orange)

            Text("Your testimony may contain sensitive details. Review them before sharing publicly.")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
    }
}
