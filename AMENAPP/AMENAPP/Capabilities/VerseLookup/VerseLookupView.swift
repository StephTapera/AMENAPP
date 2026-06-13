// VerseLookupView.swift
// AMEN Capabilities v1 — Inline verse lookup in all composers (Wave 1: Lane E)
//
// Presented by the CapabilityPicker when the user selects "Verse Lookup" via @ trigger.
// Supports reference search (e.g. "John 3:16") and keyword search (e.g. "God is love").
// Results load with a 500 ms debounce on keystroke. Selecting a result shows a preview
// with a surface-aware insertion button.
//
// Flag gate: AMENFeatureFlags.shared.verseLookupInlineEnabled
//   OFF → shows "Verse Lookup is not available" message and no network calls are made.
//
// Accessibility:
//   • Search field submitLabel .search
//   • Result rows labeled "<reference>: <snippet>"
//   • Insert button title adapts to CapabilitySurface
//   • Dynamic Type: all text uses text styles

import SwiftUI

// MARK: - VerseLookupView

struct VerseLookupView: View {

    // MARK: Input

    let surface: CapabilitySurface
    var onInsert: (VerseCard) -> Void

    // MARK: Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: State

    @State private var query = ""
    @State private var results: [ScriptureSearchResult] = []
    @State private var selectedVerse: VerseCard? = nil
    @State private var isSearching = false
    @State private var searchError: Error? = nil
    @FocusState private var isQueryFocused: Bool

    // Debounce task reference
    @State private var debounceTask: Task<Void, Never>? = nil

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if !AMENFeatureFlags.shared.verseLookupInlineEnabled {
                    unavailableState
                } else {
                    lookupContent
                }
            }
            .navigationTitle("Verse Lookup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Content

    private var lookupContent: some View {
        VStack(spacing: 0) {
            searchField

            if isSearching {
                Spacer()
                ProgressView()
                    .accessibilityLabel("Searching verses")
                    .padding()
                Spacer()
            } else if let error = searchError {
                errorView(error)
            } else {
                resultsList
            }

            if let verse = selectedVerse {
                VerseInsertPreview(verse: verse, surface: surface) {
                    onInsert(verse)
                    dismiss()
                }
            }
        }
        .onAppear { isQueryFocused = true }
    }

    private var searchField: some View {
        TextField("John 3:16 or "God is love"", text: $query)
            .textFieldStyle(.roundedBorder)
            .focused($isQueryFocused)
            .padding()
            .submitLabel(.search)
            .onSubmit {
                debounceTask?.cancel()
                Task { await search() }
            }
            .onChange(of: query) { _, newValue in
                // Cancel previous debounce, start a new 500 ms window
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    await search()
                }
            }
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty && !query.isEmpty {
            Text("No results for "\(query)"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(results) { result in
                VerseLookupResultRow(result: result) {
                    Task { await selectResult(result) }
                }
            }
            .listStyle(.plain)
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 8) {
            Text("Search failed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await search() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Verse Lookup is not available")
                .font(.headline)
            Text("This feature is not currently enabled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Async Actions

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            results = try await VerseLookupService.shared.search(query: trimmed)
        } catch {
            searchError = error
        }
    }

    private func selectResult(_ result: ScriptureSearchResult) async {
        do {
            selectedVerse = try await VerseLookupService.shared.getVerse(osisRef: result.osisRef)
        } catch {
            searchError = error
        }
    }
}

// MARK: - VerseLookupResultRow

struct VerseLookupResultRow: View {
    let result: ScriptureSearchResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.display)
                    .font(.headline)
                Text(result.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(result.display): \(result.snippet)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - VerseInsertPreview

/// Bottom-anchored preview of the selected verse with a surface-aware insertion button.
struct VerseInsertPreview: View {
    let verse: VerseCard
    let surface: CapabilitySurface
    let onInsert: () -> Void

    var insertButtonTitle: String {
        switch surface {
        case .messages: return "Add to Message"
        case .notes:    return "Insert as Block"
        case .berean:   return "Add as Context"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verse.display)
                .font(.headline)
            Text(verse.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(verse.translation.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(insertButtonTitle, action: onInsert)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("\(insertButtonTitle): \(verse.display)")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}
