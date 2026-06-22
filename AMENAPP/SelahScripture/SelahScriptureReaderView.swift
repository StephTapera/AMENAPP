//
//  SelahScriptureReaderView.swift
//  AMENAPP
//
//  Apple Books-style horizontally-paged reader. White canvas, black text,
//  Dynamic Type. Liquid Glass only for the floating top/bottom chrome.
//  Pages are chapters of the active translation.
//

import SwiftUI
import FirebaseAuth

struct SelahScriptureReaderView: View {

    // MARK: - Inputs

    let initialReference: SelahScriptureReference
    let provider: SelahBibleTranslationProvider
    @ObservedObject var preferencesStore: SelahScriptureReaderPreferencesStore

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var currentBookId: String
    @State private var currentChapter: Int
    @State private var chapterCache: [String: SelahBibleChapter] = [:]
    @State private var loadingKeys: Set<String> = []
    @State private var loadErrors: [String: String] = [:]
    @State private var showSearch: Bool = false
    @State private var toast: String?

    // Toolbar selection state (single verse)
    @State private var selectedVerseNumber: Int?

    // MARK: - Annotation State

    /// The verse currently selected for context menu / annotation.
    /// Hidden by default — only set when the user taps a verse.
    @State private var selectedVerse: (number: Int, text: String, ref: String)? = nil

    /// Controls visibility of the verse context menu (action sheet).
    @State private var showVerseContextMenu: Bool = false

    /// Controls visibility of the annotation bottom sheet.
    @State private var showAnnotationSheet: Bool = false

    /// Which annotation mode the sheet opens in.
    @State private var annotationMode: SelahAnnotationMode = .highlight

    /// Controls visibility of the discernment check sheet.
    @State private var showDiscernmentSheet: Bool = false

    /// The verse text forwarded to the discernment sheet.
    @State private var discernmentInputVerse: String? = nil

    // MARK: - Init

    init(
        initialReference: SelahScriptureReference,
        provider: SelahBibleTranslationProvider,
        preferencesStore: SelahScriptureReaderPreferencesStore
    ) {
        self.initialReference = initialReference
        self.provider = provider
        self._preferencesStore = ObservedObject(initialValue: preferencesStore)
        _currentBookId = State(initialValue: initialReference.bookId)
        _currentChapter = State(initialValue: max(1, initialReference.chapter))
    }

    // MARK: - Derived

    private var translation: SelahBibleTranslation {
        SelahBibleTranslation.known.first { $0.id == preferencesStore.preferences.translationId } ?? .kjv
    }

    private var book: SelahBibleBook? {
        SelahBibleBook.find(id: currentBookId)
    }

