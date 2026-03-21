//
//  ChurchNotesEditor.swift
//  AMENAPP
//
//  Enhanced church notes editor with smart features
//  P1-1: Text input debouncing
//  P1-4: Unsaved changes warning
//  UX-1: Quick insert toolbar
//  UX-2: Auto-save
//  UX-3: Scripture detection
//

import SwiftUI
import FirebaseAuth
#if canImport(MusicKit)
import MusicKit
#endif

// MARK: - Enhanced Note Editor with Smart Features

struct EnhancedChurchNoteEditor: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var notesService: ChurchNotesService
    
    // Edit mode (nil for new note, note for editing)
    let existingNote: ChurchNote?
    
    // Note fields
    @State private var title = ""
    @State private var sermonTitle = ""
    @State private var churchName = ""
    @State private var pastor = ""
    @State private var selectedDate = Date()
    @State private var content = ""
    @State private var scripture = ""
    @State private var tags: [String] = []
    
    // UI state
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingToolbar = false
    @FocusState private var isContentFocused: Bool
    
    // P1-1: Debouncing
    @State private var contentDebounceTask: Task<Void, Never>?
    @State private var characterCount = 0
    
    // P1-4: Unsaved changes tracking
    @State private var hasUnsavedChanges = false
    @State private var showUnsavedAlert = false
    @State private var initialContent = ""
    
    // UX-2: Auto-save
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var lastAutoSave: Date?
    @State private var showAutoSaveIndicator = false
    
    // UX-3: Scripture detection
    @State private var detectedScriptures: [String] = []

    // Music: worship songs attached to this note
    @State private var worshipSongs: [WorshipSongReference] = []
    @State private var showSongSearch = false

    // Feature 1: Claude auto-tagging
    @State private var detectedTags: [String] = []
    @State private var visibleTagCount: Int = 0
    @State private var isAnalyzing = false
    @State private var tagDebounceTask: Task<Void, Never>?

    // Feature 2: Metadata collapse
    @State private var metaExpanded: Bool = true

    // Feature 2: Verse lookup
    @State private var verseText: String? = nil
    @State private var isLookingUpVerse = false
    @State private var showVersePreview = false

    // Animation 1: Ghost Title Autocomplete
    @State private var ghostSuggestion = ""
    @State private var titleColor: Color = .primary
    @State private var showAcceptHint = false
    @State private var titleDebounceTask: Task<Void, Never>?
    private let titleSuggestions = [
        "Walking in Faith", "The Promise of God", "Renewed by Grace",
        "Trust in the Lord", "God is Our Refuge", "Faith That Moves Mountains",
        "Led by the Spirit", "A Heart After God", "Grace Upon Grace",
        "The Power of Prayer"
    ]

    // Animation 2: Context Completion Ring
    private var contextFilledCount: Int {
        [!sermonTitle.isEmpty, !churchName.isEmpty, !pastor.isEmpty, true].filter { $0 }.count
    }
    private var contextAllFilled: Bool { contextFilledCount == 4 }
    private var contextCompletionFraction: Double { Double(contextFilledCount) / 4.0 }

    // Animation 3: Focus Mode + Word Momentum
    @State private var focusMode = false
    @State private var wordCount = 0
    @State private var lastMilestone = 0
    @State private var milestoneRingScale: CGFloat = 0.3
    @State private var milestoneRingOpacity: Double = 0
    @State private var milestoneLabelOpacity: Double = 0
    @State private var milestoneLabelOffset: CGFloat = 0
    @State private var milestoneLabel = ""
    private let milestones = [10, 25, 50, 100]

    var canSave: Bool {
        !title.isEmpty && !content.isEmpty
    }
    
    var isEditMode: Bool {
        existingNote != nil
    }
    
    init(notesService: ChurchNotesService, existingNote: ChurchNote? = nil) {
        self.notesService = notesService
        self.existingNote = existingNote
        
        // Initialize with existing note data if editing
        if let note = existingNote {
            _title = State(initialValue: note.title)
            _sermonTitle = State(initialValue: note.sermonTitle ?? "")
            _churchName = State(initialValue: note.churchName ?? "")
            _pastor = State(initialValue: note.pastor ?? "")
            _selectedDate = State(initialValue: note.date)
            _content = State(initialValue: note.content)
            _scripture = State(initialValue: note.scripture ?? "")
            _tags = State(initialValue: note.tags)
            _initialContent = State(initialValue: note.content)
            _worshipSongs = State(initialValue: note.worshipSongs)
            _detectedTags = State(initialValue: note.claudeTags)
            _visibleTagCount = State(initialValue: note.claudeTags.count)
            // Editing an existing note: start collapsed since metadata is already filled
            _metaExpanded = State(initialValue: false)
        }
    }

    // MARK: - Computed helpers

    private var metaSummary: String {
        let date = selectedDate.formatted(.dateTime.month(.abbreviated).day())
        let parts: [String] = [date,
                               churchName.isEmpty ? nil : churchName,
                               pastor.isEmpty ? nil : "Pastor \(pastor)"].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private var anyMetaEmpty: Bool {
        sermonTitle.isEmpty || churchName.isEmpty || pastor.isEmpty
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.96, blue: 0.96)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with auto-save indicator
                headerView
                
                Divider()
                    .background(Color.black.opacity(0.1))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Focus-mode dimmable: title, context, scripture
                        VStack(alignment: .leading, spacing: 24) {
                            titleField
                            sermonContextSection
                            scriptureSection
                        }
                        .opacity(focusMode ? 0.2 : 1.0)
                        .allowsHitTesting(!focusMode)
                        .animation(.easeInOut(duration: 0.35), value: focusMode)

                        // Main content editor
                        contentEditorSection
                        
                        // UX-1: Quick insert toolbar
                        if showingToolbar {
                            quickInsertToolbar
                        }

                        // Worship songs attached to this note
                        if !worshipSongs.isEmpty {
                            worshipSongsSection
                        }

                        // Tags section
                        tagsSection
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges) // P1-4
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Discard", role: .destructive) {
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
        .onAppear {
            initialContent = content
        }
        .onChange(of: content) { oldValue, newValue in
            handleContentChange(newValue)
        }
        .onChange(of: isContentFocused) { _, focused in
            guard focused else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                // Auto-expand if any metadata is missing; collapse if all filled
                metaExpanded = anyMetaEmpty
            }
        }
        .sheet(isPresented: $showSongSearch) {
            SongSearchSheet { song in
                if !worshipSongs.contains(where: { $0.title == song.title && $0.artist == song.artist }) {
                    worshipSongs.append(song)
                    trackUnsavedChanges()
                }
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Button("Cancel") {
                handleCancel()
            }
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(.black.opacity(0.6))
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(isEditMode ? "Edit Note" : "New Note")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.black)
                
                // UX-2: Auto-save indicator
                if showAutoSaveIndicator {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("Auto-saved")
                            .font(.system(size: 11))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                    .transition(.opacity)
                }
            }
            
            Spacer()
            
            Button {
                saveNote()
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(contextAllFilled ? Color.purple : .black)
                } else {
                    Text("Save")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(contextAllFilled ? Color.purple : (canSave ? .black : .black.opacity(0.3)))
                }
            }
            .disabled(!canSave || isSaving)
            .opacity(contextAllFilled ? 1.0 : (canSave ? 0.7 : 0.35))
            .animation(.easeInOut(duration: 0.3), value: contextAllFilled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(red: 0.96, green: 0.96, blue: 0.96))
    }
    
    // MARK: - Title Field (with Ghost Autocomplete)

    private var titleField: some View {
        ZStack(alignment: .topLeading) {
            // Ghost text overlay — drawn behind, non-interactive
            if !ghostSuggestion.isEmpty {
                (Text(title).foregroundColor(.clear) +
                 Text(ghostSuggestion).foregroundColor(Color(.tertiaryLabel)))
                    .font(.system(size: 32, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("Note Title", text: $title)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(titleColor)
                    .tint(.black)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .onChange(of: title) { _, newVal in
                        trackUnsavedChanges()
                        updateGhostSuggestion(for: newVal)
                    }

                // "tab to accept →" badge
                if showAcceptHint {
                    Button { acceptSuggestion() } label: {
                        Text("tab to accept →")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: showAcceptHint)
    }
    
    // MARK: - Sermon Context Section (collapsible)

    private var sermonContextSection: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Collapsed pill summary ──────────────────────────────────
            if !metaExpanded {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                        metaExpanded = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.black.opacity(0.35))
                        if metaSummary.isEmpty {
                            Text("Add sermon details…")
                                .font(.system(size: 14))
                                .foregroundStyle(.black.opacity(0.35))
                        } else {
                            Text(metaSummary)
                                .font(.system(size: 14))
                                .foregroundStyle(.black.opacity(0.65))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            // ── Expanded fields ─────────────────────────────────────────
            if metaExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Sermon Context")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.black.opacity(0.5))
                            .textCase(.uppercase)
                            .tracking(1)

                        // Animation 2: Completion ring
                        contextCompletionRing
                            .padding(.leading, 6)

                        Spacer()
                        // Only show collapse button when there is summary data
                        if !metaSummary.isEmpty {
                            Button {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                                    metaExpanded = false
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("Collapse")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(.black.opacity(0.4))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    VStack(spacing: 12) {
                        EditorMinimalTextField(icon: "mic", placeholder: "Sermon title", text: $sermonTitle)
                            .overlay(alignment: .trailing) { contextDot(filled: !sermonTitle.isEmpty).padding(.trailing, 6) }
                            .onChange(of: sermonTitle) { _, _ in trackUnsavedChanges() }

                        EditorMinimalTextField(icon: "building.2", placeholder: "Church name", text: $churchName)
                            .overlay(alignment: .trailing) { contextDot(filled: !churchName.isEmpty).padding(.trailing, 6) }
                            .onChange(of: churchName) { _, _ in trackUnsavedChanges() }

                        EditorMinimalTextField(icon: "person", placeholder: "Pastor", text: $pastor)
                            .overlay(alignment: .trailing) { contextDot(filled: !pastor.isEmpty).padding(.trailing, 6) }
                            .onChange(of: pastor) { _, _ in trackUnsavedChanges() }

                        HStack {
                            Image(systemName: "calendar")
                                .font(.system(size: 16))
                                .foregroundStyle(.black.opacity(0.4))
                                .frame(width: 24)
                            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.black)
                            Spacer()
                            // Date always counts as filled (always has a value)
                            contextDot(filled: true)
                                .padding(.trailing, 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
                        .padding(.horizontal, 20)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Scripture Section with Detection + Inline Lookup

    private var scriptureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scripture Reference")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1)
                .padding(.horizontal, 20)

            // Scripture field with inline "Look up" button
            HStack {
                Image(systemName: "book")
                    .font(.system(size: 16))
                    .foregroundStyle(.black.opacity(0.4))
                    .frame(width: 24)

                TextField("e.g., John 3:16", text: $scripture)
                    .font(.system(size: 16))
                    .foregroundStyle(.black)
                    .tint(.black)
                    .onChange(of: scripture) { _, _ in
                        trackUnsavedChanges()
                        // Clear old verse preview when the reference changes
                        if showVersePreview {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showVersePreview = false
                                verseText = nil
                            }
                        }
                    }

                Spacer()

                Button { triggerVerseLookup() } label: {
                    if isLookingUpVerse {
                        ProgressView().scaleEffect(0.7).tint(.black)
                            .frame(width: 52, height: 20)
                    } else {
                        Text("Look up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(
                                scripture.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.black.opacity(0.3)
                                    : Color(red: 0.498, green: 0.467, blue: 0.867)
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(scripture.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? Color.clear
                                          : Color(red: 0.498, green: 0.467, blue: 0.867).opacity(0.10))
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(scripture.trimmingCharacters(in: .whitespaces).isEmpty || isLookingUpVerse)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
            .padding(.horizontal, 20)

            // Verse preview — slides in below the field
            if showVersePreview, let verse = verseText {
                Text(verse)
                    .font(.system(size: 12, design: .serif).italic())
                    .foregroundStyle(.black.opacity(0.75))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.498, green: 0.467, blue: 0.867).opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color(red: 0.498, green: 0.467, blue: 0.867).opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // UX-3: Show detected scriptures from content
            if !detectedScriptures.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detected in notes:")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.5))
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(detectedScriptures, id: \.self) { ref in
                                Button {
                                    scripture = ref
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "book.fill").font(.system(size: 10))
                                        Text(ref).font(.system(size: 13))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
    }
    
    // MARK: - Content Editor Section (with Focus Mode + Word Momentum)

    private var contentEditorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Notes")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1)

                Spacer()

                // Animation 3: Word counter
                Text("\(wordCount) words")
                    .font(.caption)
                    .foregroundStyle(wordCount > 0 ? Color.purple : Color.secondary)
                    .animation(.easeInOut(duration: 0.2), value: wordCount > 0)

                // Character count (debounced)
                Text("\(characterCount) characters")
                    .font(.system(size: 12))
                    .foregroundStyle(.black.opacity(0.4))

                // Formatting toolbar toggle
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showingToolbar.toggle()
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "textformat")
                            .font(.system(size: 12, weight: .medium))
                        Text(showingToolbar ? "Hide" : "Format")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.05))
                    .foregroundStyle(.black.opacity(0.7))
                    .cornerRadius(6)
                }

                // Animation 3: Focus toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        focusMode.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(focusMode ? "Exit Focus" : "Focus")
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.purple.opacity(focusMode ? 0.12 : 0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            // Text editor with focus glow + milestone ring overlay
            ZStack {
                TextEditor(text: $content)
                    .font(.system(size: 16))
                    .foregroundStyle(.black)
                    .frame(minHeight: 300)
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                focusMode
                                    ? Color.purple.opacity(0.45)
                                    : (isContentFocused ? Color.black.opacity(0.2) : Color.black.opacity(0.1)),
                                lineWidth: focusMode ? 1.5 : 1
                            )
                            .animation(.easeInOut(duration: 0.3), value: focusMode)
                    )
                    .focused($isContentFocused)

                // Animation 3: Milestone ring + floating label
                if milestoneRingOpacity > 0 {
                    Circle()
                        .stroke(Color.purple, lineWidth: 1.5)
                        .frame(width: 40 * milestoneRingScale * 3, height: 40 * milestoneRingScale * 3)
                        .opacity(milestoneRingOpacity)
                        .allowsHitTesting(false)

                    Text(milestoneLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .offset(y: milestoneLabelOffset - 80)
                        .opacity(milestoneLabelOpacity)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - UX-1: Quick Insert Toolbar
    
    private var quickInsertToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Insert")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    QuickInsertButton(icon: "book.fill", label: "Scripture") {
                        insertTemplate("\n\n📖 Scripture: ")
                    }
                    
                    QuickInsertButton(icon: "lightbulb.fill", label: "Key Point") {
                        insertTemplate("\n\n💡 Key Point: ")
                    }
                    
                    QuickInsertButton(icon: "hand.raised.fill", label: "Application") {
                        insertTemplate("\n\n🙏 Application: ")
                    }
                    
                    QuickInsertButton(icon: "heart.fill", label: "Prayer") {
                        insertTemplate("\n\n❤️ Prayer: ")
                    }
                    
                    QuickInsertButton(icon: "star.fill", label: "Reflection") {
                        insertTemplate("\n\n✨ Reflection: ")
                    }
                    
                    QuickInsertButton(icon: "checkmark.circle.fill", label: "Action Step") {
                        insertTemplate("\n\n✅ Action Step: ")
                    }

                    QuickInsertButton(icon: "music.note", label: "Add Song") {
                        showSongSearch = true
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    // MARK: - Worship Songs Section

    private var worshipSongsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Worship Songs")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1)

                Spacer()

                Button {
                    showSongSearch = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.05))
                    .foregroundStyle(.black.opacity(0.7))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(worshipSongs) { song in
                    HStack(spacing: 0) {
                        WorshipSongCard(
                            title: song.title,
                            artist: song.artist,
                            churchNoteId: nil
                        )

                        // Remove button
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                worshipSongs.removeAll { $0.id == song.id }
                                trackUnsavedChanges()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(.systemGray3))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - AI Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("AI Tags")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1)
                if isAnalyzing {
                    AnalyzingPulsingDot()
                }
            }
            .padding(.horizontal, 20)

            if !detectedTags.isEmpty {
                NoteTagFlowLayout(tags: detectedTags, visibleCount: visibleTagCount)
            } else if !isAnalyzing && content.count > 50 {
                Text("Tags appear after you write a few sentences")
                    .font(.system(size: 12))
                    .foregroundStyle(.black.opacity(0.35))
                    .padding(.horizontal, 20)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleContentChange(_ newValue: String) {
        // P1-1: Debounce character count update
        contentDebounceTask?.cancel()
        contentDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                characterCount = newValue.count
            }
        }

        // Animation 3: Word count + milestone detection
        let newWordCount = newValue.split(whereSeparator: \.isWhitespace).count
        wordCount = newWordCount
        if let milestone = milestones.first(where: { newWordCount >= $0 && $0 > lastMilestone }) {
            lastMilestone = milestone
            fireMilestoneEffect(words: milestone)
        }
        
        // UX-3: Detect scripture references
        detectedScriptures = detectScriptureReferences(in: newValue)
        
        // Track unsaved changes
        trackUnsavedChanges()
        
        // UX-2: Trigger auto-save after 3 seconds of inactivity
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(for: .seconds(3))
            await autoSave()
        }

        // Feature 1: Claude auto-tagging — 800ms debounce, min 50 chars
        tagDebounceTask?.cancel()
        guard newValue.count > 50 else { return }
        tagDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await triggerTagAnalysis(content: newValue)
        }
    }
    
    private func trackUnsavedChanges() {
        hasUnsavedChanges = (
            content != initialContent ||
            !title.isEmpty ||
            !sermonTitle.isEmpty ||
            !churchName.isEmpty
        )
    }
    
    private func handleCancel() {
        if hasUnsavedChanges {
            showUnsavedAlert = true
        } else {
            dismiss()
        }
    }
    
    private func insertTemplate(_ template: String) {
        content += template
        isContentFocused = true
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
    }
    
    // UX-2: Auto-save functionality
    private func autoSave() async {
        guard canSave, !isSaving else { return }
        
        // Only auto-save for existing notes (not new ones)
        guard isEditMode else { return }
        
        do {
            try await saveNoteInternal()
            
            await MainActor.run {
                lastAutoSave = Date()
                showAutoSaveIndicator = true
                hasUnsavedChanges = false
                initialContent = content
            }
            
            // Hide indicator after 2 seconds
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                showAutoSaveIndicator = false
            }
        } catch {
            dlog("Auto-save failed: \(error)")
        }
    }
    
    private func saveNote() {
        Task {
            isSaving = true
            defer { isSaving = false }
            
            do {
                try await saveNoteInternal()
                
                await MainActor.run {
                    hasUnsavedChanges = false
                    dismiss()
                }
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
    
    private func saveNoteInternal() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ChurchNotesEditor", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        if let existingNote = existingNote {
            // Update existing note
            var updatedNote = existingNote
            updatedNote.title = title
            updatedNote.sermonTitle = sermonTitle.isEmpty ? nil : sermonTitle
            updatedNote.churchName = churchName.isEmpty ? nil : churchName
            updatedNote.pastor = pastor.isEmpty ? nil : pastor
            updatedNote.date = selectedDate
            updatedNote.content = content
            updatedNote.scripture = scripture.isEmpty ? nil : scripture
            updatedNote.scriptureReferences = detectedScriptures
            updatedNote.tags = tags
            updatedNote.worshipSongs = worshipSongs
            updatedNote.claudeTags = detectedTags

            try await notesService.updateNote(updatedNote)
        } else {
            // Create new note
            let newNote = ChurchNote(
                userId: userId,
                title: title,
                sermonTitle: sermonTitle.isEmpty ? nil : sermonTitle,
                churchName: churchName.isEmpty ? nil : churchName,
                pastor: pastor.isEmpty ? nil : pastor,
                date: selectedDate,
                content: content,
                scripture: scripture.isEmpty ? nil : scripture,
                tags: tags,
                scriptureReferences: detectedScriptures,
                worshipSongs: worshipSongs,
                claudeTags: detectedTags
            )

            try await notesService.createNote(newNote)
        }
    }
    
    // MARK: - Feature 1: Tag analysis

    @MainActor
    private func triggerTagAnalysis(content: String) async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let tags = try await NoteTagService.analyzeTags(content: content)
            guard !tags.isEmpty else { return }
            detectedTags = tags
            visibleTagCount = 0
            for i in 0..<tags.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        self.visibleTagCount = i + 1
                    }
                }
            }
        } catch {
            dlog("NoteTagService tag analysis error: \(error)")
        }
    }

    // MARK: - Feature 2: Verse lookup

    private func triggerVerseLookup() {
        let ref = scripture.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty else { return }
        isLookingUpVerse = true
        Task {
            do {
                let text = try await NoteTagService.lookupVerse(reference: ref)
                await MainActor.run {
                    verseText = text.isEmpty ? nil : text
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showVersePreview = verseText != nil
                    }
                    isLookingUpVerse = false
                }
            } catch {
                await MainActor.run { isLookingUpVerse = false }
                dlog("NoteTagService verse lookup error: \(error)")
            }
        }
    }

    // UX-3: Scripture detection
    private func detectScriptureReferences(in text: String) -> [String] {
        let pattern = #"(\d?\s?[A-Z][a-z]+\s\d+:\d+(-\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    // MARK: - Animation 1 Helpers: Ghost Title Autocomplete

    private func updateGhostSuggestion(for input: String) {
        titleDebounceTask?.cancel()
        guard !input.isEmpty else {
            ghostSuggestion = ""
            withAnimation { showAcceptHint = false }
            return
        }
        titleDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let match = titleSuggestions.first(where: {
                    $0.lowercased().hasPrefix(input.lowercased()) && input.count < $0.count
                }) {
                    ghostSuggestion = String(match.dropFirst(input.count))
                    withAnimation(.easeOut(duration: 0.2)) { showAcceptHint = true }
                } else {
                    ghostSuggestion = ""
                    withAnimation(.easeOut(duration: 0.15)) { showAcceptHint = false }
                }
            }
        }
    }

    private func acceptSuggestion() {
        guard !ghostSuggestion.isEmpty else { return }
        title = title + ghostSuggestion
        ghostSuggestion = ""
        showAcceptHint = false
        titleColor = .purple
        withAnimation(.easeOut(duration: 0.45)) { titleColor = .primary }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Animation 2 Helpers: Context Completion Ring

    private var contextCompletionRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.quaternaryLabel), lineWidth: 3)
            Circle()
                .trim(from: 0, to: contextCompletionFraction)
                .stroke(
                    contextAllFilled ? Color.green : Color.purple,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: contextCompletionFraction)
                .animation(.easeInOut(duration: 0.4), value: contextAllFilled)

            if contextAllFilled {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
                    .scaleEffect(contextAllFilled ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: contextAllFilled)
            } else {
                Text("\(contextFilledCount)/4")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.purple)
                    .opacity(contextAllFilled ? 0 : 1)
            }
        }
        .frame(width: 28, height: 28)
    }

    private func contextDot(filled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(filled ? Color.purple : Color(.systemBackground))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle().stroke(filled ? Color.clear : Color(.separator), lineWidth: 1)
                )
            if filled {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: filled)
    }

    // MARK: - Animation 3 Helpers: Focus Mode + Word Momentum

    private func fireMilestoneEffect(words: Int) {
        milestoneLabel = "\(words) words ✦"
        milestoneRingScale = 0.3
        milestoneRingOpacity = 0
        milestoneLabelOffset = 0
        milestoneLabelOpacity = 0

        // Ring expands and fades
        withAnimation(.easeOut(duration: 0.7)) {
            milestoneRingScale = 1.8
            milestoneRingOpacity = 0
        }
        withAnimation(.easeIn(duration: 0.1)) {
            milestoneRingOpacity = 0.8
        }

        // Label floats up and fades
        withAnimation(.easeOut(duration: 0.4)) {
            milestoneLabelOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 1.2).delay(0.15)) {
            milestoneLabelOffset = -24
        }
        withAnimation(.easeIn(duration: 0.5).delay(0.7)) {
            milestoneLabelOpacity = 0
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Clean up after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            milestoneRingOpacity = 0
        }
    }
}

