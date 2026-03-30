//
//  DraftsView.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//

import SwiftUI

// MARK: - Drafts View

struct DraftsView: View {
    @ObservedObject private var draftsManager = DraftsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDraft: PostDraft?
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if draftsManager.drafts.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Compact info bar — not a heavy banner
                            infoBar
                                .padding(.horizontal, 16)
                                .padding(.top, 4)

                            ForEach(draftsManager.drafts) { draft in
                                DraftCard(draft: draft) {
                                    selectedDraft = draft
                                }
                                .padding(.horizontal, 16)
                                // Swipe to delete
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            draftsManager.deleteDraft(draft)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }

                            Spacer().frame(height: 32)
                        }
                        .padding(.vertical, 8)
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
                    .font(.custom("OpenSans-SemiBold", size: 15))
                }

                if !draftsManager.drafts.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    draftsManager.cleanupExpiredDrafts()
                                }
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
                                .font(.system(size: 17))
                        }
                    }
                }
            }
            .sheet(item: $selectedDraft) { draft in
                EditDraftView(draft: draft) { updatedDraft in
                    if let index = draftsManager.drafts.firstIndex(where: { $0.id == draft.id }) {
                        draftsManager.drafts[index] = updatedDraft
                    }
                }
            }
            .confirmationDialog(
                "Delete all \(draftsManager.drafts.count) drafts?",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        draftsManager.deleteAllDrafts()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 80, height: 80)

                Image(systemName: "doc.text")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text("No Drafts")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)

                Text("Posts you save while composing\nappear here for up to 7 days.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Info Bar

    private var infoBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Drafts are saved locally · auto-deleted after 7 days")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Draft Card

struct DraftCard: View {
    let draft: PostDraft
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // ── Header (matches PostCard header style) ──────────────────
                HStack(spacing: 12) {
                    // Category icon — same 44x44 circle as PostCard avatar
                    ZStack {
                        Circle()
                            .fill(draft.categoryColor.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: draft.categoryIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(draft.categoryColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        // Category label styled like author name
                        HStack(spacing: 6) {
                            Text(draft.category)
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundStyle(.primary)

                            // Expiry badge — urgent only
                            if draft.daysRemaining <= 2 {
                                expiryBadge
                            }
                        }

                        // Topic tag styled like username line
                        if let tag = draft.topicTag {
                            Text(tag)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(timeAgoString(from: draft.savedAt))
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Days remaining — non-urgent, quiet
                    if draft.daysRemaining > 2 {
                        Text("\(draft.daysRemaining)d")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                // ── Content preview ─────────────────────────────────────────
                Text(draft.content)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .lineSpacing(3)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                // ── Metadata pills row ───────────────────────────────────────
                if draft.linkURL != nil || draft.topicTag != nil {
                    HStack(spacing: 8) {
                        if let link = draft.linkURL, !link.isEmpty {
                            metadataPill(
                                icon: "link",
                                label: "Link",
                                color: .blue
                            )
                        }
                        if draft.topicTag != nil {
                            // Show time here since tag already showed above
                            metadataPill(
                                icon: "clock",
                                label: timeAgoString(from: draft.savedAt),
                                color: .secondary
                            )
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                Spacer().frame(height: 18)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            )
            // Thin left accent bar matching category color
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(draft.categoryColor.opacity(0.6))
                    .frame(width: 3)
                    .padding(.vertical, 18)
                    .padding(.leading, 1)
            }
            .scaleEffect(isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        ._onButtonGesture(pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    // MARK: - Subviews

    @ViewBuilder
    private var expiryBadge: some View {
        let isExpiring = draft.daysRemaining == 0
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text(isExpiring ? "Expires today" : "\(draft.daysRemaining)d left")
                .font(.custom("OpenSans-Bold", size: 10))
        }
        .foregroundStyle(isExpiring ? .red : .orange)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill((isExpiring ? Color.red : Color.orange).opacity(0.12))
        )
    }

    private func metadataPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 11))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }

    private func timeAgoString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: Date())
        if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hr ago" : "\(hours) hrs ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 min ago" : "\(minutes) min ago"
        } else {
            return "Just now"
        }
    }
}

// MARK: - Edit Draft View

struct EditDraftView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var postsManager = PostsManager.shared

    let draft: PostDraft
    let onUpdate: (PostDraft) -> Void

    @State private var content: String
    @State private var isPublishing = false
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    @FocusState private var editorFocused: Bool

    init(draft: PostDraft, onUpdate: @escaping (PostDraft) -> Void) {
        self.draft = draft
        self.onUpdate = onUpdate
        _content = State(initialValue: draft.content)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // ── Category context row ─────────────────────────────
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(draft.categoryColor.opacity(0.12))
                                    .frame(width: 44, height: 44)

                                Image(systemName: draft.categoryIcon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(draft.categoryColor)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(draft.category)
                                    .font(.custom("OpenSans-Bold", size: 15))
                                    .foregroundStyle(.primary)

                                HStack(spacing: 6) {
                                    Text("Saved \(timeAgoString(from: draft.savedAt))")
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)

                                    if let tag = draft.topicTag {
                                        Text("·")
                                            .foregroundStyle(.tertiary)
                                        Text(tag)
                                            .font(.custom("OpenSans-Regular", size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            // Expiry indicator
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(draft.daysRemaining)")
                                    .font(.custom("OpenSans-Bold", size: 17))
                                    .foregroundStyle(draft.daysRemaining <= 2 ? (draft.daysRemaining == 0 ? .red : .orange) : .primary)
                                Text("days left")
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .background(Color(.systemBackground))

                        Divider()
                            .padding(.horizontal, 20)

                        // ── Text editor ──────────────────────────────────────
                        TextEditor(text: $content)
                            .font(.custom("OpenSans-Regular", size: 16))
                            .focused($editorFocused)
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                            .background(Color(.systemBackground))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                        // ── Link row (read-only) ──────────────────────────────
                        if let link = draft.linkURL, !link.isEmpty {
                            Divider()
                                .padding(.horizontal, 20)

                            HStack(spacing: 10) {
                                Image(systemName: "link")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.blue)
                                Text(link)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color(.systemBackground))
                        }

                        // ── Visibility row ────────────────────────────────────
                        Divider()
                            .padding(.horizontal, 20)

                        HStack(spacing: 8) {
                            Image(systemName: visibilityIcon(draft.visibility))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(draft.visibility)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color(.systemBackground))

                        Spacer().frame(height: 100) // Clearance for bottom bar
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }

                // ── Bottom action bar ────────────────────────────────────────
                bottomBar
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Edit Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 15))
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundStyle(.red)
                    }
                }
            }
            .confirmationDialog("Delete this draft?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Draft", role: .destructive) {
                    DraftsManager.shared.deleteDraft(draft)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            .onAppear {
                // Auto-focus editor so keyboard appears immediately
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    editorFocused = true
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Save changes
            Button {
                saveDraft()
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.primary)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .medium))
                    }
                    Text(isSaving ? "Saving…" : "Save")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                )
            }
            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || isPublishing)

            // Publish
            Button {
                publishDraft()
            } label: {
                HStack(spacing: 6) {
                    if isPublishing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .medium))
                    }
                    Text(isPublishing ? "Publishing…" : "Publish")
                        .font(.custom("OpenSans-Bold", size: 15))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.primary.opacity(0.3)
                            : Color.primary
                        )
                )
            }
            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    // MARK: - Actions

    private func saveDraft() {
        guard !isSaving else { return }
        isSaving = true
        editorFocused = false

        let updatedDraft = PostDraft(
            id: draft.id,
            content: content,
            category: draft.category,
            topicTag: draft.topicTag,
            linkURL: draft.linkURL,
            visibility: draft.visibility,
            savedAt: Date()
        )
        onUpdate(updatedDraft)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isSaving = false
            dismiss()
        }
    }

    private func publishDraft() {
        guard !isPublishing else { return }
        isPublishing = true
        editorFocused = false

        let postCategory: Post.PostCategory
        switch draft.category {
        case "#OPENTABLE": postCategory = .openTable
        case "Testimonies": postCategory = .testimonies
        case "Prayer": postCategory = .prayer
        default: postCategory = .openTable
        }

        let postVisibility: Post.PostVisibility
        switch draft.visibility {
        case "Followers": postVisibility = .followers
        case "Community Only": postVisibility = .community
        default: postVisibility = .everyone
        }

        postsManager.createPost(
            content: content,
            category: postCategory,
            topicTag: draft.topicTag,
            visibility: postVisibility,
            allowComments: true,
            imageURLs: nil,
            linkURL: draft.linkURL
        )

        DraftsManager.shared.deleteDraft(draft)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            dismiss()
        }
    }

    private func visibilityIcon(_ visibility: String) -> String {
        switch visibility {
        case "Followers": return "person.2"
        case "Community Only": return "building.2"
        default: return "globe"
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: Date())
        if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hr ago" : "\(hours) hrs ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 min ago" : "\(minutes) min ago"
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
