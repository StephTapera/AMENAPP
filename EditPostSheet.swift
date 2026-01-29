//
//  EditPostSheet.swift
//  AMENAPP
//
//  Sheet for editing an existing post
//

import SwiftUI

struct EditPostSheet: View {
    let post: Post
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var postsManager = PostsManager.shared
    
    @State private var editedContent: String
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    @FocusState private var isTextEditorFocused: Bool
    
    init(post: Post) {
        self.post = post
        _editedContent = State(initialValue: post.content)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Edit info banner
                HStack(spacing: 8) {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.blue)
                    
                    Text("Editing your post")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                    
                    Spacer()
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Author info
                        HStack(spacing: 12) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(post.authorInitials)
                                        .font(.custom("OpenSans-Bold", size: 14))
                                        .foregroundStyle(.white)
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.authorName)
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                
                                Text(post.category.rawValue)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        // Content editor
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $editedContent)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .frame(minHeight: 200)
                                .focused($isTextEditorFocused)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                            
                            // Character count
                            HStack {
                                Spacer()
                                Text("\(editedContent.count)/500")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(editedContent.count > 500 ? .red : .secondary)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Topic tag (if exists)
                        if let topicTag = post.topicTag {
                            HStack {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                
                                Text(topicTag)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                Divider()
                
                // Bottom action bar
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                    }
                    
                    Button {
                        saveChanges()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save Changes")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(hasChanges && isContentValid ? Color.blue : Color.gray)
                    )
                    .disabled(!hasChanges || !isContentValid || isSubmitting)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Edit Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // Auto-focus text editor
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextEditorFocused = true
                }
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var hasChanges: Bool {
        editedContent.trimmingCharacters(in: .whitespacesAndNewlines) != post.content
    }
    
    private var isContentValid: Bool {
        let trimmed = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 500
    }
    
    // MARK: - Actions
    
    private func saveChanges() {
        guard hasChanges && isContentValid else { return }
        
        isSubmitting = true
        
        Task {
            do {
                let trimmedContent = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Call PostsManager to edit the post
                postsManager.editPost(postId: post.id, newContent: trimmedContent)
                
                // Wait a moment for the update to process
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                await MainActor.run {
                    isSubmitting = false
                    
                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    // Dismiss sheet
                    dismiss()
                }
                
                print("✅ Post edited successfully")
                
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to save changes: \(error.localizedDescription)"
                    showError = true
                }
                
                print("❌ Failed to edit post: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let samplePost = Post(
        id: UUID(),
        authorId: "preview-user",
        authorName: "John Disciple",
        authorInitials: "JD",
        timeAgo: "5m",
        content: "This is a sample post that can be edited. Let's see how the edit functionality works!",
        category: .openTable,
        topicTag: "AI & Technology",
        visibility: .everyone,
        allowComments: true,
        imageURLs: nil,
        linkURL: nil,
        createdAt: Date(),
        amenCount: 0,
        lightbulbCount: 0,
        commentCount: 0,
        repostCount: 0,
        isRepost: false,
        originalAuthorName: nil,
        originalAuthorId: nil
    )
    
    EditPostSheet(post: samplePost)
}
