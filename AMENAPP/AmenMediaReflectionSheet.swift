// AmenMediaReflectionSheet.swift
// AMENAPP
//
// Private reflection sheet for immersive media sessions.
// Users reflect privately, save to journal, or share with their community.
// Gated by AMENFeatureFlags.shared.mediaReflectionSheetEnabled.

import FirebaseFunctions
import SwiftUI

// MARK: - MediaReflectionVisibility

enum MediaReflectionVisibility: String, CaseIterable, Identifiable {
    case onlyMe       = "only_me"
    case closeCircle  = "close_circle"
    case community    = "community"
    case creatorOnly  = "creator_only"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onlyMe:      return "Only me"
        case .closeCircle: return "Close circle"
        case .community:   return "Community"
        case .creatorOnly: return "Creator only"
        }
    }

    var icon: String {
        switch self {
        case .onlyMe:      return "lock"
        case .closeCircle: return "person.2"
        case .community:   return "person.3"
        case .creatorOnly: return "person.badge.shield.checkmark"
        }
    }
}

// MARK: - AmenMediaReflectionSheet

struct AmenMediaReflectionSheet: View {

    // MARK: Inputs

    let mediaId: String?
    let sessionId: String?
    let mediaTitle: String?
    let sessionIntent: String?

    var onSaved: (() -> Void)? = nil
    var onAddToJournal: ((String) -> Void)? = nil

    // MARK: State

    @State private var reflectionText = ""
    @State private var visibility: MediaReflectionVisibility = .onlyMe
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedSuccessfully = false

    @Environment(\.dismiss) private var dismiss
    @FocusState private var editorFocused: Bool

    private var prompt: String { reflectionPrompt(for: sessionIntent) }
    private var canSave: Bool {
        !reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    mediaContextRow
                    promptSection
                    textEditorSection
                    visibilitySection
                    feedbackRow
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Cancel reflection")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await saveReflection() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(!canSave)
                    .accessibilityLabel("Save reflection")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if !reflectionText.isEmpty, let onJournal = onAddToJournal {
                        Button("Add to Journal") {
                            onJournal(reflectionText)
                            dismiss()
                        }
                        .accessibilityLabel("Add this reflection to your journal")
                    }
                    Spacer()
                    Button("Done") { editorFocused = false }
                        .accessibilityLabel("Dismiss keyboard")
                }
            }
        }
        .onAppear { editorFocused = true }
    }

    // MARK: Media Context Row

    @ViewBuilder
    private var mediaContextRow: some View {
        if let title = mediaTitle {
            HStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }

    // MARK: Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Your reflection is private by default. You choose who can see it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Text Editor

    private var textEditorSection: some View {
        TextEditor(text: $reflectionText)
            .font(.body)
            .frame(minHeight: 130)
            .padding(12)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
            )
            .focused($editorFocused)
            .accessibilityLabel("Reflection text")
    }

    // MARK: Visibility Section

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who can see this?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(MediaReflectionVisibility.allCases) { option in
                    visibilityButton(option)
                }
            }
        }
    }

    // MARK: Feedback Row

    @ViewBuilder
    private var feedbackRow: some View {
        if let error = errorMessage {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
        }
        if savedSuccessfully {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Reflection saved.")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: Visibility Button

    private func visibilityButton(_ option: MediaReflectionVisibility) -> some View {
        let isSelected = visibility == option
        return Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.82)) {
                visibility = option
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: option.icon)
                    .font(.system(size: 14, weight: .medium))
                    .accessibilityHidden(true)
                Text(option.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color(.label) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? .clear : Color(.separator).opacity(0.3),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Save

    private func saveReflection() async {
        let trimmed = reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            var payload: [String: Any] = [
                "reflectionText": trimmed,
                "visibility": visibility.rawValue
            ]
            if let id = mediaId   { payload["mediaId"] = id }
            if let id = sessionId { payload["sessionId"] = id }
            _ = try await Functions.functions().httpsCallable("createMediaReflection").call(payload)
            savedSuccessfully = true
            onSaved?()
            try? await Task.sleep(for: .seconds(0.7))
            dismiss()
        } catch {
            errorMessage = "Could not save your reflection. Please try again."
        }
    }

    // MARK: Prompt Copy

    private func reflectionPrompt(for intent: String?) -> String {
        guard let intent else { return "What stood out to you?" }
        let lower = intent.lowercased()
        if lower.contains("worship")  { return "How did this speak to you?" }
        if lower.contains("sermon") || lower.contains("teaching") { return "What was the main insight?" }
        if lower.contains("testimony") { return "What stood out in this story?" }
        if lower.contains("family") || lower.contains("friend") { return "What memory does this bring up?" }
        if lower.contains("wellness") { return "How are you feeling after this?" }
        if lower.contains("learning") { return "What will you carry forward from this?" }
        if lower.contains("selah") || lower.contains("reflection") { return "Take a moment. What is being said to you?" }
        if lower.contains("encourage") { return "What encouraged you here?" }
        return "What stood out to you?"
    }
}
