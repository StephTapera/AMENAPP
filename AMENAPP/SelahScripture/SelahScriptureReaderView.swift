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

private enum SelahScriptureStudyMode: String, CaseIterable, Identifiable {
    case read
    case study
    case reflect
    case pray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: return "Read"
        case .study: return "Study"
        case .reflect: return "Reflect"
        case .pray: return "Pray"
        }
    }

    var icon: String {
        switch self {
        case .read: return "book"
        case .study: return "books.vertical"
        case .reflect: return "text.bubble"
        case .pray: return "hands.sparkles"
        }
    }

    var tone: Color {
        switch self {
        case .read: return .primary
        case .study: return .indigo
        case .reflect: return .teal
        case .pray: return .mint
        }
    }
}

private struct SelahScriptureReaderDraft: Codable, Equatable {
    var reflection: String
    var prayer: String
    var updatedAt: Date
}

private enum SelahScriptureReaderHardeningStore {
    private static let defaults = UserDefaults.standard
    private static let modeKey = "selah.scriptureReader.activeMode.v2"
    private static let selectedVersePrefix = "selah.scriptureReader.selectedVerse.v2"
    private static let draftPrefix = "selah.scriptureReader.drafts.v2"
    private static let maxDraftLength = 4_000

    static func loadMode() -> SelahScriptureStudyMode {
        guard let raw = defaults.string(forKey: modeKey),
              let mode = SelahScriptureStudyMode(rawValue: raw) else { return .read }
        return mode
    }

