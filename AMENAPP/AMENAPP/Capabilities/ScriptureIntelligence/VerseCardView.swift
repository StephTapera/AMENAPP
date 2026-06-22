// VerseCardView.swift
// AMEN Capabilities v1 — Verse card popover (Wave 1: Lane E)
//
// Shown as a popover when the user taps a detected scripture reference.
// Supports translation switching (BSB / WEB / KJV) and optional verse insertion.
//
// Accessibility:
//   • Reference label has an explicit accessibilityLabel
//   • Translation Picker labeled "Bible Translation"
//   • Error retry button labeled "Retry loading verse"
//   • Dynamic Type: all text uses text styles, no fixed font sizes

import SwiftUI

// MARK: - VerseCardView

struct VerseCardView: View {

    // MARK: Input

    let initialRef: ScriptureRef
    /// Called when the user taps "Insert Verse". Passes the fully resolved VerseCard.
    var onInsert: ((VerseCard) -> Void)? = nil

    // MARK: State

    @StateObject private var service = ScriptureIntelligenceDetectionService()
    @State private var selectedTranslation: BibleTranslation = .BSB
    @State private var verse: VerseCard? = nil
    @State private var isLoading = false
    @State private var error: Error? = nil

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            referenceHeader
            translationPicker
            verseBody
            insertButton
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        // Load on appear and whenever the translation changes
        .task(id: selectedTranslation) {
            await loadVerse()
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Sub-views

    private var referenceHeader: some View {
        Text(verse?.display ?? initialRef.display)
            .font(.headline)
            .accessibilityLabel(verse?.display ?? initialRef.display)
            .accessibilityAddTraits(.isHeader)
    }

    private var translationPicker: some View {
        Picker("Translation", selection: $selectedTranslation) {
            ForEach(BibleTranslation.allCases, id: \.self) { translation in
                Text(translation.rawValue).tag(translation)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Bible Translation")
    }

    @ViewBuilder
    private var verseBody: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView()
                    .accessibilityLabel("Loading verse")
                Spacer()
            }
            .frame(minHeight: 60)
        } else if let verse {
            Text(verse.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        } else if error != nil {
            errorState
        }
    }

    private var errorState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load verse")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await loadVerse() }
            }
            .accessibilityLabel("Retry loading verse")
        }
    }

    @ViewBuilder
    private var insertButton: some View {
        if let onInsert, let verse {
            Button("Insert Verse") {
                onInsert(verse)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Insert \(verse.display) into editor")
        }
    }

    // MARK: - Async Loader

    private func loadVerse() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            verse = try await service.getVerse(ref: initialRef, translation: selectedTranslation)
        } catch {
            self.error = error
        }
    }
}
