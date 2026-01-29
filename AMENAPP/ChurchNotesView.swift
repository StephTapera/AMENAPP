//
//  ChurchNotesView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Smart church notes with Firebase backend integration
//

import SwiftUI
import Combine
import FirebaseAuth

struct ChurchNotesView: View {
    @StateObject private var notesService = ChurchNotesService()
    @State private var showingNewNote = false
    @State private var searchText = ""
    @State private var selectedFilter: FilterOption = .all
    @State private var selectedNote: ChurchNote?
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case favorites = "Favorites"
        case recent = "Recent"
    }
    
    var filteredNotes: [ChurchNote] {
        var filtered = notesService.notes
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .favorites:
            filtered = filtered.filter { $0.isFavorite }
        case .recent:
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            filtered = filtered.filter { $0.date >= sevenDaysAgo }
        }
        
        // Apply search
        if !searchText.isEmpty {
            filtered = notesService.searchNotes(query: searchText)
        }
        
        return filtered
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search notes, sermons, scriptures...", text: $searchText)
                        .font(.custom("OpenSans-Regular", size: 16))
                    
                    if !searchText.isEmpty {
                        Button {
                            withAnimation {
                                searchText = ""
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                .padding(.horizontal)
                .padding(.vertical, 12)
                
                // Filter tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FilterOption.allCases, id: \.self) { filter in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFilter = filter
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if filter == .favorites {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 12))
                                    }
                                    Text(filter.rawValue)
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                }
                                .foregroundStyle(selectedFilter == filter ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedFilter == filter ? Color.purple : Color(.systemGray6))
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 12)
                
                if notesService.isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                } else if filteredNotes.isEmpty {
                    // Empty state
                    Spacer()
                    
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "note.text")
                                .font(.system(size: 50))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        VStack(spacing: 8) {
                            Text(searchText.isEmpty ? "No Notes Yet" : "No Results")
                                .font(.custom("OpenSans-Bold", size: 24))
                            
                            Text(searchText.isEmpty ? "Start taking notes during your next sermon" : "Try a different search")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        if searchText.isEmpty {
                            Button {
                                showingNewNote = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create Your First Note")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.purple, .blue],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .shadow(color: .purple.opacity(0.3), radius: 12, y: 6)
                                )
                            }
                        }
                    }
                    .padding()
                    
                    Spacer()
                } else {
                    // Notes list
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredNotes) { note in
                                ChurchNoteCard(note: note, notesService: notesService)
                                    .onTapGesture {
                                        selectedNote = note
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Church Notes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewNote = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            }
            .sheet(isPresented: $showingNewNote) {
                NewChurchNoteView(notesService: notesService)
            }
            .sheet(item: $selectedNote) { note in
                ChurchNoteDetailView(note: note, notesService: notesService)
            }
            .task {
                await notesService.fetchNotes()
            }
        }
    }
}

// MARK: - Church Note Card