    static func saveMode(_ mode: SelahScriptureStudyMode) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }

    static func loadSelectedVerse(bookId: String, chapter: Int, translationId: String) -> Int? {
        let key = selectedVerseKey(bookId: bookId, chapter: chapter, translationId: translationId)
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }

    static func saveSelectedVerse(_ verse: Int?, bookId: String, chapter: Int, translationId: String) {
        let key = selectedVerseKey(bookId: bookId, chapter: chapter, translationId: translationId)
        if let verse {
            defaults.set(verse, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    static func loadDraft(for reference: ScriptureReference, translationId: String) -> SelahScriptureReaderDraft {
        let key = draftKey(reference: reference, translationId: translationId)
        guard let data = defaults.data(forKey: key),
              let draft = try? JSONDecoder().decode(SelahScriptureReaderDraft.self, from: data) else {
            return SelahScriptureReaderDraft(reflection: "", prayer: "", updatedAt: Date())
        }
        return draft
    }

    static func saveDraft(reflection: String, prayer: String, for reference: ScriptureReference, translationId: String) {
        let draft = SelahScriptureReaderDraft(
            reflection: sanitizedDraft(reflection),
            prayer: sanitizedDraft(prayer),
            updatedAt: Date()
        )
        let key = draftKey(reference: reference, translationId: translationId)
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key)
    }

    static func clearReflection(for reference: ScriptureReference, translationId: String) {
        let existing = loadDraft(for: reference, translationId: translationId)
        saveDraft(reflection: "", prayer: existing.prayer, for: reference, translationId: translationId)
    }

    static func clearPrayer(for reference: ScriptureReference, translationId: String) {
        let existing = loadDraft(for: reference, translationId: translationId)
        saveDraft(reflection: existing.reflection, prayer: "", for: reference, translationId: translationId)
    }

    private static func selectedVerseKey(bookId: String, chapter: Int, translationId: String) -> String {
        "\(selectedVersePrefix).\(translationId).\(bookId).\(chapter)"
    }

    private static func draftKey(reference: ScriptureReference, translationId: String) -> String {
        let verse = reference.startVerse.map(String.init) ?? "chapter"
        return "\(draftPrefix).\(translationId).\(reference.bookId).\(reference.chapter).\(verse)"
    }

    private static func sanitizedDraft(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t" }.prefix(maxDraftLength))
    }
}

private extension View {
    func erasedToAnyView() -> AnyView {
        AnyView(self)
    }
}

struct SelahScriptureReaderView: View {

    // MARK: - Inputs

    let initialReference: ScriptureReference
    let provider: SelahBibleTranslationProvider
    @ObservedObject var preferencesStore: SelahScriptureReaderPreferencesStore

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

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
    @State private var showReactionPicker: Bool = false
    @State private var showCompanion: Bool = false
    @State private var companionPrompt: String? = nil
    @State private var showDeeperStudy: Bool = false
    @State private var showRewrite: Bool = false
    @State private var showAddToChurchNotes: Bool = false
    @State private var showCreateSermonNote: Bool = false
    @State private var activeMode: SelahScriptureStudyMode = .read
    @State private var reflectionDraft: String = ""
    @State private var prayerDraft: String = ""
    @State private var crisisSupportMessage: String?
    @State private var isRestoringDrafts: Bool = false
    @ObservedObject private var engagements = SelahVerseEngagementStore.shared // PERF: singleton → @ObservedObject

    // MARK: - Selah Lens + Guided Session state

    @StateObject private var lensViewModel = SelahLensViewModel()
    @StateObject private var selahReflectionVM = SelahReflectionViewModel()
    @State private var showSelahStudySheet: Bool = false
    @State private var showSelahReflectionComposer: Bool = false
    @State private var showGuidedSelahSession: Bool = false
    @State private var sabbathFocusActive: Bool = false

    // MARK: - Init

    init(
        initialReference: ScriptureReference,
        provider: SelahBibleTranslationProvider,
        preferencesStore: SelahScriptureReaderPreferencesStore
    ) {
        self.initialReference = initialReference
        self.provider = provider
        self._preferencesStore = ObservedObject(initialValue: preferencesStore)
        _currentBookId = State(initialValue: initialReference.bookId)
        _currentChapter = State(initialValue: max(1, initialReference.chapter))
        _selectedVerseNumber = State(initialValue: initialReference.startVerse)
    }

    // MARK: - Derived

    private var translation: SelahBibleTranslation {
        SelahBibleTranslation.known.first { $0.id == preferencesStore.preferences.translationId } ?? .kjv
    }

    private var book: SelahBibleBook? {
        SelahBibleBook.find(id: currentBookId)
    }

    private var deepLinkedVerseRange: ClosedRange<Int>? {
        guard currentBookId == initialReference.bookId,
              currentChapter == initialReference.chapter,
              let start = initialReference.startVerse else { return nil }
        return start...(initialReference.endVerse ?? start)
    }

    private var pageKey: String {
        Self.cacheKey(bookId: currentBookId, chapter: currentChapter, translationId: translation.id)
    }

    // MARK: - Body

    private var canvasTone: Color {
        // Subtle time-of-day tint applied OVER the white canvas. The shift is
        // intentionally tiny so black serif text stays fully readable.
        SelahReadingTone.current().canvasColor
    }

    private var crisisSupportBinding: Binding<Bool> {
        Binding(
            get: { crisisSupportMessage != nil },
            set: { if !$0 { crisisSupportMessage = nil } }
        )
    }

    private var crisisSupportText: String {
        crisisSupportMessage ?? ""
    }

    var body: some View {
        readerContent
    }

    private var readerContent: some View {
        readerBaseView
            .erasedToAnyView()
            .alert("Pause and get support", isPresented: crisisSupportBinding) {
                Button("OK", role: .cancel) { crisisSupportMessage = nil }
            } message: {
                Text(verbatim: crisisSupportText)
            }
            .sheet(isPresented: $showSearch) {
                SelahScriptureSearchView(
                    provider: provider,
                    preferencesStore: preferencesStore
                )
            }
            // Handoff — advertise the current reading position so the user can
            // pick up where they left off on iPad / Mac.
            .userActivity(SelahHandoff.readScriptureActivityType) { activity in
                let next = SelahHandoff.makeReadingActivity(
                    bookId: currentBookId,
                    chapter: currentChapter,
                    verse: selectedVerseNumber,
                    translationId: translation.id,
                    bookDisplayName: book?.displayName ?? currentBookId.capitalized
                )
                activity.title = next.title
                activity.isEligibleForHandoff = true
                activity.isEligibleForSearch = true
                activity.isEligibleForPrediction = true
                if let info = next.userInfo {
                    activity.addUserInfoEntries(from: info)
                }
            }
            .sheet(isPresented: $showReactionPicker) {
                if let n = selectedVerseNumber,
                   let ref = currentSelectedVerseReference(verseNumber: n) {
                    SelahVerseReactionPickerSheet(
                        reference: ref,
                        translationId: translation.id,
                        store: engagements
                    )
                }
            }
            .sheet(isPresented: $showCompanion) {
                SelahScriptureCompanionSheet(
                    reference: companionReference(),
                    translationAbbreviation: translation.abbreviation,
                    visibleVerses: visibleVerseTexts()
                )
            }
            .sheet(isPresented: $showDeeperStudy) {
                SelahBereanContextSheet(
                    reference: companionReference(),
                    translationAbbreviation: translation.abbreviation,
                    verseText: selectedVerseText()
                )
            }
            .sheet(isPresented: $showRewrite) {
                SelahReflectionRewriteSheet()
            }
            .sheet(isPresented: $showAddToChurchNotes) {
                if let verse = selectedVerse() {
                    SelahAddToChurchNotesSheet(
                        verse: verse,
                        translation: translation,
                        mode: .appendReference
                    )
                }
            }
            .sheet(isPresented: $showCreateSermonNote) {
                if let verse = selectedVerse() {
                    SelahAddToChurchNotesSheet(
                        verse: verse,
                        translation: translation,
                        mode: .sermonNote
                    )
                }
            }
            // MARK: - Selah Lens sheets
            .sheet(isPresented: $showSelahStudySheet) {
                if let n = selectedVerseNumber, let text = selectedVerseText() {
                    BereanStudySheetView(
                        verseId: selahVerseId(number: n),
                        verseText: text,
                        translation: selahTranslation,
                        viewModel: lensViewModel,
                        onCrossRefTapped: handleCrossRefTapped
                    )
                }
            }
            .sheet(isPresented: $showSelahReflectionComposer) {
                SelahReflectionComposerView(
                    viewModel: selahReflectionVM,
                    verseReference: selectedVerseNumber.map { n in
                        ScriptureReference(bookId: currentBookId, chapter: currentChapter, startVerse: n, endVerse: nil).displayString
                    } ?? ""
                )
            }
            .fullScreenCover(isPresented: $showGuidedSelahSession) {
                if let n = selectedVerseNumber, let text = selectedVerseText() {
                    GuidedSelahSessionView(
                        verseId: selahVerseId(number: n),
                        verseText: text,
                        translation: selahTranslation,
                        verseReference: ScriptureReference(bookId: currentBookId, chapter: currentChapter, startVerse: n, endVerse: nil).displayString
                    )
                }
            }
            .sabbathFocusMode(sabbathFocusActive)
            .onReceive(NotificationCenter.default.publisher(for: .selahSabbathFocusModeExitRequested)) { _ in
                sabbathFocusActive = false
            }
    }

    private var readerBaseView: some View {
        ZStack {
            canvasTone.ignoresSafeArea() // reading canvas — soft, time-aware
            VStack(spacing: 0) {
                topBar
                studyModeSwitcher
                pagedContent
            }

            // Selah Lens bar — floats above safe area when a verse is selected
            if let verseNumber = selectedVerseNumber,
               let verseText = selectedVerseText() {
                VStack {
                    Spacer()
                    SelahLensBar(
                        verseId: selahVerseId(number: verseNumber),
                        verseText: verseText,
                        translation: selahTranslation,
                        viewModel: lensViewModel,
                        onStudySheet: { showSelahStudySheet = true },
                        onReflect: {
                            selahReflectionVM.verseId = selahVerseId(number: verseNumber)
                            selahReflectionVM.translation = selahTranslation
                            showSelahReflectionComposer = true
                        },
                        onPray: {
                            withAnimation { activeMode = .pray }
                        },
                        onAddToSession: { showGuidedSelahSession = true },
                        onCrossRefs: { showDeeperStudy = true },
                        onDismiss: {
                            withAnimation { selectedVerseNumber = nil }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 90)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: selectedVerseNumber)
            }

            toastOverlay
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            restoreReaderState()
            loadChapterIfNeeded(bookId: currentBookId, chapter: currentChapter)
            recordPosition()
        }
        .onChange(of: currentChapter) { _, _ in
            restoreSelectedVerseForCurrentPage()
            recordPosition()
            playPageTurnIfEnabled()
            loadChapterIfNeeded(bookId: currentBookId, chapter: currentChapter)
        }
        .onChange(of: currentBookId) { _, _ in
            restoreSelectedVerseForCurrentPage()
            recordPosition()
            loadChapterIfNeeded(bookId: currentBookId, chapter: currentChapter)
        }
        .onChange(of: preferencesStore.preferences.translationId) { _, _ in
            restoreSelectedVerseForCurrentPage()
            loadChapterIfNeeded(bookId: currentBookId, chapter: currentChapter)
        }
        .onChange(of: selectedVerseNumber) { _, newVerse in
            let shouldResetLens: Bool = (newVerse == nil)
            persistSelectedVerse()
            restoreDraftsForSelectedVerse()
            recordPosition()
            if shouldResetLens { lensViewModel.reset() }
        }
        .onChange(of: activeMode) { _, mode in
            SelahScriptureReaderHardeningStore.saveMode(mode)
        }
        .onChange(of: reflectionDraft) { _, _ in
            persistDraftsForSelectedVerse()
        }
        .onChange(of: prayerDraft) { _, _ in
            persistDraftsForSelectedVerse()
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            VStack {
                Spacer()
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 96)
            }
            .transition(.opacity)
        }
    }

    private func handleCrossRefTapped(_ crossRefId: String) {
        showSelahStudySheet = false
        let ref = ScriptureReferenceParser.parse(crossRefId)
        let bookId = BibleBook.all.first(where: { $0.displayName.lowercased() == ref.book.lowercased() || $0.abbreviation.lowercased() == ref.book.lowercased() })?.id ?? ref.book.lowercased()
        advance(to: bookId, chapter: ref.chapter)
        selectedVerseNumber = ref.verseStart
    }

    private func companionReference() -> ScriptureReference {
        if let n = selectedVerseNumber {
            return ScriptureReference(
                bookId: currentBookId, chapter: currentChapter,
                startVerse: n, endVerse: nil
            )
        }
        return ScriptureReference(
            bookId: currentBookId, chapter: currentChapter,
            startVerse: nil, endVerse: nil
        )
    }

    private func visibleVerseTexts() -> [String] {
        guard let chapter = chapterCache[pageKey] else { return [] }
        return chapter.verses.map { "\($0.number) \($0.text)" }
    }

    private func selectedVerseText() -> String? {
        guard let n = selectedVerseNumber,
              let chapter = chapterCache[pageKey] else { return nil }
        return chapter.verses.first(where: { $0.number == n })?.text
    }

    private func selectedVerse() -> SelahBibleVerse? {
        guard let n = selectedVerseNumber,
              let chapter = chapterCache[pageKey] else { return nil }
        return chapter.verses.first(where: { $0.number == n })
    }

    private func currentSelectedVerseReference(verseNumber: Int) -> ScriptureReference? {
        ScriptureReference(
            bookId: currentBookId,
            chapter: currentChapter,
            startVerse: verseNumber,
            endVerse: nil
        )
    }

    // MARK: - Top Bar (Liquid Glass)

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 32, height: 32)
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                .contentShape(Circle().size(CGSize(width: 44, height: 44)))
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close reader")

            Spacer(minLength: 0)

            VStack(spacing: 1) {
                Text(book?.displayName ?? currentBookId.capitalized)
                    .font(.system(size: 14, weight: .semibold))
                Text("Chapter \(currentChapter) · \(translation.abbreviation)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                showSearch = true
            } label: {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 32, height: 32)
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                .contentShape(Circle().size(CGSize(width: 44, height: 44)))
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search scripture")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var studyModeSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(SelahScriptureStudyMode.allCases) { mode in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        activeMode = mode
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(activeMode == mode ? mode.tone : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        Capsule(style: .continuous)
                            .fill(activeMode == mode ? mode.tone.opacity(0.10) : Color.clear)
                            .background {
                                if activeMode == mode && !reduceTransparency {
                                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                                }
                            }
                    }
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(activeMode == mode ? mode.tone.opacity(0.22) : Color.clear, lineWidth: 0.7)
                    )
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("\(mode.title) mode")
                .accessibilityHint("Changes the selected verse tools to \(mode.title.lowercased()) actions")
            }
        }
        .padding(5)
        .background {
            Capsule(style: .continuous)
                .fill(reduceTransparency ? Color(.secondarySystemBackground) : AmenTheme.Colors.glassFill)
                .background {
                    if !reduceTransparency {
                        Capsule(style: .continuous).fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorSchemeContrast == .increased ? 0.18 : 0.08), lineWidth: 0.7)
                )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Paged Content

    private var pagedContent: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentChapter) {
                ForEach(1...chapterCount, id: \.self) { ch in
                    chapterPage(chapter: ch)
                        .tag(ch)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .indexViewStyle(.page(backgroundDisplayMode: .never))
            .background(AmenTheme.Colors.backgroundPrimary)

            chapterBoundaryControls
        }
    }

    /// Lightweight previous/next book buttons that appear only at chapter 1
    /// or last chapter. Cleaner than a custom gesture that competes with
    /// TabView's own paging — and accessible to VoiceOver.
    @ViewBuilder
    private var chapterBoundaryControls: some View {
        let currentOrder = book?.canonOrder ?? 0
        let prevBook: BibleBook? = currentChapter == 1
            ? BibleBook.all.first(where: { $0.canonOrder == currentOrder - 1 })
            : nil
        let nextBook: BibleBook? = currentChapter == chapterCount
            ? BibleBook.all.first(where: { $0.canonOrder == currentOrder + 1 })
            : nil

        if prevBook != nil || nextBook != nil {
            HStack {
                if let prev = prevBook {
                    Button {
                        advance(to: prev.id, chapter: prev.chapterCount)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text(prev.displayName)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous book: \(prev.displayName)")
                }
                Spacer()
                if let next = nextBook {
                    Button {
                        advance(to: next.id, chapter: 1)
                    } label: {
                        HStack(spacing: 4) {
                            Text(next.displayName)
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next book: \(next.displayName)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
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
                    chapterUnavailable(message: err, translation: translation)
                        .padding(.horizontal, 22)
                        .padding(.top, 40)
                } else {
                    Color.clear.frame(height: 1)
                        .onAppear { loadChapterIfNeeded(bookId: currentBookId, chapter: chapter) }
                }
            }
        }
        .background(AmenTheme.Colors.backgroundPrimary)
    }

    private func pageHeader(chapter: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((book?.displayName ?? currentBookId.capitalized).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            Text("Chapter \(chapter)")
                .font(.system(size: 26, weight: .bold, design: .serif))
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
        let prayedThrough = engagements.hasPrayedThrough(verse.reference, translationId: translation.id)
        let activeReactions = engagements.reactions(for: verse.reference, translationId: translation.id)
        // Highlight tone derives from the strongest reaction, falling back to peace.
        let highlightTone = activeReactions.first?.kind.tone ?? .peace
        let isSelected = selectedVerseNumber == verse.number
        let isDeepLinked = deepLinkedVerseRange?.contains(verse.number) == true
        let bereanPayload = BereanContextCoordinator.scripturePayload(
            text: verse.text,
            reference: verse.reference.displayString,
            translation: translation.abbreviation
        )

        return Button {
            if isSelected {
                selectedVerseNumber = nil
            } else {
                selectedVerseNumber = verse.number
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(verse.number)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verse.text)
                        .font(.system(size: preferencesStore.preferences.fontPointSize, design: .serif))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if prayedThrough || !activeReactions.isEmpty {
                        HStack(spacing: 6) {
                            if prayedThrough {
                                HStack(spacing: 3) {
                                    Image(systemName: "hands.sparkles.fill")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text("Prayed through")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(Color.accentColor.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.10), in: Capsule())
                            }
                            ForEach(activeReactions.prefix(3)) { entry in
                                Image(systemName: entry.kind.icon)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(4)
                                    .background(entry.kind.tone.fill, in: Circle())
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected || isDeepLinked ? highlightTone.fill :
                          (!activeReactions.isEmpty ? highlightTone.fill.opacity(0.4) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bereanContextActions(payload: bereanPayload)
        .accessibilityLabel("Verse \(verse.number)\(isDeepLinked ? ", opened from message" : "")\(prayedThrough ? ", prayed through" : "")")
        .accessibilityHint("Tap to select, or long press for Berean actions")
    }

    private func footerActions(for chapter: SelahBibleChapter) -> [(title: String, view: AnyView)] {
        var actions: [(title: String, view: AnyView)] = []
        if let selected = selectedVerseNumber,
           let verse = chapter.verses.first(where: { $0.number == selected }) {
            actions.append((
                title: "toolbar",
                view: AnyView(
                    Group { selectedVerseStudySurface(verse) }
                        .padding(.top, 12)
                        .padding(.bottom, 16)
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
                            .font(.system(size: 14, weight: .medium))
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
                            .font(.system(size: 14, weight: .medium))
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
                            .font(.system(size: 13, weight: .medium))
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
    private func selectedVerseStudySurface(_ verse: SelahBibleVerse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch activeMode {
            case .read:
                readActionSurface(verse)
            case .study:
                studyActionSurface(verse)
            case .reflect:
                reflectionActionSurface(verse)
            case .pray:
                prayerActionSurface(verse)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(reduceTransparency ? Color(.secondarySystemBackground) : AmenTheme.Colors.glassFill)
                .background {
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(activeMode.tone.opacity(colorSchemeContrast == .increased ? 0.34 : 0.18), lineWidth: 0.8)
                )
        }
    }

    private func readActionSurface(_ verse: SelahBibleVerse) -> some View {
        VStack(spacing: 8) {
            SelahFloatingVerseActionToolbar(
                onCopy: { copy(verse) },
                onSave: { save(verse) },
                onReflect: {
                    activeMode = .reflect
                    reflect(verse)
                },
                onPray: {
                    activeMode = .pray
                    togglePrayedThrough(verse)
                }
            )
            compactOverflowActions(verse)
        }
    }

    private func studyActionSurface(_ verse: SelahBibleVerse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                footerChip("Context", system: "books.vertical") { showDeeperStudy = true }
                footerChip("Ask", system: "sparkles") {
                    openCompanion(prompt: "What does this passage mean in context?")
                }
                compactOverflowActions(verse)
            }
            if AMENFeatureFlags.shared.bereanLiquidGlassContextActionsEnabled {
                BereanFloatingActionTray(
                    payload: BereanContextCoordinator.scripturePayload(
                        text: verse.text,
                        reference: verse.reference.displayString,
                        translation: translation.abbreviation
                    ),
                    actions: BereanContextMenuManager.shared.compactActions
                ) { action in
                    BereanContextMenuManager.shared.activate(
                        payload: BereanContextCoordinator.scripturePayload(
                            text: verse.text,
                            reference: verse.reference.displayString,
                            translation: translation.abbreviation
                        ),
                        action: action
                    )
                }
            }
        }
    }

    private func reflectionActionSurface(_ verse: SelahBibleVerse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reflection")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $reflectionDraft)
                .font(.system(size: 14))
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
                )
                .accessibilityLabel("Private reflection draft")
                .accessibilityHint("Saved locally while you type and cleared only after you save it")
            HStack(spacing: 8) {
                footerChip("Save", system: "checkmark.circle") {
                    saveReflectionDraft(for: verse)
                }
                if SelahAIAccessGate.shared.currentState().isAvailable {
                    footerChip("Rewrite", system: "wand.and.stars") { showRewrite = true }
                }
                compactOverflowActions(verse)
            }
        }
    }

    private func prayerActionSurface(_ verse: SelahBibleVerse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prayer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $prayerDraft)
                .font(.system(size: 14))
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
                )
                .accessibilityLabel("Private prayer draft")
                .accessibilityHint("Saved locally while you type and cleared only after you mark it prayed")
            HStack(spacing: 8) {
                footerChip("Prayed", system: "hands.sparkles") { savePrayerDraft(for: verse) }
                if SelahAIAccessGate.shared.currentState().isAvailable {
                    footerChip("Guide", system: "sparkles") {
                        openCompanion(prompt: "How should I pray through this passage?")
                    }
                }
                compactOverflowActions(verse)
            }
        }
    }

    private func compactOverflowActions(_ verse: SelahBibleVerse) -> some View {
        Menu {
            Button("Copy", systemImage: "doc.on.doc") { copy(verse) }
            Button("Save", systemImage: "bookmark") { save(verse) }
            Button("React", systemImage: "heart.text.square") { showReactionPicker = true }
            if AMENFeatureFlags.shared.selahAddToChurchNotesEnabled {
                Button("Add to Notes", systemImage: "square.and.pencil") { showAddToChurchNotes = true }
                Button("Sermon Note", systemImage: "doc.badge.plus") { showCreateSermonNote = true }
            }
            if SelahAIAccessGate.shared.currentState().isAvailable {
                Button("Deeper Study", systemImage: "books.vertical") { showDeeperStudy = true }
                Button("Scripture Companion", systemImage: "sparkles") { openCompanion(prompt: nil) }
                Button("Rewrite Reflection", systemImage: "wand.and.stars") { showRewrite = true }
                Button("Ask Later", systemImage: "clock.badge.questionmark") { askBereanLater(verse) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More verse actions")
    }

    private func footerChip(_ label: String, system icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.primary.opacity(colorSchemeContrast == .increased ? 0.88 : 0.66))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .background {
                Capsule(style: .continuous)
                    .fill(reduceTransparency ? Color(.secondarySystemBackground) : Color.white.opacity(0.13))
                    .background {
                        if !reduceTransparency {
                            Capsule(style: .continuous).fill(.ultraThinMaterial)
                        }
                    }
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.7)
                    )
            }
        }
        .buttonStyle(SelahGlassPressButtonStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func chapterUnavailable(message: String, translation: SelahBibleTranslation) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Chapter not available")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if translation.id != SelahBibleTranslation.kjv.id {
                AmenLiquidGlassPillButton(
                    title: "Try KJV",
                    systemImage: "book",
                    isLoading: false,
                    isDisabled: false,
                    hint: "Switches to the bundled public-domain KJV translation for this passage",
                    action: {
                        preferencesStore.setTranslation(SelahBibleTranslation.kjv.id)
                        loadChapterIfNeeded(bookId: currentBookId, chapter: currentChapter)
                    }
                )
            }
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

    private func openCompanion(prompt: String?) {
        companionPrompt = prompt
        showCompanion = true
    }

    private func askBereanLater(_ verse: SelahBibleVerse) {
        let entry = SelahScriptureHighlightEntry(
            reference: verse.reference,
            translationId: translation.id,
            toneKey: "question"
        )
        SelahSavedScriptureStore.shared.addHighlight(entry)
        AMENAnalyticsService.shared.track(.bereanStudyActionStarted(action: "ask_later"))
        flash("Saved for Berean later")
    }

    private func togglePrayedThrough(_ verse: SelahBibleVerse) {
        let wasPrayed = engagements.hasPrayedThrough(verse.reference, translationId: translation.id)
        engagements.togglePrayedThrough(verse.reference, translationId: translation.id)
        flash(wasPrayed ? "Removed prayer marker" : "Prayed through \(verse.reference.displayString)")
    }

    private func saveReflectionDraft(for verse: SelahBibleVerse) {
        let trimmed = reflectionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldAllowDraftSave(trimmed) else { return }
        let tone = trimmed.isEmpty ? "peace" : "reflection"
        SelahSavedScriptureStore.shared.addHighlight(
            SelahScriptureHighlightEntry(reference: verse.reference, translationId: translation.id, toneKey: tone)
        )
        if !trimmed.isEmpty {
            reflectionDraft = ""
            SelahScriptureReaderHardeningStore.clearReflection(for: verse.reference, translationId: translation.id)
        }
        flash("Reflection saved for \(verse.reference.displayString)")
    }

    private func savePrayerDraft(for verse: SelahBibleVerse) {
        let trimmed = prayerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldAllowDraftSave(trimmed) else { return }
        let wasPrayed = engagements.hasPrayedThrough(verse.reference, translationId: translation.id)
        if !wasPrayed {
            engagements.togglePrayedThrough(verse.reference, translationId: translation.id)
        }
        if !trimmed.isEmpty {
            SelahSavedScriptureStore.shared.addHighlight(
                SelahScriptureHighlightEntry(reference: verse.reference, translationId: translation.id, toneKey: "prayer")
            )
            prayerDraft = ""
            SelahScriptureReaderHardeningStore.clearPrayer(for: verse.reference, translationId: translation.id)
        }
        flash("Prayer marked for \(verse.reference.displayString)")
    }

    // MARK: - Persistence + Safety

    private func restoreReaderState() {
        activeMode = SelahScriptureReaderHardeningStore.loadMode()
        if initialReference.startVerse == nil {
            restoreSelectedVerseForCurrentPage()
        } else {
            restoreDraftsForSelectedVerse()
        }
    }

    private func restoreSelectedVerseForCurrentPage() {
        let restored = SelahScriptureReaderHardeningStore.loadSelectedVerse(
            bookId: currentBookId,
            chapter: currentChapter,
            translationId: translation.id
        )
        selectedVerseNumber = restored
        restoreDraftsForSelectedVerse()
    }

    private func persistSelectedVerse() {
        SelahScriptureReaderHardeningStore.saveSelectedVerse(
            selectedVerseNumber,
            bookId: currentBookId,
            chapter: currentChapter,
            translationId: translation.id
        )
    }

    private func restoreDraftsForSelectedVerse() {
        guard let reference = selectedDraftReference() else {
            isRestoringDrafts = true
            reflectionDraft = ""
            prayerDraft = ""
            isRestoringDrafts = false
            return
        }
        let draft = SelahScriptureReaderHardeningStore.loadDraft(for: reference, translationId: translation.id)
        isRestoringDrafts = true
        reflectionDraft = draft.reflection
        prayerDraft = draft.prayer
        isRestoringDrafts = false
    }

    private func persistDraftsForSelectedVerse() {
        guard !isRestoringDrafts, let reference = selectedDraftReference() else { return }
        SelahScriptureReaderHardeningStore.saveDraft(
            reflection: reflectionDraft,
            prayer: prayerDraft,
            for: reference,
            translationId: translation.id
        )
    }

    private func selectedDraftReference() -> ScriptureReference? {
        guard let selectedVerseNumber else { return nil }
        return ScriptureReference(
            bookId: currentBookId,
            chapter: currentChapter,
            startVerse: selectedVerseNumber,
            endVerse: nil
        )
    }

    private func shouldAllowDraftSave(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        if case .blockedCrisis(let careMessage) = SelahAISafetyPreflight.evaluate(text) {
            persistDraftsForSelectedVerse()
            crisisSupportMessage = careMessage
            return false
        }
        return true
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

    // MARK: - Selah Lens Helpers

    private func selahVerseId(number: Int) -> String {
        "\(currentBookId)_\(currentChapter)_\(number)"
    }

    private var selahTranslation: SelahTranslation {
        translation.id.lowercased().contains("esv") ? .esv : .kjv
    }
}

private struct SelahAddToChurchNotesSheet: View {
    enum Mode {
        case appendReference
        case sermonNote

        var title: String {
            switch self {
            case .appendReference: return "Add to Church Notes"
            case .sermonNote: return "Create Sermon Note"
            }
        }
    }

    let verse: SelahBibleVerse
    let translation: SelahBibleTranslation
    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @StateObject private var notesService = ChurchNotesService()
    @State private var noteTitle = ""
    @State private var reflection = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canStoreVerseText: Bool {
        translation.license == .publicDomain
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scripture") {
                    Text(verse.reference.displayString)
                        .font(.headline)
                    if canStoreVerseText {
                        Text(verse.text)
                    } else {
                        Text("This translation is not stored in Church Notes. The reference will be saved.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Private note") {
                    TextField("Title", text: $noteTitle)
                    TextEditor(text: $reflection)
                        .frame(minHeight: 120)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear {
                if noteTitle.isEmpty {
                    noteTitle = mode == .sermonNote ? "Sermon Note - \(verse.reference.displayString)" : "Study Note - \(verse.reference.displayString)"
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Please sign in to save this note."
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        var content = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        if canStoreVerseText {
            let quoted = "\(verse.reference.displayString) (\(translation.abbreviation))\n\(verse.text)"
            content = content.isEmpty ? quoted : "\(quoted)\n\n\(content)"
        } else if content.isEmpty {
            content = verse.reference.displayString
        }

        let note = ChurchNote(
            userId: userId,
            title: noteTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            sermonTitle: mode == .sermonNote ? verse.reference.displayString : nil,
            content: content,
            scripture: verse.reference.displayString,
            tags: mode == .sermonNote ? ["sermon", "selah"] : ["selah"],
            scriptureReferences: [verse.reference.displayString]
        )

        do {
            _ = try await notesService.createNote(note)
            AMENAnalyticsService.shared.track(.selahVerseAddedToChurchNotes)
            AMENAnalyticsService.shared.track(.scriptureAddedToChurchNote(source: "selah"))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
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
