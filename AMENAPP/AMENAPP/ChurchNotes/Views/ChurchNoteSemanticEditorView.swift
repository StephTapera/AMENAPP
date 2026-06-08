// ChurchNoteSemanticEditorView.swift
// AMENAPP
//
// Full semantic block editor for ChurchNoteV2.
// Design: glass capsule toolbar, block list, floating quick-action bar.
// Each block is rendered inline; tapping a block activates an editing sheet.

import SwiftUI
import FirebaseAuth
import UniformTypeIdentifiers

extension Notification.Name {
    static let churchNoteEdited = Notification.Name("amen.churchNoteEdited")
}

// MARK: - Editor ViewModel

@MainActor
final class ChurchNoteSemanticEditorViewModel: ObservableObject {
    @Published var note: ChurchNoteV2
    @Published var blocks: [ChurchNoteBlockV2] = []
    @Published var isSaving = false
    @Published var error: String?
    @Published var showBlockFactory = false
    @Published var editingBlock: ChurchNoteBlockV2?
    @Published var showSelah = false

    private let repository = ChurchNoteBlockRepository.shared
    let intelligenceRepo = ChurchNotesIntelligenceRepository.shared
    private let intelligenceService = ChurchNotesIntelligenceService.shared
    private var autosaveTask: Task<Void, Never>?

    // MARK: - AI State Enums

    enum AIReviewState: Equatable {
        case notGenerated
        case generating
        case generated([CNReviewSuggestion])
        case stale
        case failed(String)

