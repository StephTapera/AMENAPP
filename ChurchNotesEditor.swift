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
        }
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
                        // Title field
                        titleField
                        
                        // Sermon context section
                        sermonContextSection
                        
                        // Scripture section with detection
                        scriptureSection
                        
                        // Main content editor
                        contentEditorSection
                        
                        // UX-1: Quick insert toolbar
                        if showingToolbar {
                            quickInsertToolbar
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
                        .tint(.black)
                } else {
                    Text("Save")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(canSave ? .black : .black.opacity(0.3))
                }
            }
            .disabled(!canSave || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(red: 0.96, green: 0.96, blue: 0.96))
    }
    
    // MARK: - Title Field
    
    private var titleField: some View {
        TextField("Note Title", text: $title)
            .font(.system(size: 32, weight: .medium))
            .foregroundStyle(.black)
            .tint(.black)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .onChange(of: title) { _, _ in
                trackUnsavedChanges()
            }
    }
    
    // MARK: - Sermon Context Section
    
    private var sermonContextSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sermon Context")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1)
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                EditorMinimalTextField(icon: "mic", placeholder: "Sermon title", text: $sermonTitle)
                    .onChange(of: sermonTitle) { _, _ in trackUnsavedChanges() }
                
                EditorMinimalTextField(icon: "building.2", placeholder: "Church name", text: $churchName)
                    .onChange(of: churchName) { _, _ in trackUnsavedChanges() }
                
                EditorMinimalTextField(icon: "person", placeholder: "Pastor", text: $pastor)
                    .onChange(of: pastor) { _, _ in trackUnsavedChanges() }
                
                // Date picker
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 16))
                        .foregroundStyle(.black.opacity(0.4))
                        .frame(width: 24)
                    
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
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
    }
    
    // MARK: - Scripture Section with Detection
    
    private var scriptureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scripture Reference")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1)
                .padding(.horizontal, 20)
            
            EditorMinimalTextField(icon: "book", placeholder: "e.g., John 3:16", text: $scripture)
                .onChange(of: scripture) { _, _ in trackUnsavedChanges() }
            
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
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "book.fill")
                                            .font(.system(size: 10))
                                        Text(ref)
                                            .font(.system(size: 13))
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
    
    // MARK: - Content Editor Section
    
    private var contentEditorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Notes")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1)
                
                Spacer()
                
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
            }
            .padding(.horizontal, 20)
            
            // Text editor with focused state
            TextEditor(text: $content)
                .font(.system(size: 16))
                .foregroundStyle(.black)
                .frame(minHeight: 300)
                .padding(16)
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isContentFocused ? Color.black.opacity(0.2) : Color.black.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .focused($isContentFocused)
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
                }
                .padding(.horizontal, 20)
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    // MARK: - Tags Section
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags (Optional)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1)
                .padding(.horizontal, 20)
            
            // Tag input and display would go here
            // Simplified for now
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
            print("Auto-save failed: \(error)")
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
                scriptureReferences: detectedScriptures
            )
            
            try await notesService.createNote(newNote)
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
