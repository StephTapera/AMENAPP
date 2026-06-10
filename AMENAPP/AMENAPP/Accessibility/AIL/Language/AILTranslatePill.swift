// AILTranslatePill.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Language Surface (A3)
//
// C1 Translate. An under-text Liquid Glass pill that, on tap, routes the host
// text through AILTransformService.transform(.translate, …) toward the user's
// locale target, then shows the translation inline with provenance + a one-tap
// "View original" toggle. Idiom/slang/scripture-phrase culture notes surface as
// tappable tooltips.
//
// IRON RULES honored here:
//   • FAIL OPEN — if result.failOpen is true we render the ORIGINAL text with a
//     quiet ".unavailable" caption and never block the user's view.
//   • Every AI output shows provenance (AILProvenanceLabel) and is reversible
//     (AILViewOriginalButton).
//   • Low confidence shows a hedge so the reader knows the translation is rough.
//   • Reduce Transparency → opaque pill; Reduce Motion → no transition animation.
//   • NO tier checks.
//
// This view never touches Scripture verse text — callers must route canonical
// verse explanation through AILScriptureExplanationPanel, never this pill.

import SwiftUI

struct AILTranslatePill: View {

    /// The original, human-authored text to (optionally) translate.
    let originalText: String
    /// Resolvable id/path of the original — round-tripped to "View original".
    let originalRef: String

    // The six UI states, expressed as a small enum + flags below.
    private enum Phase: Equatable {
        case idle          // pill not yet tapped — nothing transformed
        case loading       // transform in flight
        case translated    // success — showing translated text
        case showingOriginal   // user toggled back to original after a success
        case failOpen      // transform failed — original shown + "unavailable"
    }

    @State private var phase: Phase = .idle
    @State private var result: A11yTransformResult?
    @State private var showCultureNotes = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            controls
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: phase)
    }

    // MARK: - Content (the text the reader sees)

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .showingOriginal:
            // Original content — the default and the "View original" state.
            Text(originalText)
                .textSelection(.enabled)

        case .loading:
            // Show the original beneath an inline progress hint — never blank.
            VStack(alignment: .leading, spacing: 6) {
                Text(originalText)
                    .textSelection(.enabled)
                    .opacity(0.6)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Translating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Translating"))
            }

        case .translated:
            translatedContent

        case .failOpen:
            // FAIL OPEN — original text + a quiet, non-alarming caption.
            VStack(alignment: .leading, spacing: 4) {
                Text(originalText)
                    .textSelection(.enabled)
                Text("Translation unavailable")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(Text("Translation is currently unavailable. Showing the original."))
            }
        }
    }

    @ViewBuilder
    private var translatedContent: some View {
        if let result, let text = result.text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .textSelection(.enabled)

                if result.confidence == .low {
                    // Hedge — low-confidence translations are flagged as rough.
                    Text("Rough translation — meaning may be imperfect.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Rough translation. Meaning may be imperfect."))
                }

                AILProvenanceLabel(provenance: result.provenance)
            }
        } else {
            // Defensive: a "success" with no text behaves like fail-open.
            Text(originalText).textSelection(.enabled)
        }
    }

    // MARK: - Controls (translate / toggle / culture notes)

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            switch phase {
            case .idle:
                translateButton
            case .loading:
                EmptyView()
            case .translated:
                AILViewOriginalButton(isShowingOriginal: false) {
                    phase = .showingOriginal
                }
                cultureNotesButton
            case .showingOriginal:
                AILViewOriginalButton(isShowingOriginal: true) {
                    phase = .translated
                }
                cultureNotesButton
            case .failOpen:
                // Allow a retry on fail-open without nagging.
                Button {
                    runTranslate()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
    }

    private var translateButton: some View {
        Button {
            runTranslate()
        } label: {
            Label("Translate", systemImage: "character.bubble")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(pillBackground)
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Translates this text into your language."))
    }

    @ViewBuilder
    private var cultureNotesButton: some View {
        if let notes = result?.cultureNotes, !notes.isEmpty {
            Button {
                showCultureNotes = true
            } label: {
                Label("Culture notes", systemImage: "info.bubble")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .popover(isPresented: $showCultureNotes) {
                AILCultureNotesList(notes: notes)
            }
            .accessibilityHint(Text("Explains idioms, slang, and scripture phrases in this text."))
        }
    }

    // MARK: - Glass / opaque background

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous).fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        }
    }

    // MARK: - Transform

    /// Resolve the user's preferred target language from the current locale.
    private var targetLang: String? {
        Locale.current.language.languageCode?.identifier
    }

    private func runTranslate() {
        phase = .loading
        Task {
            let res = await AILTransformService.shared.transform(
                task: .translate,
                input: originalText,
                originalRef: originalRef,
                targetLang: targetLang
            )
            await MainActor.run {
                self.result = res
                // FAIL OPEN: any failOpen result shows the original quietly.
                self.phase = res.failOpen ? .failOpen : .translated
            }
        }
    }
}

// MARK: - Culture notes tooltip list

/// Tappable tooltip content listing idiom/slang/scripture-phrase/cultural notes.
private struct AILCultureNotesList: View {
    let notes: [CultureNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Culture notes")
                .font(.headline)
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: note.kind))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(note.phrase)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(note.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(note.phrase). \(note.note)"))
            }
        }
        .padding()
        .frame(minWidth: 240, maxWidth: 320, alignment: .leading)
    }

    private func icon(for kind: CultureNote.Kind) -> String {
        switch kind {
        case .idiom:           return "text.quote"
        case .slang:           return "bubble.left"
        case .scripturePhrase: return "book.closed"
        case .cultural:        return "globe"
        }
    }
}
