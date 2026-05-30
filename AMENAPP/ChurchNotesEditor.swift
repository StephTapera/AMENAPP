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
import Combine
import FirebaseAuth
import AVFoundation
import Speech
import Vision
import UserNotifications
import FirebaseFirestore
#if canImport(MusicKit)
import MusicKit
#endif

// MARK: - Enhanced Note Editor with Smart Features

struct EnhancedChurchNoteEditor: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @StateObject private var scriptureEngine = BereanScriptureEngine.shared
    @State private var scriptureInsights: [ScriptureInsight] = []
    @State private var scriptureEnrichTask: Task<Void, Never>?

    // Music: worship songs attached to this note
    @State private var worshipSongs: [WorshipSongReference] = []
    @State private var showSongSearch = false

    // Feature 01: Live Sermon Transcription
    @State private var showTranscription = false

    // Feature 02: Photo → Structured Notes
    @State private var showPhotoScan = false

    // Feature 03: Bible Verse Linking
    @StateObject private var verseManager = BibleVerseManager()

    // Feature 08: Scripture Reminders
    @StateObject private var reminderManager = ScriptureReminderManager()

    // MARK: — Smart Feature ViewModels (8 features)
    @StateObject private var aiInsightsVM    = AIInsightsViewModel()
    @StateObject private var scriptureDNAVM  = ScriptureDNAViewModel()
    @StateObject private var churchRadarVM   = ChurchRadarViewModel()
    @StateObject private var voiceWisdomVM   = VoiceToWisdomViewModel()
    @StateObject private var communityDuetVM = CommunityDuetViewModel()
    @StateObject private var quoteForgeVM    = QuoteForgeViewModel()
    @StateObject private var growthArcVM     = GrowthArcViewModel()

    // MARK: — Smart Feature Visibility Toggles
    // Inline panels
    @State private var showVoicePanel      = false
    @State private var showAIInsightsPanel = false
    @State private var showScriptureDNA    = false
    @State private var showRadarPanel      = false
    // Sheet presentations
    @State private var showCommunityDuet   = false
    @State private var showQuoteForge      = false
    @State private var showGrowthArc       = false
    @State private var showReelComposer    = false

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

    // TC-01: Draft persistence for new notes
    private let draftKey = "church_notes_editor_draft"
    @State private var wasSaved = false

    // Animation 3: Focus Mode + Word Momentum
    @State private var focusMode = false
    @State private var titleSectionAppeared = false
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
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with auto-save indicator
                headerView

                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Focus-mode dimmable: title, context, scripture
                        VStack(alignment: .leading, spacing: 24) {
                            titleField
                            sermonContextSection
                            scriptureSection
                        }
                        .opacity(focusMode ? 0.2 : 1.0)
                        .offset(y: titleSectionAppeared ? 0 : 12)
                        .opacity(titleSectionAppeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .spring(response: 0.52, dampingFraction: 0.84).delay(0.05), value: titleSectionAppeared)
                        .allowsHitTesting(!focusMode)
                        .animation(reduceMotion ? .none : .easeInOut(duration: 0.35), value: focusMode)

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

                        // Smart feature chip bar (always visible)
                        smartFeatureChipBar
                            .padding(.top, 4)

                        // Inline feature panels (toggled by chips above)
                        if showVoicePanel {
                            VoiceToWisdomView(viewModel: voiceWisdomVM, noteBody: $content)
                                .padding(.horizontal, 16)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if showAIInsightsPanel {
                            AIInsightsPanelView(viewModel: aiInsightsVM, bodyText: $content)
                                .padding(.horizontal, 16)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if showScriptureDNA {
                            ScriptureDNAView(viewModel: scriptureDNAVM, reference: $scripture)
                                .padding(.horizontal, 16)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if showRadarPanel {
                            ChurchRadarView(viewModel: churchRadarVM) { church in
                                churchName   = church.name
                                pastor       = church.pastorName
                                if sermonTitle.isEmpty { sermonTitle = church.sermonTitle }
                            }
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78)), value: showVoicePanel)
                    .animation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78)), value: showAIInsightsPanel)
                    .animation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78)), value: showScriptureDNA)
                    .animation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78)), value: showRadarPanel)
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
            withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.75))) {
                // Auto-expand if any metadata is missing; collapse if all filled
                metaExpanded = anyMetaEmpty
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation { titleSectionAppeared = true }
            }
            // TC-01: Restore draft for new notes
            if !isEditMode {
                if let draft = UserDefaults.standard.dictionary(forKey: draftKey) {
                    title    = draft["title"]    as? String ?? title
                    content  = draft["content"]  as? String ?? content
                    scripture = draft["scripture"] as? String ?? scripture
                }
                UserDefaults.standard.removeObject(forKey: draftKey)
            }
        }
        .onDisappear {
            // TC-01: Persist draft when navigating away from a new, unsaved note
            if !isEditMode && !wasSaved && (!title.isEmpty || !content.isEmpty) {
                let draft: [String: String] = [
                    "title": title,
                    "content": content,
                    "scripture": scripture
                ]
                UserDefaults.standard.set(draft, forKey: draftKey)
            } else if wasSaved {
                UserDefaults.standard.removeObject(forKey: draftKey)
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
        .sheet(isPresented: $showTranscription) {
            SermonTranscriptionView(noteId: existingNote?.id ?? UUID().uuidString)
        }
        .sheet(isPresented: $showPhotoScan) {
            PhotoNotesScanSheet { extracted in
                content += (content.isEmpty ? "" : "\n\n") + extracted
                trackUnsavedChanges()
            }
        }
        .sheet(isPresented: $showCommunityDuet) {
            CommunityDuetSheet(viewModel: communityDuetVM, noteBody: $content)
        }
        .sheet(isPresented: $showQuoteForge) {
            QuoteForgeSheet(viewModel: quoteForgeVM, noteBody: $content)
        }
        .sheet(isPresented: $showGrowthArc) {
            GrowthArcSheet(viewModel: growthArcVM)
        }
        .sheet(isPresented: $showReelComposer) {
            ReelComposerView(viewModel: quoteForgeVM, quote: quoteForgeVM.detectedQuote)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Button("Cancel") {
                handleCancel()
            }
            .font(.systemScaled(17, weight: .regular))
            .foregroundStyle(.black.opacity(0.6))
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(isEditMode ? "Edit Note" : "New Note")
                    .font(.systemScaled(17, weight: .medium))
                    .foregroundStyle(.primary)
                
                // UX-2: Auto-save indicator
                if showAutoSaveIndicator {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.systemScaled(10))
                            .foregroundStyle(.green)
                        Text("Auto-saved")
                            .font(.systemScaled(11))
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
                        .font(.systemScaled(17, weight: .medium))
                        .foregroundStyle(contextAllFilled ? Color.purple : (canSave ? .black : .black.opacity(0.3)))
                }
            }
            .disabled(!canSave || isSaving)
            .opacity(contextAllFilled ? 1.0 : (canSave ? 0.7 : 0.35))
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: contextAllFilled)

            // Doctrine Check + Study Guide (shown when note has content)
            if !content.isEmpty {
                HStack(spacing: 12) {
                    DoctrineCheckButton(text: [title, content].joined(separator: " "))
                    Spacer()
                    if let note = existingNote {
                        StudyGuideButton(note: note)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.thinMaterial)
    }

    // MARK: - Title Field (with Ghost Autocomplete)

    private var titleField: some View {
        ZStack(alignment: .topLeading) {
            // Ghost text overlay — drawn behind, non-interactive
            if !ghostSuggestion.isEmpty {
                HStack(spacing: 0) {
                    Text(title)
                        .foregroundStyle(.clear)
                    Text(ghostSuggestion)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .font(.systemScaled(32, weight: .medium))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("Note Title", text: $title)
                    .font(.systemScaled(32, weight: .medium))
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
                            .font(.systemScaled(10))
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
        .animation(reduceMotion ? .none : .easeOut(duration: 0.2), value: showAcceptHint)
    }
    
    // MARK: - Sermon Context Section (collapsible)

    private var sermonContextSection: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Collapsed pill summary ──────────────────────────────────
            if !metaExpanded {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.75))) {
                        metaExpanded = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(.black.opacity(0.35))
                        if metaSummary.isEmpty {
                            Text("Add sermon details…")
                                .font(.systemScaled(14))
                                .foregroundStyle(.black.opacity(0.35))
                        } else {
                            Text(metaSummary)
                                .font(.systemScaled(14))
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
                            .font(.systemScaled(13, weight: .medium))
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
                                withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.75))) {
                                    metaExpanded = false
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.up")
                                        .font(.systemScaled(11, weight: .medium))
                                    Text("Collapse")
                                        .font(.systemScaled(12, weight: .medium))
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
                                .font(.systemScaled(16))
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
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.thinMaterial)
                                .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.68)))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
                        )
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
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
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(.black.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1)
                .padding(.horizontal, 20)

            // Scripture field with inline "Look up" button
            HStack {
                Image(systemName: "book")
                    .font(.systemScaled(16))
                    .foregroundStyle(.black.opacity(0.4))
                    .frame(width: 24)

                TextField("e.g., John 3:16", text: $scripture)
                    .font(.systemScaled(16))
                    .foregroundStyle(.primary)
                    .tint(.black)
                    .onChange(of: scripture) { _, _ in
                        trackUnsavedChanges()
                        // Clear old verse preview when the reference changes
                        if showVersePreview {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
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
                            .font(.systemScaled(12, weight: .medium))
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
                .opacity(scripture.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.68)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
            )
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            .padding(.horizontal, 20)

            // Verse preview — slides in below the field
            if showVersePreview, let verse = verseText {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verse)
                        .font(.systemScaled(12, design: .serif).italic())
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
                        .highlightable(text: verse, verse: scripture, church: churchName)

                    // Feature 08: Scripture reminder cadence
                    ScriptureReminderView(verse: verse, reference: scripture)
                }
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // UX-3: Show detected scriptures from content
            if !detectedScriptures.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detected in notes:")
                        .font(.systemScaled(12))
                        .foregroundStyle(.black.opacity(0.5))
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(detectedScriptures, id: \.self) { ref in
                                BibleVerseChip(reference: ref, manager: verseManager)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                // Scripture Enrichment Strip (cross-refs + verse text from BereanScriptureEngine)
                ScriptureEnrichmentStrip(insights: scriptureInsights)
            }
        }
    }

    // MARK: - Content Editor Section (with Focus Mode + Word Momentum)

    private var contentEditorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Notes")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1)

                Spacer()

                // Animation 3: Word counter
                Text("\(wordCount) words")
                    .font(.caption)
                    .foregroundStyle(wordCount > 0 ? Color.purple : Color.secondary)
                    .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: wordCount > 0)

                // Character count (debounced)
                Text("\(characterCount) characters")
                    .font(.systemScaled(12))
                    .foregroundStyle(.black.opacity(0.4))

                // Formatting toolbar toggle
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        showingToolbar.toggle()
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "textformat")
                            .font(.systemScaled(12, weight: .medium))
                        Text(showingToolbar ? "Hide" : "Format")
                            .font(.systemScaled(12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.05))
                    .foregroundStyle(.black.opacity(0.7))
                    .cornerRadius(6)
                }

                // Animation 3: Focus toggle
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
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
                    .font(.systemScaled(16))
                    .foregroundStyle(.primary)
                    .frame(minHeight: 300)
                    .padding(16)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.thinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.70)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        focusMode
                                            ? Color.purple.opacity(0.35)
                                            : (isContentFocused ? Color.black.opacity(0.14) : Color.black.opacity(0.07)),
                                        lineWidth: focusMode ? 1.5 : 1
                                    )
                                    .animation(reduceMotion ? .none : .easeInOut(duration: 0.22), value: focusMode)
                            )
                    )
                    .shadow(color: .black.opacity(isContentFocused ? 0.06 : 0.03), radius: 8, y: 2)
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
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(.black.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    QuickInsertButton(icon: "book.fill", label: "Scripture") {
                        insertTemplate("\n\n📖 Scripture: ")
                    }
                    .accessibilityLabel("Insert scripture reference")
                    .accessibilityHint("Adds a scripture template at the end of your notes")

                    QuickInsertButton(icon: "lightbulb.fill", label: "Key Point") {
                        insertTemplate("\n\n💡 Key Point: ")
                    }
                    .accessibilityLabel("Insert key point")
                    .accessibilityHint("Adds a key point template at the end of your notes")

                    QuickInsertButton(icon: "hand.raised.fill", label: "Application") {
                        insertTemplate("\n\n🙏 Application: ")
                    }
                    .accessibilityLabel("Insert application")
                    .accessibilityHint("Adds an application template at the end of your notes")

                    QuickInsertButton(icon: "heart.fill", label: "Prayer") {
                        insertTemplate("\n\n❤️ Prayer: ")
                    }
                    .accessibilityLabel("Insert prayer")
                    .accessibilityHint("Adds a prayer template at the end of your notes")

                    QuickInsertButton(icon: "star.fill", label: "Reflection") {
                        insertTemplate("\n\n✨ Reflection: ")
                    }
                    .accessibilityLabel("Insert reflection")
                    .accessibilityHint("Adds a reflection template at the end of your notes")

                    QuickInsertButton(icon: "checkmark.circle.fill", label: "Action Step") {
                        insertTemplate("\n\n✅ Action Step: ")
                    }
                    .accessibilityLabel("Insert action step")
                    .accessibilityHint("Adds an action step template at the end of your notes")

                    QuickInsertButton(icon: "music.note", label: "Add Song") {
                        showSongSearch = true
                    }
                    .accessibilityLabel("Add worship song")
                    .accessibilityHint("Opens song search to attach a worship song to this note")

                    QuickInsertButton(icon: "mic.fill", label: "Record") {
                        showTranscription = true
                    }
                    .accessibilityLabel("Record sermon transcription")
                    .accessibilityHint("Opens live sermon transcription")

                    QuickInsertButton(icon: "camera.viewfinder", label: "Scan") {
                        showPhotoScan = true
                    }
                    .accessibilityLabel("Scan bulletin or slide")
                    .accessibilityHint("Opens camera to scan printed text into your notes")
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
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1)

                Spacer()

                Button {
                    showSongSearch = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.systemScaled(11, weight: .semibold))
                        Text("Add")
                            .font(.systemScaled(12, weight: .medium))
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
                            withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                                worshipSongs.removeAll { $0.id == song.id }
                                trackUnsavedChanges()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.systemScaled(18))
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

    // MARK: - Smart Feature Chip Bar

    private var smartFeatureChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // ── Inline panel chips ─────────────────────────────────────
                CNFeatureChip(
                    icon: "mic.fill",
                    label: "Voice",
                    isActive: showVoicePanel,
                    accentColor: Color(hex: "16A34A")
                ) {
                    withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78))) {
                        showVoicePanel.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                CNFeatureChip(
                    icon: "sparkles",
                    label: "AI Insights",
                    isActive: showAIInsightsPanel,
                    accentColor: .amenPurple
                ) {
                    withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78))) {
                        showAIInsightsPanel.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                CNFeatureChip(
                    icon: "book.closed.fill",
                    label: "Scripture",
                    isActive: showScriptureDNA,
                    accentColor: .amenBlue
                ) {
                    withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78))) {
                        showScriptureDNA.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                CNFeatureChip(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "Radar",
                    isActive: showRadarPanel,
                    accentColor: .amenCyan
                ) {
                    withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78))) {
                        showRadarPanel.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                // Divider pip
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1, height: 24)

                // ── Sheet chips ────────────────────────────────────────────
                CNFeatureChip(
                    icon: "quote.bubble.fill",
                    label: "Quote",
                    isActive: false,
                    accentColor: .cnGold
                ) {
                    quoteForgeVM.detectBestQuote(from: content)
                    showQuoteForge = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                CNFeatureChip(
                    icon: "film.fill",
                    label: "Reel",
                    isActive: false,
                    accentColor: .cnGold
                ) {
                    quoteForgeVM.detectBestQuote(from: content)
                    showReelComposer = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                CNFeatureChip(
                    icon: "person.2.fill",
                    label: "Duet",
                    isActive: false,
                    accentColor: .amenRose
                ) {
                    showCommunityDuet = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                CNFeatureChip(
                    icon: "chart.line.uptrend.xyaxis",
                    label: "Growth",
                    isActive: false,
                    accentColor: .amenEmerald
                ) {
                    showGrowthArc = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    // MARK: - AI Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("AI Tags")
                    .font(.systemScaled(13, weight: .medium))
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
                    .font(.systemScaled(12))
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
        
        // UX-3: Detect scripture references + enrich via BereanScriptureEngine
        detectedScriptures = detectScriptureReferences(in: newValue)
        scheduleScriptureEnrichment(for: newValue)

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
                    wasSaved = true
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
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.6))) {
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
                    withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.8))) {
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

    private func scheduleScriptureEnrichment(for text: String) {
        scriptureEnrichTask?.cancel()
        guard !detectedScriptures.isEmpty else {
            scriptureInsights = []
            return
        }
        scriptureEnrichTask = Task {
            // Debounce 2s to avoid hammering Claude on every keystroke
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            let results = await BereanScriptureEngine.shared.enrich(text: text)
            await MainActor.run { scriptureInsights = results }
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
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showAcceptHint = true }
                } else {
                    ghostSuggestion = ""
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { showAcceptHint = false }
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
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { titleColor = .primary }
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
                .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.7), value: contextCompletionFraction)
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.4), value: contextAllFilled)

            if contextAllFilled {
                Image(systemName: "checkmark")
                    .font(.systemScaled(9, weight: .bold))
                    .foregroundStyle(.green)
                    .scaleEffect(contextAllFilled ? 1 : 0)
                    .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.6), value: contextAllFilled)
            } else {
                Text("\(contextFilledCount)/4")
                    .font(.systemScaled(9, weight: .bold))
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
                    .font(.systemScaled(7, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.65), value: filled)
    }

    // MARK: - Animation 3 Helpers: Focus Mode + Word Momentum

    private func fireMilestoneEffect(words: Int) {
        milestoneLabel = "\(words) words ✦"
        milestoneRingScale = 0.3
        milestoneRingOpacity = 0
        milestoneLabelOffset = 0
        milestoneLabelOpacity = 0

        // Ring expands and fades
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) {
            milestoneRingScale = 1.8
            milestoneRingOpacity = 0
        }
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.1)) {
            milestoneRingOpacity = 0.8
        }

        // Label floats up and fades
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
            milestoneLabelOpacity = 1.0
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 1.2).delay(0.15)) {
            milestoneLabelOffset = -24
        }
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.5).delay(0.7)) {
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
                    .font(.systemScaled(14))
                Text(label)
                    .font(.systemScaled(14, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.68)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
            )
            .foregroundStyle(.primary)
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
                                        .font(.systemScaled(15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(song.artist)
                                        .font(.systemScaled(13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "plus.circle")
                                    .font(.systemScaled(20))
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
        } catch {
            // Non-fatal: MusicKit search failure falls through to the URL fallback below.
            print("[ERROR] ChurchNotesEditor: MusicKit search failed — \(error)")
        }
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
                .font(.systemScaled(15))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            TextField(placeholder, text: $text)
                .font(.systemScaled(16))
                .foregroundStyle(.primary)
                .tint(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.68)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        .padding(.horizontal, 20)
    }
}


// MARK: - Analyzing Pulsing Dot

private struct AnalyzingPulsingDot: View {
    @State private var scale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Color(red: 0.498, green: 0.467, blue: 0.867).opacity(0.7))
            .frame(width: 7, height: 7)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
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
                    .font(.systemScaled(11, weight: .medium))
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

// ================================================================
// FEATURE 01 — LIVE SERMON TRANSCRIPTION
// ================================================================

class SermonTranscriptionManager: NSObject, ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    @Published var transcript = ""
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var errorMessage: String?

    private var startTime: Date?
    private var timer: Timer?

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    func start() {
        guard !(speechRecognizer?.isAvailable ?? false) == false, !audioEngine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let req = recognitionRequest, let recognizer = speechRecognizer else { return }
        req.shouldReportPartialResults = true

        startTime = Date()
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let s = self.startTime else { return }
            DispatchQueue.main.async { self.elapsed = Date().timeIntervalSince(s) }
        }

        recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let result {
                DispatchQueue.main.async {
                    self?.transcript = result.bestTranscription.formattedString
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                self?.stop()
            }
        }

        let node = audioEngine.inputNode
        let fmt = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in req.append(buf) }
        audioEngine.prepare()
        try? audioEngine.start()
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        timer?.invalidate()
        DispatchQueue.main.async { self.isRecording = false }
    }

    func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }

    func save(noteId: String) {
        guard let uid = Auth.auth().currentUser?.uid, !transcript.isEmpty else { return }
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("notes").document(noteId)
            .updateData([
                "transcript": transcript,
                "audioDuration": elapsed,
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }
}

struct SermonTranscriptionView: View {
    @StateObject private var mgr = SermonTranscriptionManager()
    let noteId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Control bar
                HStack(spacing: 14) {
                    Circle()
                        .fill(mgr.isRecording ? Color.red : Color.gray.opacity(0.4))
                        .frame(width: 10, height: 10)
                        .animation(reduceMotion ? .none : .easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: mgr.isRecording)

                    Text(mgr.isRecording ? mgr.timeString(mgr.elapsed) : "00:00")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let err = mgr.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red).lineLimit(1)
                    }

                    Button(mgr.isRecording ? "Stop" : "Record") {
                        if mgr.isRecording {
                            mgr.stop()
                            mgr.save(noteId: noteId)
                        } else {
                            mgr.start()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(mgr.isRecording ? .red : .accentColor)
                }
                .padding()
                .background(Color(.systemGray6))

                ScrollView {
                    if mgr.transcript.isEmpty {
                        Text("Tap Record to start transcribing your sermon in real time.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(40)
                    } else {
                        Text(mgr.transcript)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .navigationTitle("Live Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        if mgr.isRecording { mgr.stop() }
                        dismiss()
                    }
                }
            }
            .onAppear { mgr.requestPermissions() }
            .onDisappear {
                if mgr.isRecording { mgr.stop(); mgr.save(noteId: noteId) }
            }
        }
    }
}

