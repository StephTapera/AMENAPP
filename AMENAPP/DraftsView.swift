//
//  DraftsView.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//

import SwiftUI

// MARK: - Drafts View

struct DraftsView: View {
    @StateObject private var draftsManager = DraftsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDraft: PostDraft?
    @State private var showDeleteAllConfirmation = false
    @State private var draftToDelete: PostDraft?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if draftsManager.drafts.isEmpty {
                    // Empty State
                    emptyStateView
                } else {
                    // Drafts List
                    ScrollView {
                        VStack(spacing: 16) {
                            // Info Banner
                            infoBanner
                            
                            // Drafts
                            ForEach(draftsManager.drafts) { draft in
                                DraftCard(
                                    draft: draft,
                                    onTap: {
                                        selectedDraft = draft
                                    },
                                    onDelete: {
                                        draftToDelete = draft
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if !draftsManager.drafts.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                draftsManager.cleanupExpiredDrafts()
                            } label: {
                                Label("Clean Up Expired", systemImage: "trash.circle")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                showDeleteAllConfirmation = true
                            } label: {
                                Label("Delete All Drafts", systemImage: "trash.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 18))
                        }
                    }
                }
            }
            .sheet(item: $selectedDraft) { draft in
                EditDraftView(draft: draft) { updatedDraft in
                    // Update draft in manager
                    if let index = draftsManager.drafts.firstIndex(where: { $0.id == draft.id }) {
                        draftsManager.drafts[index] = updatedDraft
                    }
                }
            }
            .confirmationDialog("Delete this draft?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let draft = draftToDelete {
                        withAnimation {
                            draftsManager.deleteDraft(draft)
                        }
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .confirmationDialog("Delete all drafts?", isPresented: $showDeleteAllConfirmation, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    withAnimation {
                        draftsManager.deleteAllDrafts()
                    }
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.warning)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All \(draftsManager.drafts.count) drafts will be permanently deleted.")
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
            
            Text("No Drafts")
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(.primary)
            
            Text("Your saved drafts will appear here.\nThey'll be automatically deleted after 7 days.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - Info Banner
    
    private var infoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-delete after 7 days")
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.primary)
                
                Text("Drafts are saved locally on your device")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
    }
}

// MARK: - Draft Card

struct DraftCard: View {
    let draft: PostDraft
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    // Category Icon
                    ZStack {
                        Circle()
                            .fill(draft.categoryColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: draft.categoryIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(draft.categoryColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.category)
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.primary)
                        
                        if let topicTag = draft.topicTag {
                            Text(topicTag)
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Delete Button
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                }
                
                // Content Preview
                Text(draft.content)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .lineSpacing(4)
                
                // Footer
                HStack {
                    // Time Info
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        
                        Text(timeAgoString(from: draft.savedAt))
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Expiry Warning
                    if draft.daysRemaining <= 2 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                            
                            Text("\(draft.daysRemaining) day\(draft.daysRemaining == 1 ? "" : "s") left")
                                .font(.custom("OpenSans-Bold", size: 11))
                        }
                        .foregroundStyle(draft.daysRemaining == 0 ? .red : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill((draft.daysRemaining == 0 ? Color.red : Color.orange).opacity(0.15))
                        )
                    } else {
                        Text("Expires in \(draft.daysRemaining) days")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                
                // Link indicator
                if let link = draft.linkURL, !link.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                        Text("Link attached")
                            .font(.custom("OpenSans-SemiBold", size: 11))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.1))
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeIn(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
    
    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "Just now"
        }
    }
}

// MARK: - Edit Draft View

struct EditDraftView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var postsManager = PostsManager.shared
    
    let draft: PostDraft
    let onUpdate: (PostDraft) -> Void
    
    @State private var content: String
    @State private var linkURL: String
    @State private var isPublishing = false
    
    init(draft: PostDraft, onUpdate: @escaping (PostDraft) -> Void) {
        self.draft = draft
        self.onUpdate = onUpdate
        _content = State(initialValue: draft.content)
        _linkURL = State(initialValue: draft.linkURL ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Category Header
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(draft.categoryColor.opacity(0.15))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: draft.categoryIcon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(draft.categoryColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.category)
                                .font(.custom("OpenSans-Bold", size: 18))
                            
                            if let topicTag = draft.topicTag {
                                Text(topicTag)
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Expiry Badge
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(draft.daysRemaining)")
                                .font(.custom("OpenSans-Bold", size: 20))
                                .foregroundStyle(draft.daysRemaining <= 2 ? .red : .primary)
                            
                            Text("days left")
                                .font(.custom("OpenSans-Regular", size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    
                    // Content Editor
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Content")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: $content)
                            .font(.custom("OpenSans-Regular", size: 16))
                            .frame(minHeight: 200)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                    }
                    
                    // Link (if exists)
                    if !draft.linkURL.isNilOrEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Link")
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "link")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.blue)
                                
                                Text(draft.linkURL ?? "")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                        }
                    }
                    
                    // Saved Info
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        
                        Text("Saved \(timeAgoString(from: draft.savedAt))")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Edit Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            publishDraft()
                        } label: {
                            Label("Publish Now", systemImage: "paperplane.fill")
                        }
                        
                        Button {
                            updateDraft()
                        } label: {
                            Label("Save Changes", systemImage: "square.and.arrow.down")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            DraftsManager.shared.deleteDraft(draft)
                            dismiss()
                        } label: {
                            Label("Delete Draft", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private func publishDraft() {
        guard !isPublishing else { return }
        isPublishing = true
        
        // Convert category string to Post.PostCategory
        let postCategory: Post.PostCategory
        switch draft.category {
        case "#OPENTABLE":
            postCategory = .openTable
        case "Testimonies":
            postCategory = .testimonies
        case "Prayer":
            postCategory = .prayer
        default:
            postCategory = .openTable
        }
        
        // Convert visibility string to Post.PostVisibility
        let postVisibility: Post.PostVisibility
        switch draft.visibility {
        case "Everyone":
            postVisibility = .everyone
        case "Followers":
            postVisibility = .followers
        case "Community Only":
            postVisibility = .community
        default:
            postVisibility = .everyone
        }
        
        // Create post
        postsManager.createPost(
            content: content,
            category: postCategory,
            topicTag: draft.topicTag,
            visibility: postVisibility,
            allowComments: true,
            imageURLs: nil,
            linkURL: draft.linkURL
        )
        
        // Delete draft
        DraftsManager.shared.deleteDraft(draft)
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        // Dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            dismiss()
        }
    }
    
    private func updateDraft() {
        let updatedDraft = PostDraft(
            id: draft.id,
            content: content,
            category: draft.category,
            topicTag: draft.topicTag,
            linkURL: linkURL.isEmpty ? nil : linkURL,
            visibility: draft.visibility,
            savedAt: Date() // Update save time
        )
        
        onUpdate(updatedDraft)
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        dismiss()
    }
    
    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "just now"
        }
    }
}

// MARK: - Helper Extension

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
}

#Preview {
    DraftsView()
}
