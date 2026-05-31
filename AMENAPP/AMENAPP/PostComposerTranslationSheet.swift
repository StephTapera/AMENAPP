// PostComposerTranslationSheet.swift
// AMENAPP
//
// Sheet presented from the post composer letting the author preview and
// optionally post a translated version of their draft.
// Uses PostTranslationService (BereanContextualTranslationEngine).

import SwiftUI

// MARK: - PostComposerTranslationSheet

struct PostComposerTranslationSheet: View {

    @Binding var isPresented: Bool
    let draftText: String
    /// Called with (text, wasTranslated).
    let onConfirm: (String, Bool) -> Void

    @State private var selectedLanguage: TranslationLanguage = PostTranslationService.shared.preferredLanguage
    @State private var translatedText: String? = nil
    @State private var isTranslating = false
    @State private var showTranslated = false
    @State private var translationError: String? = nil

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Language picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Translate to")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(TranslationLanguage.allCases, id: \.rawValue) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 140)
                        .clipped()
                        .onChange(of: selectedLanguage) { _ in
                            // Reset translation when language changes
                            translatedText = nil
                            showTranslated = false
                            translationError = nil
                        }
                    }

                    // Translate button
                    Button(action: performTranslation) {
                        Group {
                            if isTranslating {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text("Translating…")
                                }
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "globe")
                                    Text("Translate")
                                }
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AmenTheme.Colors.amenGold, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isTranslating)
                    .padding(.horizontal)

                    // Error banner
                    if let errorMsg = translationError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(errorMsg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Side-by-side preview cards
                    if let translated = translatedText {
                        HStack(alignment: .top, spacing: 12) {
                            previewCard(
                                title: "Original",
                                text: draftText,
                                background: AmenTheme.Colors.backgroundSecondary
                            )
                            previewCard(
                                title: "Translated (\(selectedLanguage.displayName))",
                                text: translated,
                                background: AmenTheme.Colors.amenGold.opacity(0.12)
                            )
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                        // Character count
                        HStack {
                            Spacer()
                            Text("\(translated.count) characters")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)

                        // Length divergence warning
                        if lengthDivergenceExceeds50Percent(original: draftText, translated: translated) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                                Text("Translation may differ significantly in length.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }

                        // Action buttons
                        VStack(spacing: 12) {
                            Button {
                                onConfirm(translated, true)
                                isPresented = false
                            } label: {
                                Text("Post translated version")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(AmenTheme.Colors.amenGold, in: RoundedRectangle(cornerRadius: 14))
                            }

                            Button {
                                onConfirm(draftText, false)
                                isPresented = false
                            } label: {
                                Text("Post original")
                                    .font(.subheadline)
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
                .padding(.top, 8)
                .animation(.easeInOut(duration: 0.25), value: translatedText != nil)
            }
            .navigationTitle("Translate Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
    }

    // MARK: - Sub-views

    private func previewCard(title: String, text: String, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func performTranslation() {
        guard !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isTranslating = true
        translationError = nil
        Task {
            do {
                let result = try await PostTranslationService.shared.translate(
                    postId: "draft_\(UUID().uuidString)",
                    text: draftText,
                    to: selectedLanguage
                )
                withAnimation {
                    translatedText = result.translatedText
                    showTranslated = true
                }
            } catch {
                translationError = error.localizedDescription
            }
            isTranslating = false
        }
    }

    private func lengthDivergenceExceeds50Percent(original: String, translated: String) -> Bool {
        guard original.count > 0 else { return false }
        let ratio = Double(translated.count) / Double(original.count)
        return ratio < 0.5 || ratio > 1.5
    }
}

// MARK: - Preview

#if DEBUG
struct PostComposerTranslationSheet_Previews: PreviewProvider {
    static var previews: some View {
        PostComposerTranslationSheet(
            isPresented: .constant(true),
            draftText: "God is good all the time. Sharing this verse with my faith community today."
        ) { text, wasTranslated in
            print("Confirmed: wasTranslated=\(wasTranslated) text=\(text)")
        }
    }
}
#endif