struct ChurchNoteCard: View {
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.title)
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                    
                    if let sermonTitle = note.sermonTitle {
                        Text(sermonTitle)
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        if let churchName = note.churchName {
                            Label(churchName, systemImage: "building.2")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        if let pastor = note.pastor {
                            Label(pastor, systemImage: "person")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Button {
                    Task {
                        try? await notesService.toggleFavorite(note)
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                    }
                } label: {
                    Image(systemName: note.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 24))
                        .foregroundStyle(note.isFavorite ? .yellow : .secondary)
                }
            }
            
            if !note.content.isEmpty {
                Text(note.content)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            
            if let scripture = note.scripture, !scripture.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                    Text(scripture)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.purple)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.purple.opacity(0.1))
                )
            }
            
            HStack {
                Text(note.date, style: .date)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Tags
                if !note.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(note.tags.prefix(3), id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.custom("OpenSans-SemiBold", size: 11))
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue.opacity(0.1))
                                    )
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .contextMenu {
            Button {
                Task {
                    try? await notesService.toggleFavorite(note)
                }
            } label: {
                Label(note.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: note.isFavorite ? "star.slash" : "star")
            }
            
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await notesService.deleteNote(note)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - New Note View

struct NewChurchNoteView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var notesService: ChurchNotesService
    
    @State private var title = ""
    @State private var sermonTitle = ""
    @State private var churchName = ""
    @State private var pastor = ""
    @State private var selectedDate = Date()
    @State private var content = ""
    @State private var scripture = ""
    @State private var keyPoints: [String] = []
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var isSaving = false
    
    var canSave: Bool {
        !title.isEmpty && !content.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Note Title", systemImage: "pencil")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.secondary)
                        
                        TextField("My Sunday Sermon Notes", text: $title)
                            .font(.custom("OpenSans-SemiBold", size: 18))
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                    }
                    
                    // Sermon Details
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Sermon Details", systemImage: "info.circle")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.secondary)
                        
                        TextField("Sermon Title (Optional)", text: $sermonTitle)
                            .font(.custom("OpenSans-Regular", size: 16))
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                        
                        HStack(spacing: 12) {
                            TextField("Church Name", text: $churchName)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                            
                            TextField("Pastor/Speaker", text: $pastor)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                        
                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                    }
                    
                    // Scripture Reference
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Scripture Reference", systemImage: "book.fill")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.purple)
                        
                        TextField("e.g., John 3:16, Romans 8:28", text: $scripture)
                            .font(.custom("OpenSans-Regular", size: 16))
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.purple.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                    
                    // Content
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notes", systemImage: "note.text")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: $content)
                            .font(.custom("OpenSans-Regular", size: 16))
                            .frame(minHeight: 200)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                    }
                    
                    // Tags
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Tags", systemImage: "tag")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.secondary)
                        
                        if !tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(tags, id: \.self) { tag in
                                        HStack(spacing: 6) {
                                            Text("#\(tag)")
                                                .font(.custom("OpenSans-SemiBold", size: 13))
                                            
                                            Button {
                                                tags.removeAll { $0 == tag }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 14))
                                            }
                                        }
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                    }
                                }
                            }
                        }
                        
                        HStack {
                            TextField("Add tag", text: $newTag)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                            
                            Button {
                                if !newTag.isEmpty && !tags.contains(newTag) {
                                    tags.append(newTag)
                                    newTag = ""
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.blue)
                            }
                            .disabled(newTag.isEmpty)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveNote()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
    }
    
    private func saveNote() {
        guard let userId = FirebaseManager.shared.currentUser?.uid else { return }
        
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
                    dismiss()
                }
            } catch {
                print("❌ Failed to save note: \(error)")
                isSaving = false
            }
        }
    }
}

// MARK: - Note Detail View

struct ChurchNoteDetailView: View {
    @Environment(\.dismiss) var dismiss
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(note.title)
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Button {
                                Task {
                                    try? await notesService.toggleFavorite(note)
                                }
                            } label: {
                                Image(systemName: note.isFavorite ? "star.fill" : "star")
                                    .font(.system(size: 28))
                                    .foregroundStyle(note.isFavorite ? .yellow : .secondary)
                            }
                        }
                        
                        if let sermonTitle = note.sermonTitle {
                            Text(sermonTitle)
                                .font(.custom("OpenSans-SemiBold", size: 18))
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack(spacing: 16) {
                            if let churchName = note.churchName {
                                Label(churchName, systemImage: "building.2")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let pastor = note.pastor {
                                Label(pastor, systemImage: "person")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Text(note.date, style: .date)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    // Scripture
                    if let scripture = note.scripture {
                        HStack(spacing: 12) {
                            Image(systemName: "book.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.purple)
                            
                            Text(scripture)
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.purple)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple.opacity(0.1))
                        )
                    }
                    
                    // Content
                    Text(note.content)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.primary)
                        .lineSpacing(6)
                    
                    // Tags
                    if !note.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(note.tags, id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.custom("OpenSans-SemiBold", size: 13))
                                            .foregroundStyle(.blue)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(Color.blue.opacity(0.1))
                                            )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Note Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button {
                            // Share functionality
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 24))
                    }
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await notesService.deleteNote(note)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

#Preview {
    ChurchNotesView()
}