// MARK: - Quick Insert Button

struct QuickInsertButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white)
            .foregroundStyle(.black.opacity(0.8))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

// MARK: - Song Search Sheet

/// Presents a lightweight search bar that queries Apple Music via WorshipMusicService
/// (MusicKit when available, Apple Music search URL otherwise).
/// Calls `onAdd` with a `WorshipSongReference` when the user picks a result.
struct SongSearchSheet: View {
    let onAdd: (WorshipSongReference) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SongResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    struct SongResult: Identifiable {
        let id: String
        let title: String
        let artist: String
        let albumArtURL: String?
        let appleMusicURL: String?
        let musicKitID: String?
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Song title or artist…", text: $query)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { runSearch() }
                        .onChange(of: query) { _, _ in scheduleDebouncedSearch() }
                    if isSearching {
                        ProgressView().scaleEffect(0.75)
                    } else if !query.isEmpty {
                        Button { query = ""; results = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Divider().padding(.top, 12)

                if results.isEmpty && !isSearching && !query.isEmpty {
                    ContentUnavailableView("No results", systemImage: "music.note",
                        description: Text("Try a different song or artist name."))
                        .padding(.top, 40)
                } else {
                    List(results) { song in
                        Button {
                            let ref = WorshipSongReference(
                                title: song.title,
                                artist: song.artist,
                                musicKitID: song.musicKitID,
                                appleMusicURL: song.appleMusicURL,
                                albumArtURL: song.albumArtURL
                            )
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onAdd(ref)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                // Album art or placeholder
                                Group {
                                    if let urlStr = song.albumArtURL, let url = URL(string: urlStr) {
                                        AsyncImage(url: url) { phase in
                                            if case .success(let img) = phase {
                                                img.resizable().aspectRatio(contentMode: .fill)
                                            } else {
                                                Color(.systemGray5)
                                            }
                                        }
                                    } else {
                                        Color(.systemGray5)
                                            .overlay(Image(systemName: "music.note")
                                                .foregroundStyle(.secondary))
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(song.artist)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "plus.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.purple)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .navigationTitle("Add Worship Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { focused = true }
        .onDisappear { searchTask?.cancel() }
    }

    private func scheduleDebouncedSearch() {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            runSearch()
        }
    }

    private func runSearch() {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            await MainActor.run { isSearching = true }
            let found = await searchSongs(query: term)
            await MainActor.run {
                results = found
                isSearching = false
            }
        }
    }

    func searchSongs(query: String) async -> [SongResult] {
        // MusicKit catalog search when the framework and authorization are available.
        // Falls back to an Apple Music deep-link result in all other cases.
        #if canImport(MusicKit)
        do {
            let status = await MusicAuthorization.request()
            if status == .authorized {
                var req = MusicCatalogSearchRequest(term: query, types: [Song.self])
                req.limit = 15
                let resp = try await req.response()
                if !resp.songs.isEmpty {
                    return resp.songs.map { song in
                        SongResult(
                            id: song.id.rawValue,
                            title: song.title,
                            artist: song.artistName,
                            albumArtURL: song.artwork?.url(width: 120, height: 120)?.absoluteString,
                            appleMusicURL: song.url?.absoluteString,
                            musicKitID: song.id.rawValue
                        )
                    }
                }
            }
        } catch {}
        #endif
        let searchURL = WorshipMusicService.appleMusicSearchURL(title: query, artist: "")?.absoluteString
        return [SongResult(
            id: UUID().uuidString, title: query,
            artist: "Search in Apple Music →",
            albumArtURL: nil, appleMusicURL: searchURL, musicKitID: nil
        )]
    }
}

// MARK: - Minimal Text Field (local to editor)

private struct EditorMinimalTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.black.opacity(0.4))
                .frame(width: 24)
            
            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .foregroundStyle(.black)
                .tint(.black)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
}


// MARK: - Analyzing Pulsing Dot

private struct AnalyzingPulsingDot: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(Color(red: 0.498, green: 0.467, blue: 0.867).opacity(0.7))
            .frame(width: 7, height: 7)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    scale = 1.6
                }
            }
    }
}

// MARK: - Tag Flow Layout

/// Wrapping horizontal flow for AI-detected tag pills.
struct NoteTagFlowLayout: View {
    let tags: [String]
    let visibleCount: Int

    private let tagColors: [Color] = [
        Color(red: 0.498, green: 0.467, blue: 0.867), // purple
        Color(red: 0.20,  green: 0.60,  blue: 0.60),  // teal
        Color(red: 0.85,  green: 0.60,  blue: 0.15),  // amber
    ]

    var body: some View {
        TagWrapLayout(spacing: 8) {
            ForEach(Array(tags.prefix(visibleCount).enumerated()), id: \.element) { idx, tag in
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(tagColors[idx % tagColors.count].opacity(0.25))
                            .overlay(Capsule().strokeBorder(tagColors[idx % tagColors.count].opacity(0.45), lineWidth: 0.75))
                    )
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Tag Wrap Layout (iOS 16+ Layout protocol)

struct TagWrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flow(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flow(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let pos = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
    }

    private func flow(in maxWidth: CGFloat, subviews: Subviews) -> FlowResult {
        var result = FlowResult()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            result.positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        result.size = CGSize(width: maxWidth, height: y + rowHeight)
        return result
    }
}
