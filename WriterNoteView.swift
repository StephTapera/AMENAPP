//
//  WriterNoteView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Beautiful writer-focused note creation UI
//

import SwiftUI
import FirebaseAuth

struct WriterNoteView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var notesService: ChurchNotesService
    
    @State private var title = ""
    @State private var sermonTitle = ""
    @State private var churchName = ""
    @State private var pastor = ""
    @State private var selectedDate = Date()
    @State private var content = ""
    @State private var scripture = ""
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var wordCount = 0
    @State private var characterCount = 0
    @State private var showMetadata = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case title, sermonTitle, churchName, pastor, scripture, content, tag
    }
    
    var canSave: Bool {
        !title.isEmpty && !content.isEmpty
    }
    
    var body: some View {
        ZStack {
            // Clean, minimal background
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Glass Header
                headerView
                
                // Writer Area
                ScrollView {
                    VStack(spacing: 0) {
                        // Title Input
                        titleSection
                        
                        // Metadata Toggle
                        metadataToggle
                        
                        // Collapsible Metadata
                        if showMetadata {
                            metadataSection
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Main Content Editor
                        contentEditor
                        
                        // Writing Stats
                        writingStats
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 16) {
            // Cancel Button (Liquid Glass)
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.8),
                                                Color.white.opacity(0.6)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        Color.black.opacity(0.1),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            }
            
            Spacer()
            
            // Save Button (Liquid Glass - Active)
            Button {
                saveNote()
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                        Text("Save")
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: canSave ? [
                                            Color.blue,
                                            Color.blue.opacity(0.85)
                                        ] : [
                                            Color.gray.opacity(0.3),
                                            Color.gray.opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    Color.white.opacity(canSave ? 0.3 : 0.1),
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(color: canSave ? Color.blue.opacity(0.3) : Color.black.opacity(0.05), radius: 12, y: 6)
            }
            .disabled(!canSave || isSaving)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color.white.opacity(0.85)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
        )
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Encouraging prompt
            if title.isEmpty && focusedField != .title {
                Text("What's your note about?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
            }
            
            // Title input
            TextField("", text: $title, prompt: Text("Note Title").foregroundStyle(Color.black.opacity(0.25)))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Color.black)
                .tint(.blue)
                .focused($focusedField, equals: .title)
                .padding(.horizontal, 20)
                .padding(.vertical, title.isEmpty ? 8 : 24)
                .animation(.easeInOut(duration: 0.2), value: title.isEmpty)
        }
    }
    
    // MARK: - Metadata Toggle
    
    private var metadataToggle: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showMetadata.toggle()
            }
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: showMetadata ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(showMetadata ? 0 : 0))
                
                Text("Sermon Details")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.8))
                
                Text("(Optional)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.4))
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(white: 0.97))
        }
    }
    
    // MARK: - Metadata Section
    
    private var metadataSection: some View {
        VStack(spacing: 16) {
            // Sermon Title
            CleanTextField(
                icon: "mic.fill",
                placeholder: "Sermon title",
                text: $sermonTitle,
                focusedField: $focusedField,
                field: .sermonTitle
            )
            
            // Church and Pastor
            HStack(spacing: 12) {
                CleanTextField(
                    icon: "building.2.fill",
                    placeholder: "Church",
                    text: $churchName,
                    focusedField: $focusedField,
                    field: .churchName
                )
                
                CleanTextField(
                    icon: "person.fill",
                    placeholder: "Pastor",
                    text: $pastor,
                    focusedField: $focusedField,
                    field: .pastor
                )
            }
            
            // Scripture
            CleanTextField(
                icon: "book.fill",
                placeholder: "Scripture (e.g., John 3:16)",
                text: $scripture,
                focusedField: $focusedField,
                field: .scripture
            )
            
            // Date
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .frame(width: 24)
                
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(.blue)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(white: 0.97))
    }
    
    // MARK: - Content Editor
    
    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Encouraging header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Reflection")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.8))
                    
                    Text("Write freely about what moved you")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.5))
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            
            // Text editor
            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Start writing...")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.25))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            PromptText("💡 What stood out to you?")
                            PromptText("🙏 How did this message speak to you?")
                            PromptText("✨ What will you apply this week?")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                
                TextEditor(text: $content)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.black)
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 400)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .focused($focusedField, equals: .content)
                    .onChange(of: content) { oldValue, newValue in
                        updateStats()
                    }
            }
        }
    }
    
    // MARK: - Writing Stats
    
    private var writingStats: some View {
        HStack(spacing: 24) {
            if wordCount > 0 {
                StatPill(icon: "textformat.size", value: "\(wordCount)", label: "words")
                StatPill(icon: "character", value: "\(characterCount)", label: "characters")
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(white: 0.98))
    }
    
    // MARK: - Helper Functions
    
    private func updateStats() {
        wordCount = content.split(separator: " ").count
        characterCount = content.count
    }
    
    private func saveNote() {
        guard let userId = FirebaseManager.shared.currentUser?.uid else {
            errorMessage = "You must be signed in to create notes."
            showErrorAlert = true
            return
        }
        
        guard canSave else { return }
        
        isSaving = true
        
        let note = ChurchNote(
            userId: userId,
            title: title,
            sermonTitle: sermonTitle.isEmpty ? nil : sermonTitle,
            churchName: churchName.isEmpty ? nil : churchName,
            pastor: pastor.isEmpty ? nil : pastor,
            date: selectedDate,
            content: content,
            scripture: scripture.isEmpty ? nil : scripture,
            keyPoints: [],
            tags: tags
        )
        
        Task {
            do {
                try await notesService.createNote(note)
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save note. Please try again."
                    showErrorAlert = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Clean Text Field

struct CleanTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var focusedField: FocusState<WriterNoteView.Field?>.Binding
    let field: WriterNoteView.Field
    
    private var isFocused: Bool {
        focusedField.wrappedValue == field
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(isFocused ? 0.7 : 0.4))
                .frame(width: 24)
            
            TextField(placeholder, text: $text)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.black)
                .tint(.blue)
                .focused(focusedField, equals: field)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(isFocused ? 0.08 : 0.05), radius: isFocused ? 12 : 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? Color.blue.opacity(0.3) : Color.black.opacity(0.06),
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}

// MARK: - Prompt Text

struct PromptText: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Color.black.opacity(0.35))
            .padding(.leading, 4)
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(value)
                .font(.system(size: 14, weight: .bold))
            Text(label)
                .font(.system(size: 13, weight: .regular))
        }
        .foregroundStyle(Color.black.opacity(0.6))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    WriterNoteView(notesService: ChurchNotesService())
}