        static func == (lhs: AIReviewState, rhs: AIReviewState) -> Bool {
            switch (lhs, rhs) {
            case (.notGenerated, .notGenerated), (.generating, .generating), (.stale, .stale): return true
            case (.generated(let a), .generated(let b)): return a.map(\.id) == b.map(\.id)
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    enum BereanInsightState: Equatable {
        case notFetched
        case fetching
        case fetched(ScripturePassagePayload)
        case failed

        static func == (lhs: BereanInsightState, rhs: BereanInsightState) -> Bool {
            switch (lhs, rhs) {
            case (.notFetched, .notFetched), (.fetching, .fetching), (.failed, .failed): return true
            case (.fetched(let a), .fetched(let b)): return a.id == b.id
            default: return false
            }
        }
    }

    // Intelligence state
    @Published var anchorPickerBlock: ChurchNoteBlockV2?
    @Published var aiReviewState: AIReviewState = .notGenerated
    @Published var bridge: CNSermonBridge
    @Published var showBridgeCard = false
    @Published var connections: [ChurchNoteConnection] = []
    @Published var detectedPosture: CNPostureSignal?
    @Published var showReflectionScheduler = false
    @Published var selectedReplayIntervals: Set<Int> = []
    @Published var bereanInsightState: BereanInsightState = .notFetched

    // Backward-compatible computed properties so existing view code compiles unchanged.
    var showReviewStrip: Bool {
        get {
            if case .generated(let s) = aiReviewState { return !s.isEmpty }
            return false
        }
        set { if !newValue { aiReviewState = .notGenerated } }
    }
    var reviewSuggestions: [CNReviewSuggestion] {
        if case .generated(let s) = aiReviewState { return s }
        return []
    }
    var bereanPassageInsight: ScripturePassagePayload? {
        if case .fetched(let p) = bereanInsightState { return p }
        return nil
    }
    var isFetchingBereanInsight: Bool {
        bereanInsightState == .fetching
    }

    init(note: ChurchNoteV2? = nil) {
        if let note {
            self.note = note
            self.bridge = CNSermonBridge.empty(noteId: note.id)
        } else {
            let uid = Auth.auth().currentUser?.uid ?? ""
            let newNote = ChurchNoteV2.empty(userId: uid)
            self.note = newNote
            self.bridge = CNSermonBridge.empty(noteId: newNote.id)
        }
    }

    func startEditing() {
        Task {
            // Ensure the note doc exists before listening for blocks
            if blocks.isEmpty && note.blockCount == 0 {
                try? await repository.createNote(note)
                // Seed with one empty paragraph
                let seed = ChurchNoteBlockV2.paragraph(text: "", order: 0)
                try? await repository.addBlock(seed, to: note.id)
            }
            repository.startListeningToBlocks(noteId: note.id)
        }
    }

    func stopEditing() {
        repository.stopListeningToBlocks()
        autosaveTask?.cancel()
    }

    func addBlock(_ block: ChurchNoteBlockV2) {
        var b = block
        b = ChurchNoteBlockV2(
            id: b.id,
            sortOrder: (blocks.last?.sortOrder ?? -1) + 1,
            type: b.type,
            semanticType: b.semanticType,
            visibility: b.visibility,
            pinnedState: b.pinnedState,
            text: b.text,
            richSpans: b.richSpans,
            versePayload: b.versePayload,
            calloutPayload: b.calloutPayload,
            sectionPayload: b.sectionPayload,
            checklistPayload: b.checklistPayload,
            createdAt: b.createdAt,
            updatedAt: b.updatedAt
        )
        Task {
            try? await repository.addBlock(b, to: note.id)
            await MainActor.run { self.notifyNoteEdited() }
        }
    }

    func updateBlock(_ block: ChurchNoteBlockV2) {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s debounce
            guard !Task.isCancelled else { return }
            try? await repository.updateBlock(block, in: note.id)
            await MainActor.run { self.notifyNoteEdited() }
        }
    }

    func deleteBlock(_ block: ChurchNoteBlockV2) {
        Task {
            try? await repository.deleteBlock(blockId: block.id, from: note.id)
            await MainActor.run { self.notifyNoteEdited() }
        }
    }

    func toggleVisibility(for block: ChurchNoteBlockV2) {
        let next: ChurchNoteVisibility = block.visibility == .privateOnly ? .shareable : .privateOnly
        Task {
            try? await repository.updateBlockVisibility(
                blockId: block.id,
                noteId: note.id,
                visibility: next
            )
            await MainActor.run { self.notifyNoteEdited() }
        }
    }

    func togglePin(_ state: ChurchNotePinnedState, for block: ChurchNoteBlockV2) {
        let next: ChurchNotePinnedState = block.pinnedState == state ? .none : state
        Task {
            try? await repository.updateBlockPinnedState(
                blockId: block.id,
                noteId: note.id,
                pinnedState: next
            )
            await MainActor.run { self.notifyNoteEdited() }
        }
    }

    var pinnedBlocks: [ChurchNoteBlockV2] {
        blocks.filter { $0.pinnedState != .none }
    }

    // MARK: - Intelligence methods

    func applyAnchor(_ anchorType: CNAnchorType?, to block: ChurchNoteBlockV2) {
        let newSemanticType = anchorType?.semanticType ?? .general
        let updated = ChurchNoteBlockV2(
            id: block.id, sortOrder: block.sortOrder, type: block.type,
            semanticType: newSemanticType, visibility: block.visibility, pinnedState: block.pinnedState,
            text: block.text, richSpans: block.richSpans, versePayload: block.versePayload,
            calloutPayload: block.calloutPayload, sectionPayload: block.sectionPayload,
            checklistPayload: block.checklistPayload,
            createdAt: block.createdAt, updatedAt: Date()
        )
        updateBlock(updated)
    }

    private func notifyNoteEdited() {
        NotificationCenter.default.post(
            name: .churchNoteEdited,
            object: nil,
            userInfo: ["noteId": note.id]
        )
    }

    func computeIntelligence() {
        // Posture detection — runs locally, never blocks UI
        Task {
            let currentBlocks = blocks
            let posture = intelligenceService.detectPosture(from: currentBlocks)
            await MainActor.run { detectedPosture = posture }

            // Note connections
            let allNotes = repository.notes
            let found = await intelligenceService.findConnections(
                sourceNote: note,
                sourceBlocks: currentBlocks,
                allNotes: allNotes
            )
            await MainActor.run { connections = found }
        }
        // Fetch Berean AI insight for the primary verse (lazy — only once per note session)
        if bereanPassageInsight == nil {
            fetchBereanInsight()
        }
    }

    func fetchBereanInsight() {
        // Prefer the first verse-embed block's reference; fall back to note-level scriptureReferences
        let verseRef = blocks
            .first { $0.type == .verseEmbed }?
            .versePayload?.reference
            ?? note.scriptureReferences.first
        guard let ref = verseRef, !ref.isEmpty else { return }
        guard bereanInsightState != .fetching else { return }
        bereanInsightState = .fetching
        Task {
            if let result = try? await BereanAPIClient.shared.studyPassage(reference: ref) {
                bereanInsightState = .fetched(result)
            } else {
                bereanInsightState = .failed
            }
        }
    }

    func prepareReviewStrip() {
        aiReviewState = .generating
        let suggestions = intelligenceService.reviewSuggestions(
            for: blocks,
            bridge: bridge.isPopulated ? bridge : nil,
            reflections: []
        )
        withAnimation(ChurchNotesAnimationTokens.reviewMode) {
            aiReviewState = suggestions.isEmpty ? .notGenerated : .generated(suggestions)
        }
    }

    func saveBridge() {
        Task {
            var updated = bridge
            updated.noteId = note.id
            updated.id = note.id
            try? await intelligenceRepo.saveBridge(updated)
        }
    }

    func scheduleReplay() {
        Task {
            for days in selectedReplayIntervals {
                try? await intelligenceRepo.scheduleReflectionReplay(noteId: note.id, afterDays: days)
            }
        }
    }
}

// MARK: - Main Editor View

struct ChurchNoteSemanticEditorView: View {

    @StateObject private var vm: ChurchNoteSemanticEditorViewModel
    @EnvironmentObject private var blockRepo: ChurchNoteBlockRepository
    @Environment(\.dismiss) private var dismiss
    @State private var showLivingEntries = false
    @State private var linkedNoteToOpen: ChurchNoteV2?  // wires onOpenNote from connections section

