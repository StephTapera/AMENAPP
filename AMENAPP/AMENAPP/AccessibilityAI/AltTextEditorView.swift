//
//  AltTextEditorView.swift
//  AMENAPP
//
//  A8 — Sheet for reviewing and editing per-media alt text.
//  On appear, auto-populates via AltTextService if the field is empty.
//  Character limit mirrors the 200-char cap enforced at post submission.
//

import SwiftUI

// MARK: - AltTextEditorView

struct AltTextEditorView: View {
    let imageURL: URL
    let initialAltText: String?
    var onSave: (String) -> Void

    @State private var text: String
    @State private var isGenerating: Bool = false
    @State private var hasGenerated: Bool = false

    @Environment(\.dismiss) private var dismiss

    private let characterLimit = 200

    init(imageURL: URL, initialAltText: String?, onSave: @escaping (String) -> Void) {
        self.imageURL = imageURL
        self.initialAltText = initialAltText
        self.onSave = onSave
        _text = State(initialValue: initialAltText ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            handle
                .padding(.top, 12)
                .padding(.bottom, 20)

            headerSection
                .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            editorSection
                .padding(.horizontal, 20)

            characterCountRow
                .padding(.horizontal, 24)
                .padding(.top, 6)

            Spacer().frame(height: 20)

            actionButtons
                .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .presentationDetents([.height(380)])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
        .task { await autoGenerateIfNeeded() }
    }

    // MARK: - Subviews

    private var handle: some View {
        Capsule()
            .fill(Color.primary.opacity(0.2))
            .frame(width: 36, height: 4)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Alt Text")
                .font(AMENFont.bold(18))
                .foregroundStyle(.primary)
            Text("Describe this image for screen reader users.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var editorSection: some View {
        if isGenerating {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(AmenTheme.Colors.amenPurple)
                Text("Generating alt text…")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            TextEditor(text: $text)
                .font(AMENFont.regular(14))
                .frame(height: 100)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                // Enforce character limit on every keystroke rather than at save time
                // so the count row never lags behind the actual capped value.
                .onChange(of: text) { _, newValue in
                    if newValue.count > characterLimit {
                        text = String(newValue.prefix(characterLimit))
                    }
                }
                .accessibilityLabel("Alt text input field")
                .accessibilityHint("Enter a description")
        }
    }

    private var characterCountRow: some View {
        Text("\(text.count)/\(characterLimit)")
            .font(AMENFont.regular(14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await runGenerate() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                    Text("Generate with AI")
                }
                .font(AMENFont.semiBold(16))
                .foregroundStyle(AmenTheme.Colors.amenPurple)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AmenTheme.Colors.amenPurple.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)

            Button {
                onSave(text)
                dismiss()
            } label: {
                Text("Save")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AmenTheme.Colors.amenPurple, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Generation Helpers

    private func autoGenerateIfNeeded() async {
        guard text.isEmpty else { return }
        await runGenerate()
    }

    private func runGenerate() async {
        isGenerating = true
        defer { isGenerating = false }
        if let generated = await AltTextService.shared.generateAltText(for: imageURL, context: nil) {
            text = generated
            hasGenerated = true
        }
    }
}
