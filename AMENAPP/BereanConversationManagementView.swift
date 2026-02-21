//
//  BereanConversationManagementView.swift
//  AMENAPP
//
//  Created by Assistant on 2/3/26.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Enhanced Conversation History View

struct BereanConversationManagementView: View {
    @Binding var conversations: [SavedConversation]
    @Binding var isLoading: Bool  // ✅ P1-2: Loading state binding
    let onSelect: (SavedConversation) -> Void
    let onDelete: (SavedConversation) -> Void
    let onUpdate: (SavedConversation, String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingExportSheet = false
    @State private var conversationToExport: SavedConversation?
    @State private var conversationToEdit: SavedConversation?
    @State private var showingDeleteAlert = false
    @State private var conversationToDelete: SavedConversation?
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false
    
    var filteredConversations: [SavedConversation] {
        if searchText.isEmpty {
            return conversations
        }
        
        return conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(searchText) ||
            conversation.messages.contains { message in
                message.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.05)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    searchBar
                    
                    if filteredConversations.isEmpty {
                        emptyStateView
                    } else {
                        conversationsList
                    }
                }
                
                // ✅ P1-2: Loading overlay
                if isLoading {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Loading conversation...")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(white: 0.1))
                            .shadow(radius: 20)
                    )
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .sheet(item: $conversationToEdit) { conversation in
                EditConversationTitleSheet(
                    conversation: conversation,
                    onSave: { newTitle in
                        onUpdate(conversation, newTitle)
                        conversationToEdit = nil
                    }
                )
            }
            .sheet(isPresented: $showingExportSheet) {
                if let conversation = conversationToExport {
                    ExportConversationSheet(
                        conversation: conversation,
                        onExport: { format in
                            exportConversation(conversation, format: format)
                        }
                    )
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Delete Conversation?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    conversationToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let conversation = conversationToDelete {
                        onDelete(conversation)
                        conversationToDelete = nil
                    }
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            
            TextField("Search conversations...", text: $searchText)
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
    
    private var conversationsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredConversations) { conversation in
                    ConversationManagementCard(
                        conversation: conversation,
                        onSelect: {
                            onSelect(conversation)
                            dismiss()
                        },
                        onEdit: {
                            conversationToEdit = conversation
                        },
                        onExport: {
                            conversationToExport = conversation
                            showingExportSheet = true
                        },
                        onDelete: {
                            conversationToDelete = conversation
                            showingDeleteAlert = true
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: searchText.isEmpty ? "clock" : "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.3))
            
            Text(searchText.isEmpty ? "No Saved Conversations" : "No Results")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.white)
            
            Text(searchText.isEmpty ?
                 "Your conversation history will appear here" :
                 "Try adjusting your search")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func exportConversation(_ conversation: SavedConversation, format: ExportFormat) {
        let dataManager = BereanDataManager.shared
        
        switch format {
        case .text:
            let text = dataManager.exportConversationAsText(conversation)
            let fileName = "\(conversation.title.prefix(30))_\(Date().formatted(date: .numeric, time: .omitted)).txt"
            saveToFile(text: text, fileName: fileName)
            
        case .pdf:
            if let pdfData = dataManager.exportConversationAsPDF(conversation) {
                let fileName = "\(conversation.title.prefix(30))_\(Date().formatted(date: .numeric, time: .omitted)).pdf"
                saveToFile(data: pdfData, fileName: fileName)
            }
        }
        
        showingExportSheet = false
    }
    
    private func saveToFile(text: String, fileName: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            exportedFileURL = fileURL
            showingShareSheet = true
            print("✅ Exported to: \(fileURL.path)")
        } catch {
            print("❌ Failed to save file: \(error)")
        }
    }
    
    private func saveToFile(data: Data, fileName: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            exportedFileURL = fileURL
            showingShareSheet = true
            print("✅ Exported to: \(fileURL.path)")
        } catch {
            print("❌ Failed to save file: \(error)")
        }
    }
}

// MARK: - Conversation Management Card

struct ConversationManagementCard: View {
    let conversation: SavedConversation
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    
    @State private var showingActions = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Text(conversation.title)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 12) {
                        Label(conversation.translation, systemImage: "book.fill")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                        
                        Text(conversation.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                        
                        Text("\(conversation.messages.count) messages")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                
                Spacer()
                
                // Actions button
                Button {
                    showingActions = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog("Conversation Actions", isPresented: $showingActions) {
            Button("Load Conversation") {
                onSelect()
            }
            
            Button("Edit Title") {
                onEdit()
            }
            
            Button("Export") {
                onExport()
            }
            
            Button("Delete", role: .destructive) {
                onDelete()
            }
            
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - Edit Conversation Title Sheet

struct EditConversationTitleSheet: View {
    let conversation: SavedConversation
    let onSave: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @FocusState private var isFocused: Bool
    
    init(conversation: SavedConversation, onSave: @escaping (String) -> Void) {
        self.conversation = conversation
        self.onSave = onSave
        _title = State(initialValue: conversation.title)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.05)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Conversation Title")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                        
                        TextField("Enter title...", text: $title, axis: .vertical)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .focused($isFocused)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                    }
                    
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Edit Title")
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
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onSave(trimmed)
                            dismiss()
                        }
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.5))
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable {
    case text = "Plain Text (.txt)"
    case pdf = "PDF Document (.pdf)"
    
    var icon: String {
        switch self {
        case .text: return "doc.text.fill"
        case .pdf: return "doc.fill"
        }
    }
}

// MARK: - Export Conversation Sheet

struct ExportConversationSheet: View {
    let conversation: SavedConversation
    let onExport: (ExportFormat) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .text
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.05)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Conversation Preview")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(conversation.title)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.white)
                            
                            HStack(spacing: 12) {
                                Label(conversation.translation, systemImage: "book.fill")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                                
                                Text("•")
                                    .foregroundStyle(.white.opacity(0.3))
                                
                                Text("\(conversation.messages.count) messages")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                    
                    // Format selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export Format")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                        
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Button {
                                selectedFormat = format
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: format.icon)
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.5))
                                        .frame(width: 32)
                                    
                                    Text(format.rawValue)
                                        .font(.custom("OpenSans-SemiBold", size: 15))
                                        .foregroundStyle(.white)
                                    
                                    Spacer()
                                    
                                    if selectedFormat == format {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.7))
                                    } else {
                                        Circle()
                                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                            .frame(width: 20, height: 20)
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedFormat == format ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    selectedFormat == format ?
                                                        Color(red: 1.0, green: 0.7, blue: 0.5).opacity(0.5) :
                                                        Color.white.opacity(0.1),
                                                    lineWidth: 1
                                                )
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    Spacer()
                    
                    // Export button
                    Button {
                        onExport(selectedFormat)
                        
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.system(size: 16, weight: .semibold))
                            
                            Text("Export Conversation")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.7, blue: 0.5),
                                            Color(red: 1.0, green: 0.6, blue: 0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.4).opacity(0.3), radius: 15, y: 5)
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle("Export Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

// Note: ShareSheet is already defined in ShareSheet.swift

#Preview {
    BereanConversationManagementView(
        conversations: .constant([]),
        isLoading: .constant(false),
        onSelect: { _ in },
        onDelete: { _ in },
        onUpdate: { _, _ in }
    )
}