    private var pageKey: String {
        Self.cacheKey(bookId: currentBookId, chapter: currentChapter, translationId: translation.id)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea() // reading canvas — always white
            VStack(spacing: 0) {
                topBar
                pagedContent
            }

            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.systemScaled(13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 96)
                }
                .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            loadChapterIfNeeded(bookId: currentBookId, chapter: currentChapter)
            recordPosition()
        }
        .onChange(of: currentChapter) { _, _ in
            recordPosition()
            playPageTurnIfEnabled()
            loadChapterIfNeeded(bookId: currentBookId, chapter: currentChapter)
        }
        .onChange(of: currentBookId) { _, _ in
            recordPosition()
            loadChapterIfNeeded(bookId: currentBookId, chapter: currentChapter)
        }
        .sheet(isPresented: $showSearch) {
            SelahScriptureSearchView(
                provider: provider,
                preferencesStore: preferencesStore
            )
        }
        // Verse context menu — Liquid Glass action sheet
        .confirmationDialog(
            selectedVerse.map { "Verse \($0.number)" } ?? "",
            isPresented: $showVerseContextMenu,
            titleVisibility: .visible
        ) {
            Button("Highlight") {
                annotationMode = .highlight
                showAnnotationSheet = true
            }
            Button("Add Note") {
                annotationMode = .note
                showAnnotationSheet = true
            }
            Button("Add Question") {
                annotationMode = .question
                showAnnotationSheet = true
            }
            Button("Add Prayer") {
                annotationMode = .prayer
                showAnnotationSheet = true
            }
            Button("Check against Scripture") {
                discernmentInputVerse = selectedVerse?.text
                showDiscernmentSheet = true
            }
            Button("Dismiss", role: .cancel) {
                selectedVerse = nil
            }
        }
        // Annotation sheet (highlight / note / question / prayer)
        .sheet(isPresented: $showAnnotationSheet) {
            if let verse = selectedVerse {
                SelahAnnotationSheet(
                    verseRef: verse.ref,
                    verseText: verse.text,
                    mode: annotationMode,
                    translationId: translation.id,
                    onSave: { noteData in
                        Task {
                            guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
                            let note = SelahNote.new(
                                userId: uid,
                                verseRef: noteData.verseRef,
                                translationRead: noteData.translationRead,
                                kind: SelahNoteKind(rawValue: noteData.kind) ?? .note,
                                color: noteData.color,
                                body: noteData.body
                            )
                            try? await SelahNoteService.shared.createNote(note)
                        }
                    },
                    onDelete: { noteId in
                        Task {
                            guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
                            try? await SelahNoteService.shared.softDeleteNote(id: noteId, userId: uid)
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        // Discernment check sheet — placeholder for Agent C's DiscernmentEntrySheet
        .sheet(isPresented: $showDiscernmentSheet) {
            if let verseText = discernmentInputVerse {
                DiscernmentEntrySheet(inputText: verseText, sourceType: "verse", sourceRef: selectedVerse?.ref)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Top Bar (Liquid Glass)

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 32, height: 32)
                    Image(systemName: "xmark").font(.systemScaled(11, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close reader")

            Spacer(minLength: 0)

            VStack(spacing: 1) {
                Text(book?.displayName ?? currentBookId.capitalized)
                    .font(.systemScaled(14, weight: .semibold))
                Text("Chapter \(currentChapter) · \(translation.abbreviation)")
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                showSearch = true
            } label: {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 32, height: 32)
                    Image(systemName: "magnifyingglass").font(.systemScaled(12, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search scripture")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Paged Content

    private var pagedContent: some View {
        TabView(selection: $currentChapter) {
            ForEach(1...chapterCount, id: \.self) { ch in
                chapterPage(chapter: ch)
                    .tag(ch)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        .background(Color(.systemBackground))
        .gesture(
            DragGesture(minimumDistance: 60, coordinateSpace: .global)
                .onEnded { value in
                    // Horizontal swipe across book boundary
                    if value.translation.width < -80, currentChapter == chapterCount, let next = book?.nextBook {
                        advance(to: next.id, chapter: 1)
                    } else if value.translation.width > 80, currentChapter == 1, let prev = book?.previousBook {
                        advance(to: prev.id, chapter: prev.chapterCount)
                    }
                }
        )
    }

    @ViewBuilder
    private func chapterPage(chapter: Int) -> some View {
        let key = Self.cacheKey(bookId: currentBookId, chapter: chapter, translationId: translation.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader(chapter: chapter)
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 18)

                if let cached = chapterCache[key] {
                    versesList(cached)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 80)
                } else if loadingKeys.contains(key) {
                    ProgressView()
                        .padding(.top, 60)
                        .frame(maxWidth: .infinity)
                } else if let err = loadErrors[key] {
                    chapterUnavailable(message: err)
                        .padding(.horizontal, 22)
                        .padding(.top, 40)
                } else {
                    Color.clear.frame(height: 1)
                        .onAppear { loadChapterIfNeeded(bookId: currentBookId, chapter: chapter) }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private func pageHeader(chapter: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((book?.displayName ?? currentBookId.capitalized).uppercased())
                .font(.systemScaled(10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            Text("Chapter \(chapter)")
                .font(.systemScaled(26, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
        }
    }

    private func versesList(_ chapter: SelahBibleChapter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(chapter.verses) { verse in
                verseRow(verse)
            }
            ForEach(footerActions(for: chapter), id: \.title) { action in
                action.view
            }
        }
    }

    private func verseRow(_ verse: SelahBibleVerse) -> some View {
        // Determine if this verse has a highlight note from SelahNoteService
        let verseRef = buildVerseRef(verse)
        let highlightNote = SelahNoteService.shared.notes[verseRef]?
            .first(where: { $0.kind == .highlight && $0.deletedAt == nil })
        let highlightHex = highlightNote?.color

        return Button {
            if selectedVerseNumber == verse.number {
                selectedVerseNumber = nil
            } else {
                selectedVerseNumber = verse.number
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(verse.number)")
                    .font(.systemScaled(10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)
                    .padding(.top, 4)
                Text(verse.text)
                    .font(.systemScaled(preferencesStore.preferences.fontPointSize, design: .serif))
                    .foregroundStyle(.black)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    // Show highlight background if note exists with kind == highlight
                    .selahHighlight(colorHex: highlightHex)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedVerseNumber == verse.number ? SelahHighlightTone.peace.fill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Verse \(verse.number)")
        .accessibilityHint("Tap to select, long press to annotate")
        // Long-press opens annotation context menu
        .onLongPressGesture(minimumDuration: 0.4) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            selectedVerse = (
                number: verse.number,
                text: verse.text,
                ref: verseRef
            )
            showVerseContextMenu = true
        }
    }

    /// Builds a display verse reference string like "James 1:5" for use as
    /// the `verseRef` key passed to SelahAnnotationSheet and SelahNoteService.
    private func buildVerseRef(_ verse: SelahBibleVerse) -> String {
        let bookName = book?.displayName ?? currentBookId.capitalized
        return "\(bookName) \(currentChapter):\(verse.number)"
    }

    private func footerActions(for chapter: SelahBibleChapter) -> [(title: String, view: AnyView)] {
        var actions: [(title: String, view: AnyView)] = []
        if let selected = selectedVerseNumber,
           let verse = chapter.verses.first(where: { $0.number == selected }) {
            actions.append((
                title: "toolbar",
                view: AnyView(
                    SelahFloatingVerseActionToolbar(
                        onCopy: { copy(verse) },
                        onSave: { save(verse) },
                        onReflect: { reflect(verse) }
                    )
                    .padding(.top, 12)
                )
            ))
        }
        actions.append((
            title: "fontControls",
            view: AnyView(
                HStack(spacing: 14) {
                    Spacer()
                    Button {
                        preferencesStore.setFontPointSize(preferencesStore.preferences.fontPointSize - 1)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Smaller text")

                    Button {
                        preferencesStore.setFontPointSize(preferencesStore.preferences.fontPointSize + 1)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Larger text")

                    Button {
                        preferencesStore.setPageTurnSoundEnabled(!preferencesStore.preferences.pageTurnSoundEnabled)
                    } label: {
                        Image(systemName: preferencesStore.preferences.pageTurnSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(preferencesStore.preferences.pageTurnSoundEnabled ? Color.accentColor : .secondary)
                            .padding(8)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toggle page-turn sound")
                }
                .padding(.top, 20)
            )
        ))
        return actions
    }

    @ViewBuilder
    private func chapterUnavailable(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.systemScaled(28))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Chapter not available")
                .font(.systemScaled(16, weight: .semibold))
            Text(message)
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: - Verse Actions

    private func copy(_ verse: SelahBibleVerse) {
        let body = "\(verse.reference.displayString) (\(translation.abbreviation))\n\(verse.text)"
        UIPasteboard.general.string = body
        flash("Copied \(verse.reference.displayString)")
    }

    private func save(_ verse: SelahBibleVerse) {
        let saved = SelahSavedScripture(
            reference: verse.reference,
            translationId: translation.id
        )
        SelahSavedScriptureStore.shared.add(saved)
        flash("Saved \(verse.reference.displayString)")
    }

    private func reflect(_ verse: SelahBibleVerse) {
        flash("Reflection saved locally")
        let entry = SelahScriptureHighlightEntry(
            reference: verse.reference,
            translationId: translation.id,
            toneKey: "peace"
        )
        SelahSavedScriptureStore.shared.addHighlight(entry)
    }

    // MARK: - Loading

    private var chapterCount: Int {
        book?.chapterCount ?? max(currentChapter, 1)
    }

    private func loadChapterIfNeeded(bookId: String, chapter: Int) {
        let key = Self.cacheKey(bookId: bookId, chapter: chapter, translationId: translation.id)
        guard chapterCache[key] == nil, !loadingKeys.contains(key) else { return }
        loadingKeys.insert(key)
        loadErrors[key] = nil
        let activeTranslation = translation
        Task {
            do {
                let result = try await provider.loadChapter(bookId: bookId, chapter: chapter, translation: activeTranslation)
                await MainActor.run {
                    chapterCache[key] = result
                    loadingKeys.remove(key)
                }
            } catch {
                await MainActor.run {
                    loadingKeys.remove(key)
                    loadErrors[key] = error.localizedDescription
                }
            }
        }
    }

    private func recordPosition() {
        preferencesStore.recordPosition(
            bookId: currentBookId,
            chapter: currentChapter,
            verse: selectedVerseNumber,
            translationId: translation.id
        )
    }

    private func playPageTurnIfEnabled() {
        SelahScripturePageTurnSoundPlayer.shared.playIfEnabled(
            preferences: preferencesStore.preferences,
            reduceMotion: reduceMotion
        )
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func advance(to bookId: String, chapter: Int) {
        currentBookId = bookId
        currentChapter = chapter
    }

    private func flash(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }

    // MARK: - Helpers

    private static func cacheKey(bookId: String, chapter: Int, translationId: String) -> String {
        "\(translationId)/\(bookId)/\(chapter)"
    }
}

// MARK: - Local Persistence Store for Saved + Highlights

/// Lightweight in-memory + UserDefaults store for verses the user saves
/// from the reader. A future revision will sync this with Firestore, but
/// the current build keeps everything local and private.
@MainActor
final class SelahSavedScriptureStore: ObservableObject {
    static let shared = SelahSavedScriptureStore()

    @Published private(set) var saved: [SelahSavedScripture] = []
    @Published private(set) var highlights: [SelahScriptureHighlightEntry] = []

    private let defaults: UserDefaults
    private let savedKey = "selah.scriptureReader.saved.v1"
    private let highlightsKey = "selah.scriptureReader.highlights.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: savedKey),
           let decoded = try? JSONDecoder().decode([SelahSavedScripture].self, from: data) {
            self.saved = decoded
        }
        if let data = defaults.data(forKey: highlightsKey),
           let decoded = try? JSONDecoder().decode([SelahScriptureHighlightEntry].self, from: data) {
            self.highlights = decoded
        }
    }

    func add(_ entry: SelahSavedScripture) {
        if !saved.contains(where: { $0.reference == entry.reference && $0.translationId == entry.translationId }) {
            saved.append(entry)
            persistSaved()
        }
    }

    func addHighlight(_ entry: SelahScriptureHighlightEntry) {
        highlights.append(entry)
        persistHighlights()
    }

    private func persistSaved() {
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: savedKey)
        }
    }

    private func persistHighlights() {
        if let data = try? JSONEncoder().encode(highlights) {
            defaults.set(data, forKey: highlightsKey)
        }
    }
}
