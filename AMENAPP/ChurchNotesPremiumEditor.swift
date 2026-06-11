//
//  ChurchNotesPremiumEditor.swift
//  AMENAPP
//
//  Production-grade Church Notes editor with liquid glass design.
//  One primary writing surface, no duplicate actions, contextual intelligence.
//

import SwiftUI
import FirebaseAuth
import FirebaseFunctions

// MARK: - Premium Church Note Editor

struct ChurchNotesPremiumEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var notesService: ChurchNotesService

    let existingNote: ChurchNote?

    // MARK: - State

    @State private var title = ""
    @State private var sermonTitle = ""
    @State private var churchName = ""
    @State private var pastor = ""
    @State private var selectedDate = Date()
    @State private var content = ""
    @State private var scripture = ""

    // Personal growth
    @State private var actionStep = ""
    @State private var prayerFromSermon = ""
    @State private var shouldRevisit = false
    @State private var growthExpanded = false

    // Worship songs
    @State private var worshipSongs: [WorshipSongReference] = []
    @State private var showSongSearch = false

    // Scripture
    @State private var scriptureChips: [String] = []
    @State private var suggestedScriptures: [ScriptureThemeSuggestion] = []
    @State private var detectedScriptures: [String] = []

    // Rich text editing
    @State private var attributedText: NSAttributedString = NSAttributedString()
    @State private var selectionRange: NSRange? = nil
    @State private var activeFormats = ChurchNoteActiveFormats()
    @State private var editorIsFirstResponder = false
    @State private var formattingCommand: ChurchNoteRichEditorView.FormattingCommand? = nil
    @State private var editorCoordinator: ChurchNoteRichEditorView.Coordinator? = nil
    @State private var showSelectionToolbar = false

    // Blocks & tags
    @State private var blocks: [ChurchNoteBlock] = []
    @State private var noteTags: [String] = []

    // Review mode
    @State private var isReviewMode = false

    // UI state
    @State private var isSaving = false
    @State private var hasUnsavedChanges = false
    @State private var showUnsavedAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var autosaveState: AutosaveState = .idle
    @State private var scrollOffset: CGFloat = 0
    @State private var showActionCapsule = true
    @State private var activeFormatting: Set<NoteTextStyle> = []
    @State private var showFormattingBar = false
    @State private var metadataExpanded = true
    @State private var contentAppeared = false
    @State private var restoredLocalDraftDate: Date?
    @State private var showChurchSearch = false
    @State private var contextualActionInFlight: ContextualNoteAction.Kind?

    // Autosave
    @State private var contentChangeTask: Task<Void, Never>?
    @StateObject private var autosaveService = ChurchNotesAutosaveService()

    // Keyboard
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var focusedField: EditorField?

    enum EditorField {
        case title, content, actionStep, prayer
    }

    enum AutosaveState {
        case idle, saving, saved
    }

    var isEditMode: Bool { existingNote != nil }
    var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var persistenceService: ChurchNotesPersistenceService { ChurchNotesPersistenceService(notesService: notesService) }
    private var localDraftKey: String { existingNote?.id ?? "new" }
    private let commandApplier = RichTextCommandApplier()
    private let localDraftService = ChurchNotesLocalDraftService.shared
    private let aiService = ChurchNotesAIService.shared
    private let reminderService = ChurchNotesReminderService.shared
    private var reviewSummary: ChurchNoteReviewSummary {
        ChurchNotesReviewSummaryService.shared.summary(for: attributedText, blocks: blocks)
    }

    // MARK: - Init

    init(notesService: ChurchNotesService, existingNote: ChurchNote? = nil) {
        self.notesService = notesService
        self.existingNote = existingNote

        if let note = existingNote {
            _title = State(initialValue: note.title)
            _sermonTitle = State(initialValue: note.sermonTitle ?? "")
            _churchName = State(initialValue: note.churchName ?? "")
            _pastor = State(initialValue: note.pastor ?? "")
            _selectedDate = State(initialValue: note.date)
            _content = State(initialValue: note.content)
            _scripture = State(initialValue: note.scripture ?? "")
            _scriptureChips = State(initialValue: note.scriptureReferences)
            _worshipSongs = State(initialValue: note.worshipSongs)
            _actionStep = State(initialValue: note.actionStepThisWeek ?? "")
            _prayerFromSermon = State(initialValue: note.prayerFromSermon ?? "")
            _shouldRevisit = State(initialValue: note.shouldRevisit)
            _metadataExpanded = State(initialValue: false)

            // Rich content
            if let doc = note.richTextDocument {
                let engine = AttributedStringFormatter()
                _attributedText = State(initialValue: engine.decode(document: doc))
            } else if !note.content.isEmpty {
                _attributedText = State(initialValue: NSAttributedString(
                    string: note.content,
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .body),
                        .foregroundColor: UIColor.label
                    ]
                ))
            }

            // Blocks & tags
            _blocks = State(initialValue: note.blocks)
            _noteTags = State(initialValue: note.tags)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Sticky header
                stickyHeader

                // Main scrollable content
                ScrollView {
                    scrollOffsetReader
                    
                    VStack(alignment: .leading, spacing: 20) {
                        metadataCard
                            .padding(.top, 12)

                        mainNoteCard

                        scriptureSection

                        contextualIntelligenceStrip

                        personalGrowthCard

                        worshipCard

                        // Bottom padding for action capsule
                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.horizontal, 16)
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 12)
                }
                .coordinateSpace(name: "noteScroll")
            }
            .scrollEdgeTopBlur(scrollOffset: scrollOffset, panelHeight: 0)

            // Bottom action capsule
            if showActionCapsule && keyboardHeight == 0 {
                actionCapsule
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Formatting bar (above keyboard)
            if showFormattingBar && keyboardHeight > 0 {
                formattingBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8)), value: showActionCapsule)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.85)), value: showFormattingBar)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Discard", role: .destructive) {
                clearLocalDraft()
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showSongSearch) {
            SongSearchSheet { song in
                if !worshipSongs.contains(where: { $0.title == song.title && $0.artist == song.artist }) {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                        worshipSongs.append(song)
                    }
                    markChanged()
                }
            }
        }
        .sheet(isPresented: $showChurchSearch) {
            ChurchNotesChurchSearchSheet(
                initialQuery: churchName,
                onSelect: { church in
                    churchName = church.name
                    if pastor.isEmpty, let seniorPastor = church.seniorPastorName {
                        pastor = seniorPastor
                    }
                    showChurchSearch = false
                    markChanged()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            restoreLocalDraftIfNeeded()
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.82)).delay(0.05)) {
                contentAppeared = true
            }
            observeKeyboard()
        }
    }

    // MARK: - Sticky Header

    private var stickyHeader: some View {
        HStack {
            Button {
                if hasUnsavedChanges {
                    showUnsavedAlert = true
                } else {
                    dismiss()
                }
            } label: {
                Text("Cancel")
                    .font(.systemScaled(16, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Church Note")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)

                autosaveIndicator
            }

            Spacer()

            Button {
                saveNote()
            } label: {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Done")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(canSave ? Color.primary : Color.secondary.opacity(0.5))
                }
            }
            .disabled(!canSave || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(min(1, max(0, -scrollOffset / 50)))
        )
    }

    @ViewBuilder
    private var autosaveIndicator: some View {
        if restoredLocalDraftDate != nil && autosaveState == .idle {
            HStack(spacing: 3) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.systemScaled(9))
                    .foregroundStyle(.green.opacity(0.7))
                Text("Draft restored")
                    .font(.systemScaled(10))
                    .foregroundStyle(.tertiary)
            }
            .transition(.opacity)
        } else {
            autosaveStatusIndicator
        }
    }

    @ViewBuilder
    private var autosaveStatusIndicator: some View {
        switch autosaveState {
        case .idle:
            EmptyView()
        case .saving:
            HStack(spacing: 3) {
                ProgressView().scaleEffect(0.5)
                Text("Saving…")
                    .font(.systemScaled(10))
                    .foregroundStyle(.tertiary)
            }
            .transition(.opacity)
        case .saved:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.systemScaled(9))
                    .foregroundStyle(.green.opacity(0.7))
                Text("Saved")
                    .font(.systemScaled(10))
                    .foregroundStyle(.tertiary)
            }
            .transition(.opacity)
        }
    }

    // MARK: - Scroll Offset Reader

    private var scrollOffsetReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: NoteScrollOffsetKey.self,
                    value: proxy.frame(in: .named("noteScroll")).minY
                )
        }
        .frame(height: 0)
        .onPreferenceChange(NoteScrollOffsetKey.self) { value in
            if abs(value - scrollOffset) >= 1 {
                scrollOffset = value
            }
        }
    }

    // MARK: - Metadata Card

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed summary
            if !metadataExpanded {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.78))) {
                        metadataExpanded = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(metadataExpanded ? 90 : 0))

                        Text(metadataSummary)
                            .font(.systemScaled(13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            }

            // Expanded fields
            if metadataExpanded {
                VStack(spacing: 10) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "cross")
                                .font(.systemScaled(10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            Text("SERMON DETAILS")
                                .font(.systemScaled(11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .tracking(0.8)
                        }

                        Spacer()

                        if !metadataSummary.isEmpty {
                            Button {
                                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.78))) {
                                    metadataExpanded = false
                                }
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.systemScaled(11, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .padding(6)
                                    .background(Circle().fill(Color.primary.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)

                    Button {
                        showChurchSearch = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "building.2")
                                .font(.systemScaled(14))
                                .foregroundStyle(.tertiary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(churchName.isEmpty ? "Search churches" : churchName)
                                    .font(.systemScaled(15))
                                    .foregroundStyle(churchName.isEmpty ? .secondary : .primary)
                                    .lineLimit(1)
                                Text("Find a Church directory")
                                    .font(.systemScaled(11, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Image(systemName: "magnifyingglass")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(ChurchNotesDesignTokens.Colors.personalTint)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                                )
                        )
                        .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(churchName.isEmpty ? "Search churches" : "Selected church, \(churchName)")

                    NoteGlassTextField(icon: "person", placeholder: "Pastor", text: $pastor)
                        .onChange(of: pastor) { _, _ in markChanged() }

                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.systemScaled(14))
                            .foregroundStyle(.tertiary)
                            .frame(width: 20)

                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var metadataSummary: String {
        let date = selectedDate.formatted(.dateTime.month(.abbreviated).day())
        let parts: [String?] = [
            date,
            churchName.isEmpty ? nil : churchName,
            pastor.isEmpty ? nil : pastor
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Main Note Card

    private var mainNoteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            noteCardTitleSection
            noteCardTagSection
            noteCardDividerWithReviewToggle
            noteCardContentSection
            noteCardBlocksSection
        }
        .background(noteCardBackground)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }

    private var noteCardTitleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Note Title", text: $title, axis: .vertical)
                .font(.systemScaled(28, weight: .semibold))
                .foregroundStyle(.primary)
                .focused($focusedField, equals: .title)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 4)
                .onChange(of: title) { _, _ in markChanged() }

            TextField("Sermon title (optional)", text: $sermonTitle)
                .font(.systemScaled(15))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .onChange(of: sermonTitle) { _, _ in markChanged() }
        }
    }

    private var noteCardTagSection: some View {
        ChurchNotesTagTray(appliedTags: $noteTags, noteContent: content)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .onChange(of: noteTags) { _, _ in markChanged() }
    }

    private var noteCardDividerWithReviewToggle: some View {
        HStack {
            VStack { Divider() }
                .padding(.leading, 16)

            Spacer()

            Button {
                withAnimation(CNToken.Anim.reviewToggle) {
                    isReviewMode.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isReviewMode ? "pencil" : "eye")
                        .font(.systemScaled(11, weight: .medium))
                    Text(isReviewMode ? "Edit" : "Review")
                        .font(.systemScaled(11, weight: .medium))
                }
                .foregroundStyle(isReviewMode ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isReviewMode ? Color.primary.opacity(0.08) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var noteCardContentSection: some View {
        if isReviewMode {
            VStack(alignment: .leading, spacing: 12) {
                ChurchNotesReviewSummaryView(summary: reviewSummary)
                ChurchNoteReviewMode(
                    attributedText: attributedText,
                    blocks: blocks,
                    tags: noteTags
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        } else {
            noteCardEditorWithToolbar
        }
    }

    private var noteCardEditorWithToolbar: some View {
        ZStack(alignment: .top) {
            RichChurchNoteEditor(
                attributedText: $attributedText,
                plainText: $content,
                selectionRange: $selectionRange,
                activeFormats: $activeFormats,
                isFirstResponder: $editorIsFirstResponder,
                formattingCommand: formattingCommand,
                onCommandExecuted: {
                    formattingCommand = nil
                },
                onCoordinatorReady: { coordinator in
                    editorCoordinator = coordinator
                }
            )
            .frame(minHeight: 240)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .onChange(of: content) { _, newValue in
                handleContentChange(newValue)
            }
            .onChange(of: selectionRange) { _, newRange in
                let hasSelection = newRange != nil && newRange!.length > 0
                withAnimation(CNToken.Anim.quickTap) {
                    showSelectionToolbar = hasSelection
                }
            }

            if showSelectionToolbar {
                selectionToolbarOverlay
            }
        }
    }

    private var selectionToolbarOverlay: some View {
        ChurchNotesSelectionToolbar(
            activeFormats: activeFormats,
            hasSelection: selectionRange != nil,
            onBold: {
                formattingCommand = .bold
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            onItalic: {
                formattingCommand = .italic
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            onUnderline: {
                formattingCommand = .underline
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            onHighlight: { type in
                formattingCommand = .highlight(type)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            onRemoveHighlight: {
                formattingCommand = .removeHighlight
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            onConvertBlock: { blockType in
                convertSelectionToBlock(blockType)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        )
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }

    @ViewBuilder
    private var noteCardBlocksSection: some View {
        if !blocks.isEmpty {
            VStack(spacing: 8) {
                ForEach(blocks) { block in
                    ChurchNoteBlockView(
                        block: block,
                        onDelete: {
                            withAnimation(CNToken.Anim.chipInsert) {
                                blocks.removeAll { $0.id == block.id }
                            }
                            markChanged()
                        },
                        onUpdate: { updated in
                            if let idx = blocks.firstIndex(where: { $0.id == updated.id }) {
                                blocks[idx] = updated
                                markChanged()
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var noteCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        editorIsFirstResponder || focusedField == .title
                            ? Color.primary.opacity(0.12)
                            : Color.primary.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
    }

    // MARK: - Scripture Section

    private var scriptureSection: some View {
        ChurchNotesScriptureSection(
            inputText: $scripture,
            scriptureReferences: $scriptureChips,
            detected: detectedScriptures.map { ChurchNoteScriptureReference(reference: $0) },
            suggested: suggestedScriptures.map { ChurchNoteScriptureReference(reference: $0.reference) },
            onChanged: markChanged
        )
    }

    private func scriptureChip(_ ref: String) -> some View {
        HStack(spacing: 4) {
            Text(ref)
                .font(.systemScaled(12, weight: .medium))
                .foregroundStyle(.primary)

            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                    scriptureChips.removeAll { $0 == ref }
                }
                markChanged()
            } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.05))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        )
        .transition(.scale.combined(with: .opacity))
    }

    private func addScriptureChip() {
        let ref = scripture.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty, !scriptureChips.contains(ref) else { return }
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
            scriptureChips.append(ref)
            scripture = ""
        }
        markChanged()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Contextual Intelligence

    @ViewBuilder
    private var contextualIntelligenceStrip: some View {
        let actions = contextualActions
        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(ChurchNotesDesignTokens.Colors.personalTint)
                    Text("Berean suggestions")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(actions) { action in
                            Button {
                                handleContextualAction(action.kind)
                            } label: {
                                HStack(spacing: 6) {
                                    if contextualActionInFlight == action.kind {
                                        ProgressView()
                                            .scaleEffect(0.65)
                                    } else {
                                        Image(systemName: action.icon)
                                            .font(.systemScaled(12, weight: .semibold))
                                    }
                                    Text(action.title)
                                        .lineLimit(1)
                                }
                                .font(.systemScaled(12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.thinMaterial, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .disabled(contextualActionInFlight != nil)
                            .accessibilityLabel(action.title)
                        }
                    }
                }
            }
            .padding(14)
            .churchNotesGlassCard()
        }
    }

    private var contextualActions: [ContextualNoteAction] {
        var actions: [ContextualNoteAction] = []
        let detectedToAttach = detectedScriptures.filter { !scriptureChips.contains($0) }
        if !detectedToAttach.isEmpty {
            actions.append(.init(kind: .attachDetectedScripture, title: "Attach \(detectedToAttach.count) scripture", icon: "book.closed"))
        }
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prayerFromSermon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            actions.append(.init(kind: .createPrayerPrompt, title: "Create prayer", icon: "hands.sparkles"))
        }
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && actionStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            actions.append(.init(kind: .createActionStep, title: "Create action", icon: "checkmark.circle"))
        }
        if !shouldRevisit && (!actionStep.isEmpty || !prayerFromSermon.isEmpty || !blocks.isEmpty) {
            actions.append(.init(kind: .scheduleMidweek, title: "Remind midweek", icon: "calendar.badge.clock"))
        }
        if !isReviewMode && (!blocks.isEmpty || !scriptureChips.isEmpty || !content.isEmpty) {
            actions.append(.init(kind: .openReview, title: "Preview note", icon: "eye"))
        }
        return actions
    }

    private func handleContextualAction(_ kind: ContextualNoteAction.Kind) {
        guard contextualActionInFlight == nil else { return }
        contextualActionInFlight = kind
        Task {
            defer { contextualActionInFlight = nil }
            do {
                switch kind {
                case .attachDetectedScripture:
                    let additions = detectedScriptures.filter { !scriptureChips.contains($0) }
                    scriptureChips.append(contentsOf: additions)
                case .createPrayerPrompt:
                    prayerFromSermon = try await aiService.generatePrayer(currentNoteSnapshot(), userId: currentUserIdForAI())
                case .createActionStep:
                    actionStep = firstActionLine(from: try await aiService.extractKeyTakeaways(currentNoteSnapshot(), userId: currentUserIdForAI()))
                case .scheduleMidweek:
                    try await reminderService.scheduleMidweekReminder(
                        noteTitle: title.isEmpty ? sermonTitle : title,
                        serviceDate: selectedDate,
                        draftKey: localDraftKey
                    )
                    shouldRevisit = true
                case .openReview:
                    withAnimation(CNToken.Anim.reviewToggle) { isReviewMode = true }
                }
                markChanged()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func currentNoteSnapshot() throws -> ChurchNote {
        try persistenceService.buildNote(
            from: existingNote,
            title: title.isEmpty ? "Untitled Church Note" : title,
            sermonTitle: sermonTitle,
            metadata: ChurchNoteMetadata(
                churchName: churchName,
                pastorName: pastor,
                serviceDate: selectedDate
            ),
            content: content,
            attributedText: attributedText,
            blocks: blocks,
            tags: noteTags,
            scriptureReferences: scriptureChips,
            worshipSongs: worshipSongs,
            actionStep: actionStep,
            prayer: prayerFromSermon,
            revisitMidweek: shouldRevisit
        )
    }

    private func currentUserIdForAI() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "ChurchNotesEditor",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Sign in to use Berean suggestions."]
            )
        }
        return uid
    }

    private func firstActionLine(from text: String) -> String {
        var trimSet = CharacterSet.whitespacesAndNewlines
        trimSet.formUnion(CharacterSet(charactersIn: " •-*0123456789."))
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: trimSet) }
            .first { !$0.isEmpty }
            ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ContextualNoteAction: Identifiable, Equatable {
        enum Kind: Hashable {
            case attachDetectedScripture
            case createPrayerPrompt
            case createActionStep
            case scheduleMidweek
            case openReview
        }

        var id: Kind { kind }
        let kind: Kind
        let title: String
        let icon: String
    }

    // MARK: - Personal Growth Card

    private var personalGrowthCard: some View {
        ChurchNotesGrowthCard(
            actionStep: $actionStep,
            prayer: $prayerFromSermon,
            revisitMidweek: $shouldRevisit,
            isExpanded: $growthExpanded,
            onChanged: markChanged
        )
    }

    // MARK: - Worship Card

    private var worshipCard: some View {
        ChurchNotesWorshipCard(
            songs: worshipSongs,
            onAdd: {
                showSongSearch = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            onRemove: { songID in
                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                    worshipSongs.removeAll { $0.id == songID }
                }
                markChanged()
            }
        )
    }

    private var worshipFallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay(
                Image(systemName: "music.note")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.55))
            )
    }

    private func worshipSubtitle(for song: WorshipSongReference) -> String {
        let base = song.subtitle ?? song.artist
        let helper = song.availabilityState.helperText
        return base.isEmpty ? helper : "\(base) · \(helper)"
    }

    // MARK: - Bottom Action Capsule

    private var actionCapsule: some View {
        ChurchNotesBottomActionCapsule(
            actions: CapsuleAction.allCases.map { action in
                .init(
                    id: action.rawValue,
                    label: action.label,
                    icon: action.icon,
                    handler: {
                        handleCapsuleAction(action)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
        )
        .shadow(color: ChurchNotesDesignTokens.Shadow.capsule.color, radius: ChurchNotesDesignTokens.Shadow.capsule.radius, y: ChurchNotesDesignTokens.Shadow.capsule.y)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    // MARK: - Formatting Bar

    private var formattingBar: some View {
        ChurchNotesFormattingToolbar(
            activeFormats: activeFormats,
            activeHighlight: activeFormats.highlightType,
            hasSelection: selectionRange != nil,
            onBold: {
                formattingCommand = .bold
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            onItalic: {
                formattingCommand = .italic
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            onUnderline: {
                formattingCommand = .underline
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            onHighlight: { type in
                if activeFormats.highlightType == type {
                    formattingCommand = .removeHighlight
                } else {
                    formattingCommand = .highlight(type)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            onBlockConvert: { blockType in
                convertSelectionToBlock(blockType)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        )
    }

    // MARK: - Capsule Actions

    enum CapsuleAction: String, CaseIterable, Identifiable {
        case format, scripture, prayer, action, review

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .format: return "textformat"
            case .scripture: return "book"
            case .prayer: return "hands.sparkles"
            case .action: return "checkmark.circle"
            case .review: return "eye"
            }
        }

        var label: String {
            switch self {
            case .format: return "Format"
            case .scripture: return "Scripture"
            case .prayer: return "Prayer"
            case .action: return "Action"
            case .review: return "Review"
            }
        }
    }

    private func handleCapsuleAction(_ action: CapsuleAction) {
        switch action {
        case .format:
            editorIsFirstResponder = true
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.85))) {
                showFormattingBar.toggle()
            }
        case .scripture:
            insertBlockFromCapsule(.scripture, template: "Scripture: ")
        case .prayer:
            insertBlockFromCapsule(.prayer, template: "Prayer: ")
        case .action:
            insertBlockFromCapsule(.action, template: "Action step: ")
        case .review:
            withAnimation(CNToken.Anim.reviewToggle) {
                isReviewMode.toggle()
            }
        }
    }

    /// Insert a semantic block directly from capsule action instead of appending plain text.
    private func insertBlockFromCapsule(_ blockType: ChurchNoteBlockType, template: String) {
        let newBlock = ChurchNoteBlock(type: blockType, text: template)
        withAnimation(CNToken.Anim.smoothExpand) {
            blocks.append(newBlock)
        }
        markChanged()
    }

    // MARK: - Local Drafts

    private func saveLocalDraftSnapshot() {
        let draft = ChurchNotesLocalDraft(
            key: localDraftKey,
            title: title,
            sermonTitle: sermonTitle,
            churchName: churchName,
            pastor: pastor,
            selectedDate: selectedDate,
            content: content,
            scriptureInput: scripture,
            scriptureReferences: scriptureChips,
            actionStep: actionStep,
            prayer: prayerFromSermon,
            shouldRevisit: shouldRevisit,
            worshipSongs: worshipSongs,
            blocks: blocks,
            noteTags: noteTags,
            updatedAt: Date()
        )
        localDraftService.save(draft)
    }

    private func restoreLocalDraftIfNeeded() {
        guard let draft = localDraftService.load(key: localDraftKey), draft.hasMeaningfulContent else { return }
        if let existingNote, draft.updatedAt <= existingNote.updatedAt { return }

        title = draft.title
        sermonTitle = draft.sermonTitle
        churchName = draft.churchName
        pastor = draft.pastor
        selectedDate = draft.selectedDate
        content = draft.content
        scripture = draft.scriptureInput
        scriptureChips = draft.scriptureReferences
        actionStep = draft.actionStep
        prayerFromSermon = draft.prayer
        shouldRevisit = draft.shouldRevisit
        worshipSongs = draft.worshipSongs
        blocks = draft.blocks
        noteTags = draft.noteTags
        attributedText = NSAttributedString(
            string: draft.content,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ]
        )
        let detectionService = ScriptureDetectionService.shared
        detectedScriptures = detectionService.detectedReferences(in: draft.content).map(\.reference)
        suggestedScriptures = detectionService.suggestedReferences(for: draft.content).map {
            ScriptureThemeSuggestion(
                theme: "suggested",
                reference: $0.reference,
                shortText: "Detected from your note content"
            )
        }
        restoredLocalDraftDate = draft.updatedAt
        hasUnsavedChanges = true
        autosaveState = .idle
    }

    private func clearLocalDraft() {
        localDraftService.clear(key: localDraftKey)
        restoredLocalDraftDate = nil
    }

    // MARK: - Actions

    private func toggleFormatting(_ style: NoteTextStyle) {
        if activeFormatting.contains(style) {
            activeFormatting.remove(style)
        } else {
            activeFormatting.insert(style)
        }
    }

    private func insertSemanticBlock(_ block: NoteSemanticBlock) {
        content += block.prefix
        focusedField = .content
        markChanged()
    }

    private func convertSelectionToBlock(_ blockType: ChurchNoteBlockType) {
        guard let range = selectionRange, range.length > 0 else { return }
        let nsString = (attributedText.string as NSString)
        guard range.location + range.length <= nsString.length else { return }
        let selectedText = nsString.substring(with: range)
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let newBlock = commandApplier.convertedBlock(from: selectedText, type: blockType)

        // Remove selected text from the editor
        if let coordinator = editorCoordinator, let tv = coordinator.textView {
            _ = coordinator.extractSelectedText(from: tv)
        }

        withAnimation(CNToken.Anim.smoothExpand) {
            blocks.append(newBlock)
        }
        withAnimation(CNToken.Anim.quickTap) {
            showSelectionToolbar = false
        }
        markChanged()
    }

    private func markChanged() {
        hasUnsavedChanges = true
        restoredLocalDraftDate = nil
        autosaveState = .saving
        saveLocalDraftSnapshot()
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        guard isEditMode else { return }
        autosaveService.schedule(after: 900_000_000) {
            try await saveNoteInternal()
            self.clearLocalDraft()
            self.hasUnsavedChanges = false
            self.autosaveState = .saved
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                if self.autosaveState == .saved {
                    self.autosaveState = .idle
                }
            }
        }
    }

    @MainActor
    private func performAutosave() async {
        guard canSave, !isSaving else { return }
        autosaveState = .saving
        do {
            try await saveNoteInternal()
            clearLocalDraft()
            hasUnsavedChanges = false
            autosaveState = .saved
            try? await Task.sleep(for: .seconds(2))
            if autosaveState == .saved {
                autosaveState = .idle
            }
        } catch {
            autosaveState = .idle
        }
    }

    private func saveNote() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await saveNoteInternal()
                clearLocalDraft()
                hasUnsavedChanges = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    /// Encode the current attributed text into a JSON string for persistence.
    private func encodeRichContent() -> String? {
        let engine = AttributedStringFormatter()
        let doc = engine.encode(attributedString: attributedText)
        guard let data = try? JSONEncoder().encode(doc) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveNoteInternal() async throws {
        guard Auth.auth().currentUser?.uid != nil else {
            throw NSError(domain: "ChurchNotesEditor", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        let note = try persistenceService.buildNote(
            from: existingNote,
            title: title,
            sermonTitle: sermonTitle,
            metadata: ChurchNoteMetadata(
                churchName: churchName,
                pastorName: pastor,
                serviceDate: selectedDate
            ),
            content: content,
            attributedText: attributedText,
            blocks: blocks,
            tags: noteTags,
            scriptureReferences: scriptureChips,
            worshipSongs: worshipSongs,
            actionStep: actionStep,
            prayer: prayerFromSermon,
            revisitMidweek: shouldRevisit
        )
        try await persistenceService.save(note: note)
    }

    // MARK: - Content Change Handling

    private func handleContentChange(_ newValue: String) {
        contentChangeTask?.cancel()
        contentChangeTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                let detectionService = ScriptureDetectionService.shared
                detectedScriptures = detectionService.detectedReferences(in: newValue).map(\.reference)
                suggestedScriptures = detectionService.suggestedReferences(for: newValue).map {
                    ScriptureThemeSuggestion(
                        theme: "suggested",
                        reference: $0.reference,
                        shortText: "Detected from your note content"
                    )
                }
            }
        }

        markChanged()
    }

    // MARK: - Keyboard

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil, queue: .main
        ) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = frame.height
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil, queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
                showFormattingBar = false
            }
        }
    }
}

// MARK: - Supporting Views

private struct NoteGlassTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.systemScaled(14))
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .font(.systemScaled(15))
                .foregroundStyle(.primary)
                .tint(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 14)
    }
}

private struct CapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Scroll Offset Key

private struct NoteScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Church Search Selector

private struct ChurchNotesChurchSearchSheet: View {
    let initialQuery: String
    let onSelect: (ChurchOSProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = AmenChurchService()
    @State private var query: String
    @State private var results: [ChurchOSProfile] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    init(initialQuery: String, onSelect: @escaping (ChurchOSProfile) -> Void) {
        self.initialQuery = initialQuery
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()

                content
            }
            .navigationTitle("Choose Church")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await search(query: query) }
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await search(query: newValue)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search by church, city, or denomination", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
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
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView("Church search unavailable", systemImage: "building.2.crop.circle", description: Text(errorMessage))
        } else if results.isEmpty {
            ContentUnavailableView("Search churches", systemImage: "building.2", description: Text("Use the existing Find a Church directory to attach a church to this note."))
        } else {
            List(results) { church in
                Button {
                    onSelect(church)
                } label: {
                    ChurchNotesChurchResultRow(church: church)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    @MainActor
    private func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            errorMessage = nil
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let candidates = try await service.searchChurches(
                query: trimmed,
                near: nil,
                denomination: nil,
                style: nil
            )
            results = try await ChurchNotesChurchSearchRankingService.shared.rank(
                churches: candidates,
                query: trimmed,
                intent: "church notes sermon metadata"
            )
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }
}

private final class ChurchNotesChurchSearchRankingService {
    static let shared = ChurchNotesChurchSearchRankingService()

    private let functions = Functions.functions()

    func rank(churches: [ChurchOSProfile], query: String, intent: String) async throws -> [ChurchOSProfile] {
        guard churches.count > 1 else { return churches }

        let payload: [String: Any] = [
            "intent": intent,
            "query": query,
            "timeContext": [
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "timezone": TimeZone.current.identifier
            ],
            "candidateChurches": churches.map(Self.payload)
        ]

        let result = try await functions.httpsCallable("rankChurchesForUser").call(payload)
        guard let root = result.data as? [String: Any],
              let ranked = root["results"] as? [[String: Any]] else {
            return churches
        }

        let byId = Dictionary(uniqueKeysWithValues: churches.map { ($0.id, $0) })
        let rankedIds = ranked.compactMap { $0["churchId"] as? String }
        let ordered = rankedIds.compactMap { byId[$0] }
        let orderedIds = Set(ordered.map(\.id))
        return ordered + churches.filter { !orderedIds.contains($0.id) }
    }

    private static func payload(for church: ChurchOSProfile) -> [String: Any] {
        let primaryCampus = church.campuses.first(where: { $0.isPrimary }) ?? church.campuses.first
        let address = [
            primaryCampus?.address,
            primaryCampus?.city,
            primaryCampus?.state
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")

        return [
            "churchId": church.id,
            "name": church.name,
            "denomination": church.denomination as Any,
            "address": address,
            "serviceTime": church.serviceTimesToday.first.map { "\($0.dayName) \($0.startTime)" } ?? "",
            "tags": [
                church.denomination,
                church.missionStatement,
                church.bio
            ].compactMap { $0 }
        ]
    }
}

private struct ChurchNotesChurchResultRow: View {
    let church: ChurchOSProfile

    private var primaryCampus: ChurchCampus? {
        church.campuses.first(where: { $0.isPrimary }) ?? church.campuses.first
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: church.isVerified ? "checkmark.seal.fill" : "building.2")
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(church.isVerified ? Color.green : ChurchNotesDesignTokens.Colors.personalTint)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.05), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(church.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        let campus = primaryCampus
        let place = [campus?.city, campus?.state]
            .compactMap { value in
                let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: ", ")
        return [church.denomination, place]
            .compactMap { value in
                let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")
    }
}

// MARK: - Preview

#Preview("New Note") {
    ChurchNotesPremiumEditor(notesService: ChurchNotesService())
}

#Preview("Edit Note") {
    ChurchNotesPremiumEditor(
        notesService: ChurchNotesService(),
        existingNote: .preview
    )
}
