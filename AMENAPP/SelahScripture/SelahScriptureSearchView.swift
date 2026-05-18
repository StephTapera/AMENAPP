//
//  SelahScriptureSearchView.swift
//  AMENAPP
//
//  Scripture search entry surface. Accepts free-form input — reference
//  ("John 3:16", "Rom 5:3-5"), book/chapter ("Psalm 23"), or keyword
//  ("peace"). Routes to the appropriate provider response. Tapping a
//  result opens the SelahScriptureReaderView.
//

import SwiftUI

struct SelahScriptureSearchView: View {

    // MARK: - Inputs

    let provider: SelahBibleTranslationProvider
    let preferencesStore: SelahScriptureReaderPreferencesStore

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var parsedReference: SelahScriptureReference?
    @State private var keywordHits: [SelahScriptureSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var openingReference: SelahScriptureReference?

    // MARK: - Computed

    private var translation: SelahBibleTranslation {
        SelahBibleTranslation.known.first { $0.id == preferencesStore.preferences.translationId } ?? .kjv
    }

    private var translationAvailability: SelahBibleTranslationAvailability {
        provider.availability(for: translation)
    }

    private var bookSuggestions: [SelahBibleBook] {
        SelahScriptureReferenceParser
            .suggestBooks(prefix: query, limit: 6)
            .compactMap { SelahBibleBook.find(id: $0) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    translationStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)

                    Divider().opacity(0.4)

                    resultsList
                }
            }
            .navigationTitle("Bible")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(item: $openingReference) { ref in
                SelahScriptureReaderView(
                    initialReference: ref,
                    provider: provider,
                    preferencesStore: preferencesStore
                )
            }
            .onChange(of: query) { _, new in
                handleQueryChange(new)
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search verse, book, or keyword", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { handleSubmit() }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        )
        .accessibilityLabel("Scripture search")
    }

    // MARK: - Translation Strip

    private var translationStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SelahBibleTranslation.known) { t in
                    Button {
                        preferencesStore.setTranslation(t.id)
                    } label: {
                        VStack(spacing: 2) {
                            Text(t.abbreviation)
                                .font(.system(size: 12, weight: .semibold))
                            availabilityCaption(for: t)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(t.id == translation.id ? Color.accentColor : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(t.id == translation.id ? Color.accentColor.opacity(0.10) : Color.clear)
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                t.id == translation.id ? Color.accentColor.opacity(0.32) : Color.primary.opacity(0.10),
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(t.displayName) translation")
                }
            }
        }
    }

    @ViewBuilder
    private func availabilityCaption(for t: SelahBibleTranslation) -> some View {
        switch provider.availability(for: t) {
        case .available:    Text("Ready").foregroundStyle(.secondary.opacity(0.7))
        case .unavailable:  Text("Soon").foregroundStyle(.secondary.opacity(0.45))
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let ref = parsedReference {
                        sectionHeader("Reference")
                        referenceRow(ref)
                    }
                    if !bookSuggestions.isEmpty && parsedReference == nil {
                        sectionHeader("Books")
                        ForEach(bookSuggestions) { book in
                            bookRow(book)
                        }
                    }
                    if !keywordHits.isEmpty {
                        sectionHeader("Verses")
                        ForEach(keywordHits) { hit in
                            verseRow(hit)
                        }
                    }
                    if parsedReference == nil && bookSuggestions.isEmpty && keywordHits.isEmpty && !isSearching {
                        noResults
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func referenceRow(_ ref: SelahScriptureReference) -> some View {
        Button {
            openingReference = ref
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.displayString)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(translation.abbreviation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bookRow(_ book: SelahBibleBook) -> some View {
        Button {
            let ref = SelahScriptureReference(bookId: book.id, chapter: 1, startVerse: nil, endVerse: nil)
            openingReference = ref
        } label: {
            HStack {
                Image(systemName: "book.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(book.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(book.chapterCount) chapters")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func verseRow(_ hit: SelahScriptureSearchResult) -> some View {
        Button {
            openingReference = hit.reference
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(hit.reference.displayString)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Text(hit.translationId.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                if !hit.preview.isEmpty {
                    Text(hit.preview)
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / No results

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "book.pages")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary.opacity(0.55))
            Text("Search for a verse")
                .font(.system(size: 17, weight: .semibold))
            Text("Try \"John 3:16\", \"Psalm 23\", or a word\nlike \"peace\".")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Text("No matches")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Try a different word or a reference.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Logic

    private func handleQueryChange(_ new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        parsedReference = SelahScriptureReferenceParser.parse(trimmed)
        // Only run keyword search if we don't have a parsed reference and
        // input is long enough to avoid noise.
        if parsedReference == nil, trimmed.count >= 3 {
            runKeywordSearch(trimmed)
        } else {
            keywordHits = []
            isSearching = false
        }
    }

    private func runKeywordSearch(_ keyword: String) {
        isSearching = true
        let activeTranslation = translation
        Task {
            let results = (try? await provider.search(
                keyword: keyword,
                translation: activeTranslation,
                limit: 20
            )) ?? []
            await MainActor.run {
                keywordHits = results
                isSearching = false
            }
        }
    }

    private func handleSubmit() {
        if let parsed = parsedReference {
            openingReference = parsed
        } else if let firstHit = keywordHits.first {
            openingReference = firstHit.reference
        } else if let firstBook = bookSuggestions.first {
            openingReference = SelahScriptureReference(bookId: firstBook.id, chapter: 1, startVerse: nil, endVerse: nil)
        }
    }
}

extension SelahScriptureReference: Identifiable {
    public var id: String {
        "\(bookId).\(chapter).\(startVerse ?? 0).\(endVerse ?? 0)"
    }
}