// ================================================================
// FEATURE 02 — PHOTO → STRUCTURED NOTES
// ================================================================

class PhotoNotesManager: ObservableObject {
    @Published var isProcessing = false
    @Published var error: String?

    func process(image: UIImage, completion: @escaping (String) -> Void) {
        isProcessing = true
        guard let cg = image.cgImage else { isProcessing = false; return }
        let req = VNRecognizeTextRequest { [weak self] req, _ in
            let raw = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""
            DispatchQueue.main.async {
                self?.isProcessing = false
                completion(raw)
            }
        }
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        }
    }
}

struct PhotoNotesScanSheet: View {
    let onExtracted: (String) -> Void
    @StateObject private var mgr = PhotoNotesManager()
    @State private var showPicker = false
    @State private var extractedText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if mgr.isProcessing {
                    ProgressView("Reading content…").padding(40)
                } else if !extractedText.isEmpty {
                    ScrollView {
                        Text(extractedText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    Button("Insert into Note") {
                        onExtracted(extractedText)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.viewfinder")
                            .font(.systemScaled(64))
                            .foregroundStyle(.secondary)
                        Text("Scan a bulletin, slide, or whiteboard\nto extract text into your notes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button { showPicker = true } label: {
                            Label("Open Camera", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                    }
                    .padding(40)
                }
            }
            .navigationTitle("Scan Bulletin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if !extractedText.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Scan Again") { extractedText = ""; showPicker = true }
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                NotesCameraPickerView { image in
                    mgr.process(image: image) { text in
                        extractedText = text
                    }
                }
            }
        }
    }
}