    // MARK: - Media Intelligence state
    @StateObject private var processingService = ChurchNotesMediaProcessingService()
    @State private var showAudioRecorder = false
    @State private var showPhotoOCR      = false
    @State private var showVideoImporter = false
    @State private var showAudioImporter = false
    @State private var showImageImporter = false
    @State private var showDocumentImporter = false
    @State private var showCollaboration = false
    @State private var showComments = false
    @State private var showSearch = false
    @State private var importError: String?
    @State private var reviewingJob: ChurchNoteProcessingJob?
    @State private var dismissedJobIds   = Set<String>()
    @StateObject private var collaborationService = ChurchNotesCollaborationService()
    @StateObject private var commentsService = ChurchNotesCommentsService()

    init(note: ChurchNoteV2? = nil) {
        _vm = StateObject(wrappedValue: ChurchNoteSemanticEditorViewModel(note: note))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        noteHeader
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        if !vm.pinnedBlocks.isEmpty {
                            pinnedStrip
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        LazyVStack(spacing: 4) {
                            ForEach(blockRepo.activeBlocks) { block in
                                SemanticBlockCellView(
                                    block: block,
                                    onEdit: { vm.editingBlock = block },
                                    onDelete: { vm.deleteBlock(block) },
                                    onToggleVisibility: { vm.toggleVisibility(for: block) },
                                    onPin: { vm.togglePin(.anchorInsight, for: block) },
                                    onMarkAnchor: { vm.anchorPickerBlock = block }
                                )
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 20)

                    // Intelligence section
                    intelligenceSection
                        .padding(.bottom, 140)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .onAppear {
                    vm.startEditing()
                    collaborationService.start(noteId: vm.note.id, currentRole: currentCollaborationRole)
                    commentsService.start(noteId: vm.note.id)
                }
                .onDisappear {
                    vm.stopEditing()
                    collaborationService.stop()
                    commentsService.stop()
                }
                .task {
                    // Load bridge and compute intelligence after blocks settle
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    if let loaded = await vm.intelligenceRepo.loadBridge(noteId: vm.note.id) {
                        vm.bridge = loaded
                    }
                    vm.computeIntelligence()
                }

                // Review strip — appears above floating toolbar when user presses Done
                if vm.showReviewStrip {
                    VStack(spacing: 0) {
                        Spacer()
                        ChurchNoteReviewStrip(
                            suggestions: vm.reviewSuggestions,
                            onSuggestionTap: { action in
                                vm.showReviewStrip = false
                                handleReviewAction(action)
                            },
                            onDismiss: { vm.showReviewStrip = false }
                        )
                        .padding(.bottom, 100)  // clear the floating toolbar
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Processing jobs status (Media Intelligence) — above floating toolbar
                let visibleJobs = processingService.activeJobs
                    .filter { !dismissedJobIds.contains($0.id) }
                if !visibleJobs.isEmpty {
                    VStack(spacing: 0) {
                        Spacer()
                        ChurchNotesProcessingJobList(
                            jobs: visibleJobs,
                            onReviewJob: { job in reviewingJob = job },
                            onDismissJob: { job in dismissedJobIds.insert(job.id) }
                        )
                        .padding(.bottom, 96) // clear floating toolbar
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                floatingToolbar
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        vm.saveBridge()
                        vm.prepareReviewStrip()
                        if vm.reviewSuggestions.isEmpty {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // Posture indicator
                        if let posture = vm.detectedPosture {
                            Image(systemName: posture.icon)
                                .font(.systemScaled(14))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Tone: \(posture.displayName)")
                        }
                        Button {
                            showLivingEntries = true
                        } label: {
                            Image(systemName: "square.stack.3d.up")
                                .font(.systemScaled(15))
                        }
                        .accessibilityLabel("Open Living Entries")
                        Button {
                            showSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("Search Church Notes")
                        Button {
                            showComments = true
                        } label: {
                            Image(systemName: "text.bubble")
                        }
                        .accessibilityLabel("Open comments")
                        Button {
                            showCollaboration = true
                        } label: {
                            Image(systemName: "person.2")
                        }
                        .accessibilityLabel("Manage collaborators")
                        Button {
                            vm.showSelah = true
                        } label: {
                            Image(systemName: "sparkles")
                        }
                        .accessibilityLabel("Open Selah view")
                    }
                }
            }
            .sheet(isPresented: $showLivingEntries) {
                LivingEntriesHomeView(initialFilter: .churchNotes)
            }
            .sheet(isPresented: $showCollaboration) {
                ChurchNoteCollaborationView(
                    noteId: vm.note.id,
                    currentRole: currentCollaborationRole,
                    service: collaborationService
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showComments) {
                ChurchNoteCommentsView(
                    noteId: vm.note.id,
                    currentRole: currentCollaborationRole,
                    defaultAnchorText: selectedCommentAnchor,
                    service: commentsService
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSearch) {
                ChurchNotesSearchView { noteId in
                    let uid = Auth.auth().currentUser?.uid ?? ""
                    linkedNoteToOpen = ChurchNoteV2(
                        id: noteId, userId: uid, title: "",
                        tags: [], scriptureReferences: [],
                        blockCount: 0, hasShareableBlocks: false,
                        pinnedBlockIds: [], schemaVersion: 2,
                        createdAt: Date(), updatedAt: Date()
                    )
                }
                .presentationDetents([.large])
            }
            .sheet(item: $vm.anchorPickerBlock) { block in
                ChurchNoteAnchorPickerSheet(
                    currentSemanticType: block.semanticType
                ) { anchorType in
                    vm.applyAnchor(anchorType, to: block)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $vm.showReflectionScheduler) {
                NavigationStack {
                    CNReflectionSchedulePicker(selectedIntervals: $vm.selectedReplayIntervals) {
                        vm.scheduleReplay()
                        vm.showReflectionScheduler = false
                    }
                    .navigationTitle("Revisit this note")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $vm.showBridgeCard) {
                NavigationStack {
                    ScrollView {
                        ChurchNoteSermonBridgeCard(
                            bridge: $vm.bridge,
                            onChanged: { vm.saveBridge() }
                        )
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                    .navigationTitle("Carry into your week")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { vm.showBridgeCard = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $vm.showBlockFactory) {
                BlockFactorySheet { block in
                    vm.addBlock(block)
                    vm.showBlockFactory = false
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $vm.editingBlock) { block in
                BlockEditSheet(block: block) { updated in
                    vm.updateBlock(updated)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $vm.showSelah) {
                ChurchNoteSelahRenderView(noteId: vm.note.id)
            }
            // Opens a linked/connected note from the connections section
            .sheet(item: $linkedNoteToOpen) { note in
                ChurchNoteSemanticEditorView(note: note)
                    .presentationDetents([.large])
            }
            // Media Intelligence: Audio recorder
            .sheet(isPresented: $showAudioRecorder) {
                ChurchNotesAudioRecorderView(
                    noteId: vm.note.id,
                    processingService: processingService,
                    onDismiss: { showAudioRecorder = false }
                )
                .presentationDetents([.large])
            }
            // Media Intelligence: Photo OCR
            .sheet(isPresented: $showPhotoOCR) {
                ChurchNotesPhotoOCRCaptureView(
                    noteId: vm.note.id,
                    processingService: processingService,
                    onDismiss: { showPhotoOCR = false }
                )
                .presentationDetents([.large])
            }
            .fileImporter(
                isPresented: $showVideoImporter,
                allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, .movie],
                allowsMultipleSelection: false
            ) { result in
                handleVideoImport(result)
            }
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav],
                allowsMultipleSelection: false
            ) { result in
                handleAudioImport(result)
            }
            .fileImporter(
                isPresented: $showImageImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                handleImageImport(result)
            }
            .fileImporter(
                isPresented: $showDocumentImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleDocumentImport(result)
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "The file could not be imported.")
            }
            // Media Intelligence: Draft review
            .sheet(item: $reviewingJob) { job in
                ChurchNotesAIDraftReviewView(
                    job: job,
                    processingService: processingService,
                    onApproved: { result in
                        insertApprovedDraftAsBlock(result: result)
                        reviewingJob = nil
                    },
                    onDismiss: { reviewingJob = nil }
                )
                .presentationDetents([.large])
            }
        }
    }

    // MARK: - Media imports

    private func handleVideoImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                await processingService.uploadVideoAndCreateJob(
                    fileURL: url,
                    noteId: vm.note.id,
                    durationSeconds: nil
                )
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func handleAudioImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                await processingService.uploadAudioAndCreateJob(
                    fileURL: url,
                    noteId: vm.note.id,
                    durationSeconds: 0
                )
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func handleImageImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    await processingService.uploadImageAndCreateJob(imageData: data, noteId: vm.note.id)
                } catch {
                    importError = error.localizedDescription
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func handleDocumentImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                await processingService.uploadDocumentAndCreateJob(fileURL: url, noteId: vm.note.id)
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private var currentCollaborationRole: ChurchNoteCollaboratorRole {
        if Auth.auth().currentUser?.uid == vm.note.userId {
            return .owner
        }
        return collaborationService.collaborators.first {
            $0.uid == Auth.auth().currentUser?.uid
        }?.role ?? .viewer
    }

    private var selectedCommentAnchor: String {
        vm.editingBlock?.text ?? vm.note.sermonTitle ?? vm.note.title
    }

    // MARK: - Note Header

    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Sermon title", text: Binding(
                get: { vm.note.sermonTitle ?? "" },
                set: { vm.note.sermonTitle = $0.isEmpty ? nil : $0 }
            ))
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)

            TextField("Speaker (optional)", text: Binding(
                get: { vm.note.sermonSpeaker ?? "" },
                set: { vm.note.sermonSpeaker = $0.isEmpty ? nil : $0 }
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Pinned Strip

    private var pinnedStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pinned")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.pinnedBlocks) { block in
                        pinnedChip(block)
                    }
                }
            }
        }
    }

    private func pinnedChip(_ block: ChurchNoteBlockV2) -> some View {
        HStack(spacing: 6) {
            Image(systemName: block.pinnedState.icon)
                .font(.caption2)
                .foregroundStyle(block.semanticType.accentColor)
            Text(block.text.isEmpty ? block.type.displayName : String(block.text.prefix(30)))
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
    }

    // MARK: - Intelligence Section (below blocks, above toolbar)

    private var intelligenceSection: some View {
        VStack(spacing: 10) {
            // Connections section
            if !vm.connections.isEmpty {
                ChurchNoteConnectionsSection(
                    connections: vm.connections,
                    onOpenNote: { noteId in
                        let uid = Auth.auth().currentUser?.uid ?? ""
                        linkedNoteToOpen = ChurchNoteV2(
                            id: noteId, userId: uid, title: "",
                            tags: [], scriptureReferences: [],
                            blockCount: 0, hasShareableBlocks: false,
                            pinnedBlockIds: [], schemaVersion: 2,
                            createdAt: Date(), updatedAt: Date()
                        )
                    }
                )
                .padding(.horizontal, 16)
            }

            // Bridge entry point
            if vm.bridge.isPopulated {
                ChurchNoteSermonBridgeCard(
                    bridge: $vm.bridge,
                    onChanged: { vm.saveBridge() }
                )
                .padding(.horizontal, 16)
            }

            // Berean AI Scripture Insight
            if vm.isFetchingBereanInsight || vm.bereanPassageInsight != nil {
                BereanChurchNoteInsightCard(
                    insight: vm.bereanPassageInsight,
                    isLoading: vm.isFetchingBereanInsight,
                    onStudyDeeper: {
                        vm.fetchBereanInsight()
                    }
                )
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Review Action Handler

    private func handleReviewAction(_ action: CNReviewAction) {
        switch action {
        case .addTakeaway:
            vm.addBlock(ChurchNoteBlockV2(type: .takeaway, semanticType: .keyTruth))
        case .addPrayer:
            vm.addBlock(ChurchNoteBlockV2.callout(style: .prayer))
        case .addVerse:
            vm.addBlock(ChurchNoteBlockV2.verseEmbed(reference: "", text: ""))
        case .addAction:
            vm.addBlock(ChurchNoteBlockV2.callout(style: .action))
        case .markAnchor:
            if let firstBlock = vm.blocks.first {
                vm.anchorPickerBlock = firstBlock
            }
        case .setReflectionReminder:
            vm.showReflectionScheduler = true
        case .fillBridge:
            vm.showBridgeCard = true
        }
    }

    // MARK: - Draft approval → block insertion

    private func insertApprovedDraftAsBlock(result: ChurchNoteDraftApprovalResult) {
        let nextOrder = (blockRepo.activeBlocks.last?.sortOrder ?? -1) + 1
        // Split approved text into paragraph blocks (one per non-empty line group).
        let paragraphs = result.approvedText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for (offset, paragraph) in paragraphs.enumerated() {
            let semanticType: ChurchNoteSemanticType
            switch result.draftField {
            case .summaryDraft:      semanticType = .keyTruth
            case .studyGuideDraft:   semanticType = .question
            case .prayerPromptsDraft: semanticType = .prayerPoint
            default:                 semanticType = .general
            }
            let block = ChurchNoteBlockV2(
                sortOrder:    nextOrder + offset,
                type:         .paragraph,
                semanticType: semanticType,
                visibility:   .privateOnly,
                text:         paragraph
            )
            vm.addBlock(block)
        }
    }

    // MARK: - Floating Toolbar

    private var floatingToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    vm.showBlockFactory = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Block")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.primary)
                    .foregroundStyle(Color(.systemBackground))
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Add a new block")

                Spacer()

                // Media capture (audio/photo OCR) — gated by feature flags
                let flags = AMENFeatureFlags.shared
                if flags.churchNotesAudioCaptureEnabled || flags.churchNotesPhotoOCREnabled || flags.churchNotesVideoCaptureEnabled || flags.sermonVideoCaptureEnabled || flags.churchNotesIntelligenceEnabled {
                    Menu {
                        if flags.churchNotesAudioCaptureEnabled && !flags.churchNotesProcessingKillSwitch {
                            Button {
                                showAudioRecorder = true
                            } label: {
                                Label("Record Sermon", systemImage: "mic.fill")
                            }
                            Button {
                                showAudioImporter = true
                            } label: {
                                Label("Upload Audio", systemImage: "waveform")
                            }
                        }
                        if (flags.churchNotesVideoCaptureEnabled || flags.sermonVideoCaptureEnabled) && !flags.churchNotesProcessingKillSwitch {
                            Button {
                                showVideoImporter = true
                            } label: {
                                Label("Upload Video", systemImage: "video.fill")
                            }
                        }
                        if flags.churchNotesPhotoOCREnabled && !flags.churchNotesProcessingKillSwitch {
                            Button {
                                showPhotoOCR = true
                            } label: {
                                Label("Capture Board / Screen", systemImage: "camera.fill")
                            }
                            Button {
                                showImageImporter = true
                            } label: {
                                Label("Upload Image", systemImage: "photo")
                            }
                        }
                        if flags.churchNotesIntelligenceEnabled && !flags.churchNotesProcessingKillSwitch {
                            Button {
                                showDocumentImporter = true
                            } label: {
                                Label("Import PDF", systemImage: "doc.richtext.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "camera.on.rectangle.fill")
                            .font(.systemScaled(16))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Capture sermon media")
                    .accessibilityHint("Record audio or photograph a board for AI transcription")
                }

                // Quick semantic presets
                ForEach([ChurchNoteCalloutStyle.prayer, .action, .reflection], id: \.self) { style in
                    Button {
                        vm.addBlock(ChurchNoteBlockV2.callout(style: style, order: (blockRepo.activeBlocks.last?.sortOrder ?? -1) + 1))
                    } label: {
                        Image(systemName: style.icon)
                            .font(.systemScaled(16))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(style.fillColor.opacity(0.9))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Add \(style.displayName) callout")
                }

                // Bridge shortcut
                Button {
                    vm.showBridgeCard = true
                } label: {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.systemScaled(16))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGreen).opacity(0.12))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Carry into the week")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.48), Color.white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Semantic Block Cell

struct SemanticBlockCellView: View {

    let block: ChurchNoteBlockV2
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleVisibility: () -> Void
    let onPin: () -> Void
    let onMarkAnchor: () -> Void

    @State private var showMenu = false

    private var blockAnchorType: CNAnchorType? {
        let anchorables: [ChurchNoteSemanticType] = [
            .conviction, .keyTruth, .prayerPoint, .actionStep,
            .question, .verseInsight, .pastorQuote, .testimony,
        ]
        guard anchorables.contains(block.semanticType) else { return nil }
        return CNAnchorType(from: block.semanticType)
    }

    var body: some View {
        Button(action: onEdit) {
            blockContent
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", action: onEdit)
            Button {
                onToggleVisibility()
            } label: {
                Label(
                    block.visibility == .privateOnly ? "Mark Shareable" : "Make Private",
                    systemImage: block.visibility == .privateOnly ? "square.and.arrow.up" : "lock"
                )
            }
            Button {
                onPin()
            } label: {
                Label(
                    block.pinnedState == .none ? "Pin as Anchor" : "Unpin",
                    systemImage: block.pinnedState == .none ? "pin.fill" : "pin.slash"
                )
            }
            Divider()
            Button {
                onMarkAnchor()
            } label: {
                Label(
                    blockAnchorType != nil ? "Change Anchor" : "Mark Anchor",
                    systemImage: "anchor"
                )
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Block", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.type.displayName): \(block.text.prefix(60))")
        .accessibilityHint("Double tap to edit. Long press for options.")
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block.type {
        case .paragraph, .heading, .subheading, .annotation:
            paragraphCell

        case .quote, .takeaway, .prayer, .action, .scripture:
            semanticPillCell

        case .callout:
            calloutCell

        case .verseEmbed:
            verseCell

        case .checklist:
            checklistCell

        case .divider:
            Divider().padding(.vertical, 4)

        case .section:
            sectionCell

        case .bulletList, .numberedList:
            listCell
        }
    }

    private var paragraphCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            if block.type == .heading {
                Text(block.text.isEmpty ? "Heading" : block.text)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
            } else if block.type == .subheading {
                Text(block.text.isEmpty ? "Subheading" : block.text)
                    .font(.headline)
                    .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
            } else {
                Text(block.text.isEmpty ? "Type something..." : block.text)
                    .font(.body)
                    .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .overlay(alignment: .leading) {
            if block.semanticType != .general {
                Rectangle()
                    .fill(block.semanticType.accentColor.opacity(0.5))
                    .frame(width: 2)
                    .clipShape(Capsule())
            }
        }
    }

    private var semanticPillCell: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: block.type.icon)
                .font(.systemScaled(14))
                .foregroundStyle(block.semanticType.accentColor)
                .frame(width: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(block.type.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(block.semanticType.accentColor)
                    if let anchor = blockAnchorType {
                        ChurchNoteAnchorChip(anchor: anchor)
                    }
                }

                Text(block.text.isEmpty ? "Type here..." : block.text)
                    .font(.subheadline)
                    .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            visibilityBadge
        }
        .padding(12)
        .background(
            block.semanticType.accentColor.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(block.semanticType.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var calloutCell: some View {
        let style = block.calloutPayload?.style ?? .reflection
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.icon)
                .font(.systemScaled(15))
                .foregroundStyle(style.borderColor)
                .frame(width: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(style.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.borderColor)

                if let prompt = block.calloutPayload?.prompt, !prompt.isEmpty, block.text.isEmpty {
                    Text(prompt)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .italic()
                } else {
                    Text(block.text.isEmpty ? "Tap to write..." : block.text)
                        .font(.subheadline)
                        .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
                }
            }
            Spacer()
            visibilityBadge
        }
        .padding(14)
        .background(style.fillColor, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style.borderColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var verseCell: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "book.fill")
                .font(.systemScaled(14))
                .foregroundStyle(Color(hex: "8AA8D8"))
                .frame(width: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if let payload = block.versePayload {
                    Text(payload.reference)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: "8AA8D8"))

                    Text(payload.verseText.isEmpty ? "Verse text loading..." : payload.verseText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .italic()

                    Text(payload.translation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add verse reference")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            visibilityBadge
        }
        .padding(12)
        .background(Color(hex: "DCE7F7").opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(hex: "B9CBE7").opacity(0.6), lineWidth: 1)
        )
    }

    private var checklistCell: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let payload = block.checklistPayload {
                HStack {
                    Image(systemName: payload.category.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(payload.category.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                ForEach(payload.items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.completed ? .primary : Color(.tertiaryLabel))
                            .font(.systemScaled(16))
                            .accessibilityHidden(true)
                        Text(item.text)
                            .font(.subheadline)
                            .strikethrough(item.completed)
                            .foregroundStyle(item.completed ? .secondary : .primary)
                    }
                }

                if payload.items.isEmpty {
                    Text("Tap to add items")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private var sectionCell: some View {
        HStack {
            Image(systemName: block.sectionPayload?.isCollapsed == true
                  ? "chevron.right" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(block.sectionPayload?.heading ?? "Section")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private var listCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(block.text.isEmpty ? "List item..." : block.text)
                .font(.body)
                .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var visibilityBadge: some View {
        if block.visibility != .privateOnly {
            Image(systemName: "square.and.arrow.up")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Shareable block")
        }
        if block.pinnedState != .none {
            Image(systemName: "pin.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Pinned block")
        }
    }
}

// MARK: - Block Factory Sheet

struct BlockFactorySheet: View {

    let onSelect: (ChurchNoteBlockV2) -> Void

    private let insertableTypes = ChurchNoteBlockV2Type.insertableTypes
    private let calloutStyles = ChurchNoteCalloutStyle.allCases
    private let checklistCategories = ChurchNoteChecklistCategory.allCases

    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Blocks").tag(0)
                    Text("Callouts").tag(1)
                    Text("Checklists").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(16)

                ScrollView {
                    if tab == 0 {
                        blockTypeGrid
                    } else if tab == 1 {
                        calloutGrid
                    } else {
                        checklistGrid
                    }
                }
            }
            .navigationTitle("Add Block")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var blockTypeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
            ForEach(insertableTypes.filter { ![.callout, .checklist, .verseEmbed].contains($0) }) { type in
                blockTypeButton(type)
            }
            // Verse embed gets its own cell
            Button {
                onSelect(ChurchNoteBlockV2.verseEmbed(reference: "", text: ""))
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: ChurchNoteBlockV2Type.verseEmbed.icon)
                        .font(.systemScaled(20))
                        .foregroundStyle(Color(hex: "8AA8D8"))
                    Text(ChurchNoteBlockV2Type.verseEmbed.displayName)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "DCE7F7").opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add verse embed block")
        }
        .padding(16)
    }

    private func blockTypeButton(_ type: ChurchNoteBlockV2Type) -> some View {
        Button {
            onSelect(ChurchNoteBlockV2(type: type))
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.systemScaled(20))
                    .foregroundStyle(.primary)
                Text(type.displayName)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(type.displayName) block")
    }

    private var calloutGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
            ForEach(calloutStyles) { style in
                Button {
                    onSelect(ChurchNoteBlockV2.callout(style: style))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: style.icon)
                            .font(.systemScaled(16))
                            .foregroundStyle(style.borderColor)
                        Text(style.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(12)
                    .background(style.fillColor, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style.borderColor.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(style.displayName) callout")
            }
        }
        .padding(16)
    }

    private var checklistGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
            ForEach(checklistCategories) { category in
                Button {
                    onSelect(ChurchNoteBlockV2.checklist(category: category))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: category.icon)
                            .font(.systemScaled(16))
                            .foregroundStyle(.secondary)
                        Text(category.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(category.displayName) checklist")
            }
        }
        .padding(16)
    }
}

// MARK: - Block Edit Sheet

struct BlockEditSheet: View {
    @State private var block: ChurchNoteBlockV2
    let onSave: (ChurchNoteBlockV2) -> Void
    @Environment(\.dismiss) private var dismiss

    init(block: ChurchNoteBlockV2, onSave: @escaping (ChurchNoteBlockV2) -> Void) {
        _block = State(initialValue: block)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Text editor
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Content")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        TextEditor(text: $block.text)
                            .font(.body)
                            .frame(minHeight: 100)
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Semantic type picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meaning")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ChurchNoteSemanticType.allCases) { type in
                                    semanticChip(type)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    // Visibility picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Visibility")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        HStack(spacing: 8) {
                            ForEach(ChurchNoteVisibility.allCases, id: \.self) { v in
                                visibilityChip(v)
                            }
                        }
                    }

                    // Pin picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pin")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ChurchNotePinnedState.allCases, id: \.self) { state in
                                    pinChip(state)
                                }
                            }
                        }
                    }

                    // Checklist items (if applicable)
                    if block.type == .checklist {
                        checklistEditor
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(block.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(block)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func semanticChip(_ type: ChurchNoteSemanticType) -> some View {
        let selected = block.semanticType == type
        return Button {
            block = ChurchNoteBlockV2(
                id: block.id, sortOrder: block.sortOrder, type: block.type,
                semanticType: type, visibility: block.visibility, pinnedState: block.pinnedState,
                text: block.text, richSpans: block.richSpans, versePayload: block.versePayload,
                calloutPayload: block.calloutPayload, sectionPayload: block.sectionPayload,
                checklistPayload: block.checklistPayload,
                createdAt: block.createdAt, updatedAt: Date()
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.caption2)
                Text(type.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? type.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
            .foregroundStyle(selected ? type.accentColor : Color.primary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(selected ? type.accentColor.opacity(0.4) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func visibilityChip(_ visibility: ChurchNoteVisibility) -> some View {
        let selected = block.visibility == visibility
        return Button {
            block = ChurchNoteBlockV2(
                id: block.id, sortOrder: block.sortOrder, type: block.type,
                semanticType: block.semanticType, visibility: visibility, pinnedState: block.pinnedState,
                text: block.text, richSpans: block.richSpans, versePayload: block.versePayload,
                calloutPayload: block.calloutPayload, sectionPayload: block.sectionPayload,
                checklistPayload: block.checklistPayload,
                createdAt: block.createdAt, updatedAt: Date()
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: visibility.icon).font(.caption2)
                Text(visibility.displayName).font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color.primary : Color(.tertiarySystemFill))
            .foregroundStyle(selected ? Color(.systemBackground) : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(visibility.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func pinChip(_ state: ChurchNotePinnedState) -> some View {
        let selected = block.pinnedState == state
        return Button {
            block = ChurchNoteBlockV2(
                id: block.id, sortOrder: block.sortOrder, type: block.type,
                semanticType: block.semanticType, visibility: block.visibility, pinnedState: state,
                text: block.text, richSpans: block.richSpans, versePayload: block.versePayload,
                calloutPayload: block.calloutPayload, sectionPayload: block.sectionPayload,
                checklistPayload: block.checklistPayload,
                createdAt: block.createdAt, updatedAt: Date()
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: state.icon).font(.caption2)
                Text(state.displayName).font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color(.secondarySystemGroupedBackground) : Color(.tertiarySystemFill))
            .foregroundStyle(.primary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.primary.opacity(0.3) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var checklistEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Items")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            let items = block.checklistPayload?.items ?? []
            ForEach(items.indices, id: \.self) { idx in
                HStack(spacing: 8) {
                    Image(systemName: items[idx].completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(items[idx].completed ? .primary : Color(.tertiaryLabel))
                        .onTapGesture {
                            toggleChecklistItem(at: idx)
                        }
                        .accessibilityHidden(true)
                    Text(items[idx].text)
                        .font(.subheadline)
                }
            }

            Button {
                addChecklistItem()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle").font(.subheadline)
                    Text("Add Item").font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleChecklistItem(at index: Int) {
        guard var payload = block.checklistPayload else { return }
        payload.items[index].completed.toggle()
        block = ChurchNoteBlockV2(
            id: block.id, sortOrder: block.sortOrder, type: block.type,
            semanticType: block.semanticType, visibility: block.visibility, pinnedState: block.pinnedState,
            text: block.text, richSpans: block.richSpans, versePayload: block.versePayload,
            calloutPayload: block.calloutPayload, sectionPayload: block.sectionPayload,
            checklistPayload: payload, createdAt: block.createdAt, updatedAt: Date()
        )
    }

    private func addChecklistItem() {
        var payload = block.checklistPayload ?? ChecklistPayload(
            category: .actionSteps,
            items: []
        )
        payload.items.append(CNChecklistItem(text: ""))
        block = ChurchNoteBlockV2(
            id: block.id, sortOrder: block.sortOrder, type: block.type,
            semanticType: block.semanticType, visibility: block.visibility, pinnedState: block.pinnedState,
            text: block.text, richSpans: block.richSpans, versePayload: block.versePayload,
            calloutPayload: block.calloutPayload, sectionPayload: block.sectionPayload,
            checklistPayload: payload, createdAt: block.createdAt, updatedAt: Date()
        )
    }
}

// MARK: - Berean Church Note Insight Card

private struct CNBereanThemeChip: View {
    let name: String
    private let chipColor = Color(red: 0.18, green: 0.44, blue: 0.80)
    var body: some View {
        Text(name)
            .font(AMENFont.regular(11))
            .foregroundStyle(chipColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(chipColor.opacity(0.10)))
    }
}

private struct BereanChurchNoteInsightCard: View {
    let insight: ScripturePassagePayload?
    let isLoading: Bool
    let onStudyDeeper: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.44, blue: 0.80))
                Text("Berean Insight")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(Color(red: 0.18, green: 0.44, blue: 0.80))
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(Color(red: 0.18, green: 0.44, blue: 0.80))
                }
            }

            if let insight {
                if !insight.summary.isEmpty {
                    Text(insight.summary)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                }

                if !insight.themes.isEmpty {
                    let names: [String] = Array(insight.themes.prefix(3).map(\.name))
                    HStack(spacing: 6) {
                        ForEach(names, id: \.self) { name in
                            CNBereanThemeChip(name: name)
                        }
                    }
                }

                if let christConnection = insight.christConnection,
                   !christConnection.connectionStatement.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "cross.fill")
                            .font(.systemScaled(10))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        Text(christConnection.connectionStatement)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                }
            } else if !isLoading {
                Text("Add a verse to see Berean's scripture insight for this note.")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.18, green: 0.44, blue: 0.80).opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            Color(red: 0.18, green: 0.44, blue: 0.80).opacity(0.18),
                            lineWidth: 0.5
                        )
                )
        )
    }
}
