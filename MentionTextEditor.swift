//
//  MentionTextEditor.swift
//  AMENAPP
//
//  Created by AI Assistant on 2/12/26.
//

import SwiftUI
import FirebaseAuth
import Combine

// MARK: - Mention Text Editor

struct MentionTextEditor: View {
    @Binding var text: String
    @Binding var mentions: [Mention]
    let placeholder: String
    let maxHeight: CGFloat
    
    @StateObject private var mentionService = MentionService()
    @State private var showingSuggestions = false
    @State private var currentMentionSearch = ""
    @State private var cursorPosition: Int = 0
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Text Editor
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.gray.opacity(0.5))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                
                TextEditor(text: $text)
                    .focused($isFocused)
                    .frame(maxHeight: maxHeight)
                    .scrollContentBackground(.hidden)
                    .onChange(of: text) { oldValue, newValue in
                        handleTextChange(oldValue: oldValue, newValue: newValue)
                    }
            }
            
            // Mention Suggestions
            if showingSuggestions && !mentionService.searchResults.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(mentionService.searchResults) { user in
                            MentionSuggestionRow(user: user) {
                                insertMention(user)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Text Change Handler
    
    private func handleTextChange(oldValue: String, newValue: String) {
        // Detect @ symbol
        if let lastChar = newValue.last, lastChar == "@" {
            showingSuggestions = true
            currentMentionSearch = ""
            mentionService.searchUsers(query: "")
            return
        }
        
        // Check if we're in a mention
        if showingSuggestions {
            if let atIndex = newValue.lastIndex(of: "@") {
                let searchStart = newValue.index(after: atIndex)
                if searchStart < newValue.endIndex {
                    currentMentionSearch = String(newValue[searchStart...])
                    
                    // Check if space was typed (end mention)
                    if currentMentionSearch.contains(" ") || currentMentionSearch.contains("\n") {
                        showingSuggestions = false
                        currentMentionSearch = ""
                    } else {
                        mentionService.searchUsers(query: currentMentionSearch)
                    }
                } else {
                    mentionService.searchUsers(query: "")
                }
            } else {
                showingSuggestions = false
                currentMentionSearch = ""
            }
        }
    }
    
    // MARK: - Insert Mention
    
    private func insertMention(_ user: MentionUser) {
        // Find the @ symbol position
        guard let atIndex = text.lastIndex(of: "@") else { return }
        
        let beforeAt = String(text[..<atIndex])
        let mentionText = "@\(user.username)"
        let afterMention = " "
        
        let newText = beforeAt + mentionText + afterMention
        
        // Calculate range for mention
        let startLocation = (beforeAt as NSString).length
        let mentionLength = (mentionText as NSString).length
        let range = NSRange(location: startLocation, length: mentionLength)
        
        // Create mention object
        let mention = Mention(
            userId: user.userId,
            username: user.username,
            displayName: user.displayName,
            range: range
        )
        
        mentions.append(mention)
        text = newText
        showingSuggestions = false
        currentMentionSearch = ""
    }
}

// MARK: - Mention Suggestion Row

struct MentionSuggestionRow: View {
    let user: MentionUser
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile Image
                if let profileImageUrl = user.profileImageUrl, let url = URL(string: profileImageUrl) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(user.displayName.prefix(1))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                    
                    Text("@\(user.username)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.gray)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mention Service

@MainActor
class MentionService: ObservableObject {
    @Published var searchResults: [MentionUser] = []
    
    private var searchTask: Task<Void, Never>?
    
    func searchUsers(query: String) {
        searchTask?.cancel()
        
        searchTask = Task {
            do {
                let users = try await UserSearchService.shared.searchUsers(query: query)
                
                guard !Task.isCancelled else { return }
                
                // Convert to MentionUser (take first 5)
                let limitedUsers = Array(users.prefix(5))
                self.searchResults = limitedUsers.map { (user: FirebaseSearchUser) -> MentionUser in
                    return MentionUser(
                        userId: user.id,
                        username: user.username,
                        displayName: user.displayName,
                        profileImageUrl: user.profileImageURL
                    )
                }
            } catch {
                print("❌ Failed to search users for mentions: \(error)")
                self.searchResults = []
            }
        }
    }
}