struct NotesCameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: NotesCameraPickerView
        init(_ p: NotesCameraPickerView) { parent = p }
        func imagePickerController(_ p: UIImagePickerController,
                                   didFinishPickingMediaWithInfo i: [UIImagePickerController.InfoKey: Any]) {
            if let img = i[.originalImage] as? UIImage { parent.onCapture(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ p: UIImagePickerController) { parent.dismiss() }
    }
}

// ================================================================
// FEATURE 03 — LIVE BIBLE VERSE LINKING
// ================================================================

class BibleVerseManager: ObservableObject {
    @Published var verses: [String: String] = [:]
    @Published var loading: Set<String> = []

    func fetchVerse(_ ref: String) {
        guard !loading.contains(ref), verses[ref] == nil else { return }
        loading.insert(ref)
        Task {
            let text = try? await NoteTagService.lookupVerse(reference: ref)
            await MainActor.run {
                loading.remove(ref)
                if let text { verses[ref] = text }
            }
        }
    }
}

struct BibleVerseChip: View {
    let reference: String
    @ObservedObject var manager: BibleVerseManager
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
                if expanded { manager.fetchVerse(reference) }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "book.closed")
                    Text(reference)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .font(.systemScaled(12, design: .serif))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(20)
            }
            .buttonStyle(.plain)

            if expanded {
                if manager.loading.contains(reference) {
                    ProgressView().scaleEffect(0.7).padding(.leading, 8)
                } else if let text = manager.verses[reference] {
                    Text("\"\(text)\"")
                        .font(.systemScaled(12, design: .serif).italic())
                        .foregroundStyle(.primary.opacity(0.8))
                        .padding(8)
                        .background(Color.orange.opacity(0.06))
                        .cornerRadius(8)
                        .highlightable(text: text, verse: reference, church: "")
                }
            }
        }
    }
}

