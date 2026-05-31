// AltTextEditorView.swift
// AMEN Universal Accessibility Engine — A3 Visual Understanding
// Alt text editor sheet + small badge tap target.
// NOTE: Struct names are deliberately prefixed "Media" to avoid collision with
//       the existing AltTextEditorSheet in CreatePostEnhancements.swift.

import SwiftUI

// MARK: - MediaAltTextEditorSheet

/// Full sheet for reviewing and editing AI-generated alt text.
struct MediaAltTextEditorSheet: View {

    // MARK: Init

    let mediaId: String

    init(mediaId: String, initialAltText: String) {
        self.mediaId = mediaId
        _altText = State(initialValue: initialAltText)
    }

    // MARK: State

    @State private var altText: String
    @State private var isSaving = false
    @State private var isRegenerating = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {

                // ── Header badge row ──────────────────────────────────────
                HStack(spacing: 8) {
                    Text("Alt Text")
                        .font(.headline)
                    aiAssistedBadge
                    Spacer()
                }
                .padding(.top, 4)

                // ── Editor ───────────────────────────────────────────────
                TextEditor(text: $altText)
                    .font(.body)
                    .frame(minHeight: 96) // ~4 lines at default size
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                    .accessibilityLabel("Alt text editor")

                // ── Error banner ─────────────────────────────────────────
                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(reduceMotion ? .identity : .opacity)
                }

                // ── Action buttons ───────────────────────────────────────
                HStack(spacing: 12) {

                    // Regenerate
                    Button {
                        Task { await regenerate() }
                    } label: {
                        Label {
                            Text("Regenerate")
                        } icon: {
                            if isRegenerating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(AmenTheme.Colors.amenPurple)
                    .disabled(isRegenerating || isSaving)
                    .accessibilityLabel("Regenerate alt text")

                    Spacer()

                    // Save
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.9)
                                .frame(width: 60)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                                .frame(minWidth: 60)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AmenTheme.Colors.amenPurple)
                    .disabled(isSaving || isRegenerating || altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Save alt text")
                }

                // ── Footer ───────────────────────────────────────────────
                Text("Descriptions are grounded in visible content only.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationTitle("Alt Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Private Helpers

    private var aiAssistedBadge: some View {
        HStack(spacing: 4) {
            Text("✦")
                .font(.caption2)
            Text("AI Assisted")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(AmenTheme.Colors.amenPurple.opacity(0.15))
        )
        .foregroundStyle(AmenTheme.Colors.amenPurple)
        .accessibilityLabel("AI Assisted")
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await AltTextService.shared.markHumanEdited(mediaId: mediaId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func regenerate() async {
        isRegenerating = true
        errorMessage = nil
        defer { isRegenerating = false }
        do {
            let (newText, _) = try await AltTextService.shared.generateAltText(mediaId: mediaId)
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                altText = newText
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - AltTextBadge

/// Small tap target that shows the alt text status and opens the editor sheet.
struct AltTextBadge: View {

    let mediaId: String
    let currentAltText: String

    @State private var showEditor = false

    var body: some View {
        Button {
            showEditor = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "text.viewfinder")
                    .font(.caption2.weight(.semibold))
                Text("Alt Text")
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(.systemFill))
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(currentAltText.isEmpty ? "Add alt text" : "Edit alt text")
        .sheet(isPresented: $showEditor) {
            MediaAltTextEditorSheet(
                mediaId: mediaId,
                initialAltText: currentAltText
            )
        }
    }
}
