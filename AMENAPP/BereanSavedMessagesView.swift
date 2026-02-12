//
//  BereanSavedMessagesView.swift
//  AMENAPP
//
//  Created by Assistant on 2/3/26.
//

import SwiftUI

// MARK: - Saved Messages View

struct BereanSavedMessagesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dataManager = BereanDataManager.shared
    
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var showingEditSheet = false
    @State private var messageToEdit: SavedBereanMessage?
    
    var filteredMessages: [SavedBereanMessage] {
        var messages = dataManager.savedMessages
        
        // Filter by search
        if !searchText.isEmpty {
            messages = messages.filter { savedMessage in
                savedMessage.message.content.localizedCaseInsensitiveContains(searchText) ||
                savedMessage.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        // Filter by tag
        if let tag = selectedTag {
            messages = messages.filter { $0.tags.contains(tag) }
        }
        
        return messages
    }
    
    var allTags: [String] {
        Array(Set(dataManager.savedMessages.flatMap { $0.tags })).sorted()
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.05)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    searchBar
                    
                    // Tags filter
                    if !allTags.isEmpty {
                        tagsScrollView
                    }
                    
                    if filteredMessages.isEmpty {
                        emptyStateView
                    } else {
                        savedMessagesList
                    }
                }
            }
            .navigationTitle("Saved Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .sheet(item: $messageToEdit) { savedMessage in
                EditSavedMessageSheet(
                    savedMessage: savedMessage,
                    onSave: { tags, note in
                        dataManager.updateSavedMessage(savedMessage, tags: tags, note: note)
                        messageToEdit = nil
                    },
                    onDelete: {
                        dataManager.unsaveMessage(savedMessage)
                        messageToEdit = nil
                    }
                )
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            
            TextField("Search saved messages...", text: $searchText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)
                .tint(Color(red: 1.0, green: 0.7, blue: 0.5))
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var tagsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All tag
                TagFilterChip(
                    title: "All",
                    isSelected: selectedTag == nil
                ) {
                    withAnimation(.smooth(duration: 0.2)) {
                        selectedTag = nil
                    }
                }
                
                ForEach(allTags, id: \.self) { tag in
                    TagFilterChip(
                        title: tag,
                        isSelected: selectedTag == tag
                    ) {
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedTag = selectedTag == tag ? nil : tag
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }
    
    private var savedMessagesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredMessages) { savedMessage in
                    SavedMessageCard(savedMessage: savedMessage) {
                        messageToEdit = savedMessage
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: searchText.isEmpty ? "bookmark" : "magnifyingglass")
                .font(.system(size: 50))
                .foregroundStyle(.white.opacity(0.3))
            
            Text(searchText.isEmpty ? "No Saved Messages" : "No Results")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.white)
            
            Text(searchText.isEmpty ?
                 "Messages you save will appear here" :
                 "Try adjusting your search")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tag Filter Chip

struct TagFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? Color(red: 1.0, green: 0.7, blue: 0.5) : Color.white.opacity(0.08))
                        .overlay(
                            Capsule()
                                .stroke(
                                    isSelected ? Color.clear : Color.white.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Saved Message Card

struct SavedMessageCard: View {
    let savedMessage: SavedBereanMessage
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.5))
                    
                    Text("Berean AI")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text(savedMessage.savedDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                // Content
                Text(savedMessage.message.content)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(4)
                    .lineSpacing(4)
                
                // Note (if any)
                if let note = savedMessage.note, !note.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                        
                        Text(note)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .lineLimit(2)
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.6))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 1.0, green: 0.85, blue: 0.6).opacity(0.1))
                    )
                }
                
                // Tags & Verse References
                HStack(spacing: 8) {
                    // Tags
                    if !savedMessage.tags.isEmpty {
                        ForEach(savedMessage.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.custom("OpenSans-SemiBold", size: 10))
                                .foregroundStyle(Color(red: 0.5, green: 0.6, blue: 0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color(red: 0.5, green: 0.6, blue: 0.9).opacity(0.15))
                                )
                        }
                    }
                    
                    Spacer()
                    
                    // Verse references count
                    if !savedMessage.message.verseReferences.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 10))
                            
                            Text("\(savedMessage.message.verseReferences.count)")
                                .font(.custom("OpenSans-SemiBold", size: 11))
                        }
                        .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Edit Saved Message Sheet

struct EditSavedMessageSheet: View {
    let savedMessage: SavedBereanMessage
    let onSave: ([String], String?) -> Void
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String]
    @State private var note: String
    @State private var newTag = ""
    @State private var showDeleteAlert = false
    
    init(savedMessage: SavedBereanMessage, onSave: @escaping ([String], String?) -> Void, onDelete: @escaping () -> Void) {
        self.savedMessage = savedMessage
        self.onSave = onSave
        self.onDelete = onDelete
        _tags = State(initialValue: savedMessage.tags)
        _note = State(initialValue: savedMessage.note ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.05)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Original message
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Saved Message")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white)
                            
                            Text(savedMessage.message.content)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineSpacing(4)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.05))
                                )
                        }
                        
                        // Personal note
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Personal Note")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white)
                            
                            TextEditor(text: $note)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                                .frame(height: 100)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                        }
                        
                        // Tags
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Tags")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white)
                            
                            // Current tags
                            if !tags.isEmpty {
                                FlowLayout(spacing: 8) {
                                    ForEach(tags, id: \.self) { tag in
                                        HStack(spacing: 6) {
                                            Text(tag)
                                                .font(.custom("OpenSans-SemiBold", size: 13))
                                            
                                            Button {
                                                tags.removeAll { $0 == tag }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 14))
                                            }
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(Color(red: 0.5, green: 0.6, blue: 0.9).opacity(0.3))
                                        )
                                    }
                                }
                            }
                            
                            // Add tag field
                            HStack(spacing: 12) {
                                TextField("Add tag...", text: $newTag)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.white.opacity(0.08))
                                    )
                                    .onSubmit {
                                        addTag()
                                    }
                                
                                Button {
                                    addTag()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.5))
                                }
                                .disabled(newTag.isEmpty)
                            }
                        }
                        
                        // Delete button
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 14))
                                
                                Text("Delete Saved Message")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                            }
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.1))
                            )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Saved Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(tags, note.isEmpty ? nil : note)
                        dismiss()
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.5))
                    .fontWeight(.semibold)
                }
            }
            .alert("Delete Saved Message?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
    
    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        
        tags.append(trimmed)
        newTag = ""
    }
}


#Preview {
    BereanSavedMessagesView()
}