// ================================================================
// FEATURE 07 — SHARE HIGHLIGHTS TO FEED
// ================================================================

struct HighlightableModifier: ViewModifier {
    let text: String
    let verse: String
    let church: String
    var noteId: String = ""
    @State private var showSheet = false

    func body(content: Content) -> some View {
        content.onLongPressGesture { showSheet = true }
            .confirmationDialog("Share highlight", isPresented: $showSheet) {
                Button("Post to AMEN Feed") {
                    guard let uid = Auth.auth().currentUser?.uid else { return }
                    Firestore.firestore().collection("communityFeed").addDocument(data: [
                        "type": "highlight",
                        "quote": text,
                        "verseRef": verse,
                        "churchName": church,
                        "authorId": uid,
                        "createdAt": FieldValue.serverTimestamp(),
                        "likes": 0,
                        "prayers": 0
                    ])
                }
                // Notes-to-Prayer Bridge: pre-seed a new prayer request from this verse/highlight
                if !verse.isEmpty {
                    Button("Turn into Prayer Request") {
                        PrayerPreSeedState.shared.seed(
                            verseReference: verse,
                            verseText: text,
                            noteId: noteId
                        )
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

extension View {
    func highlightable(text: String, verse: String = "", church: String = "", noteId: String = "") -> some View {
        modifier(HighlightableModifier(text: text, verse: verse, church: church, noteId: noteId))
    }
}

// ================================================================
// FEATURE 08 — SCRIPTURE REMINDER CADENCE
// ================================================================

class ScriptureReminderManager: ObservableObject {
    @Published var isScheduled = false
    private let intervals = [(label: "Tomorrow", days: 1), (label: "In 3 days", days: 3),
                              (label: "In 1 week", days: 7), (label: "In 30 days", days: 30)]

    func schedule(verse: String, reference: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            guard granted else { return }
            self?.createNotifications(verse: verse, reference: reference)
            DispatchQueue.main.async { self?.isScheduled = true }
        }
    }

    private func createNotifications(verse: String, reference: String) {
        let center = UNUserNotificationCenter.current()
        let preview = verse.count > 80 ? String(verse.prefix(80)) + "…" : verse
        for (label, days) in intervals {
            let content = UNMutableNotificationContent()
            content.title = "📖 Scripture Review"
            content.body = "\(reference): \"\(preview)\""
            content.subtitle = label
            content.sound = .default
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.day = (comps.day ?? 0) + days
            comps.hour = 8; comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = "sr_\(reference.filter { $0.isLetter || $0.isNumber })_\(days)"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    func cancel(reference: String) {
        let ids = intervals.map { "sr_\(reference.filter { $0.isLetter || $0.isNumber })_\($0.days)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        isScheduled = false
    }
}

struct ScriptureReminderView: View {
    let verse: String
    let reference: String
    @StateObject private var mgr = ScriptureReminderManager()

    var body: some View {
        Button {
            if mgr.isScheduled { mgr.cancel(reference: reference) }
            else { mgr.schedule(verse: verse, reference: reference) }
        } label: {
            Label(
                mgr.isScheduled ? "Reminders On ✓" : "Memorize This Verse",
                systemImage: mgr.isScheduled ? "bell.fill" : "bell.badge"
            )
            .font(.systemScaled(12, weight: .medium))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(mgr.isScheduled ? .green : .orange)
        .controlSize(.small)
    }
}

// MARK: - CNFeatureChip
// Liquid glass pill button used in the smart feature chip bar.
// Active state glows with the chip's accent colour.

struct CNFeatureChip: View {
    let icon: String
    let label: String
    let isActive: Bool
    let accentColor: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isActive ? accentColor : Color.primary.opacity(0.65))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                Capsule()
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule()
                            .fill(isActive
                                  ? accentColor.opacity(0.12)
                                  : Color.primary.opacity(0.03))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isActive
                                    ? accentColor.opacity(0.45)
                                    : Color.primary.opacity(0.08),
                                lineWidth: isActive ? 1.5 : 1
                            )
                    }
                    .shadow(
                        color: isActive ? accentColor.opacity(0.25) : .clear,
                        radius: 8, y: 3
                    )
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.7)), value: isActive)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}
