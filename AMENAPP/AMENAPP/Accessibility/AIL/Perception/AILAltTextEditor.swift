// AILAltTextEditor.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Perception Surface (A4)
//
// C5 image alt-text editor. A "Describe" button asks the AIL transform service to
// generate a description (.describeImage), which lands in an EDITABLE field with
// an AI-generated provenance label. When the creator edits and saves, provenance
// flips to .aiHumanEdited and the label updates to reflect human authorship.
//
// IRON RULE 6 (C5): image descriptions NEVER name or identify people and NEVER
// estimate the age of minors. The backend prompt enforces this; this UI must not
// add names either — it only displays/edits the returned text verbatim and offers
// the creator's own words. Do not inject identity into the field anywhere.
//
// FAIL OPEN (iron rule 3): if the transform fails open, we show an EMPTY editable
// field plus a quiet "couldn't generate — add your own" note. Generation never
// blocks posting an image.
//
// NO tier checks. No force-unwraps. 4-space indent. Six UI states below.

import SwiftUI

/// Editable alt-text surface for one image. `mediaId` ties the description to its
/// media; `imageRef` is the resolvable original passed to the transform.
struct AILAltTextEditor: View {

    let mediaId: String
    let imageRef: String

    /// Optional sink so a host composer can capture the final ImageDescription.
    var onSave: ((ImageDescription) -> Void)? = nil

    // MARK: - Six UI states
    private enum Phase: Equatable {
        case idle            // 1. nothing generated yet
        case generating      // 2. transform in flight
        case generated       // 3. AI description shown, editable
        case edited          // 4. creator changed the AI text (unsaved)
        case saved           // 5. creator saved (provenance reflects authorship)
        case failedOpen      // 6. transform failed open — empty field + quiet note
    }

    @State private var phase: Phase = .idle
    @State private var draft: String = ""
    @State private var provenance: A11yProvenance = .aiGenerated
    @State private var confidence: A11yConfidence = .medium
    /// The exact text the AI produced — used to detect creator edits.
    @State private var generatedText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch phase {
            case .idle:
                describeButton
            case .generating:
                generatingRow
            case .generated, .edited, .saved, .failedOpen:
                editorBody
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Image description")
                .font(.headline)
            Text("Helps people who can't see the image. It never names anyone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - State 1: idle

    private var describeButton: some View {
        Button {
            Task { await generate() }
        } label: {
            Label("Describe this image", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint(Text("Creates a starting description you can edit."))
    }

    // MARK: - State 2: generating

    private var generatingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Writing a description…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - States 3–6: editor

    private var editorBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if phase == .failedOpen {
                Label("Couldn't generate — add your own.", systemImage: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField(
                "Describe what's in the image",
                text: draftBinding,
                axis: .vertical
            )
            .lineLimit(3...8)
            .textFieldStyle(.plain)
            .padding(10)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel(Text("Image description text"))

            HStack(spacing: 12) {
                // Provenance only shown once there is AI-origin content.
                if phase != .failedOpen {
                    AILProvenanceLabel(provenance: provenance)
                }
                Spacer(minLength: 0)
                saveButton
            }
        }
    }

    private var saveButton: some View {
        Button("Save") {
            commit()
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phase == .saved)
        .accessibilityHint(Text("Saves this description for the image."))
    }

    // MARK: - Binding (tracks creator edits → provenance)

    private var draftBinding: Binding<String> {
        Binding(
            get: { draft },
            set: { newValue in
                draft = newValue
                // A change away from the AI text marks human authorship.
                if phase == .failedOpen {
                    // Author writing their own from scratch — human-authored.
                    provenance = .human
                } else if newValue != generatedText {
                    provenance = .aiHumanEdited
                    if phase == .saved || phase == .generated { phase = .edited }
                } else {
                    provenance = .aiGenerated
                    if phase == .edited { phase = .generated }
                }
            }
        )
    }

    // MARK: - Actions

    private func generate() async {
        phase = .generating
        let result = await AILTransformService.shared.transform(
            task: .describeImage,
            input: imageRef,
            originalRef: imageRef
        )

        if result.failOpen {
            // Fail OPEN: empty editable field + quiet note. Never blocks posting.
            draft = ""
            generatedText = ""
            provenance = .human
            confidence = .low
            phase = .failedOpen
            return
        }

        let text = result.text ?? ""
        generatedText = text
        draft = text
        provenance = result.provenance     // .aiGenerated on success
        confidence = result.confidence
        phase = text.isEmpty ? .failedOpen : .generated
    }

    private func commit() {
        let finalText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else { return }

        // Provenance is already correct from the binding; reaffirm the edit rule:
        // if the creator changed AI text, it's human-edited; pure AI stays AI.
        let finalProvenance: A11yProvenance
        if phase == .failedOpen {
            finalProvenance = .human
        } else if finalText != generatedText {
            finalProvenance = .aiHumanEdited
        } else {
            finalProvenance = .aiGenerated
        }
        provenance = finalProvenance

        let description = ImageDescription(
            mediaId: mediaId,
            text: finalText,
            provenance: finalProvenance,
            confidence: confidence,
            flagged: false
        )
        onSave?(description)
        phase = .saved
    }

    // MARK: - Chrome

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
