//
//  EditPostSheet.swift
//  AMENAPP
//

import SwiftUI
import PhotosUI

struct EditPostSheet: View {
    let post: Post

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var viewModel: EditPostViewModel
    @FocusState private var isTextFocused: Bool
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    init(post: Post) {
        self.post = post
        _viewModel = StateObject(wrappedValue: EditPostViewModel(post: post))
    }

    var body: some View {
        ZStack(alignment: .top) {
            background

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerSpacer
                    identityRow
                    composerCard
                    metadataRow
                    mediaSection
                    if viewModel.shouldShowIntelligencePanel {
                        intelligencePanel
                    }
                    if let message = statusMessage {
                        statusPanel(message)
                    }
                    policyFooter
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }

            headerBar
        }
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
                .background(.clear)
        }
        .onChange(of: viewModel.selectedPhotos) { _, _ in
            Task { await viewModel.handleSelectedPhotosChange() }
        }
        .onChange(of: viewModel.draftText) { _, _ in viewModel.refreshDerivedState() }
        .onChange(of: viewModel.draftTopic) { _, _ in viewModel.refreshDerivedState() }
        .onChange(of: viewModel.draftCategory) { _, _ in viewModel.refreshDerivedState() }
        .confirmationDialog("Discard changes?", isPresented: $viewModel.showDiscardPrompt, titleVisibility: .visible) {
            Button("Keep Editing", role: .cancel) { }
            Button("Discard Changes", role: .destructive) {
                viewModel.discardChanges()
                dismiss()
            }
        } message: {
            Text("Your draft edit will be lost.")
        }
        .sheet(isPresented: $viewModel.showTopicPicker) {
            EditPostTopicPickerSheet(selectedTopic: $viewModel.draftTopic)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showTypePicker) {
            EditPostTypePickerSheet(selectedCategory: $viewModel.draftCategory, originalCategory: post.category)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showUpdateInsteadSheet) {
            UpdateInsteadFlowSheet(
                onSaveAsEdit: {
                    Task { await performSave(mode: .edit) }
                },
                onAddUpdateInstead: {
                    Task { await performSave(mode: .updateInstead) }
                }
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        }
        .alert("Edit Post", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            isTextFocused = true
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.99, green: 0.99, blue: 0.985),
                Color(red: 0.96, green: 0.96, blue: 0.955)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var headerSpacer: some View {
        Color.clear.frame(height: 88)
    }

    private var headerBar: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color.black.opacity(0.10))
                .frame(width: 44, height: 5)
                .padding(.top, 8)

            HStack(spacing: 12) {
                Button {
                    handleDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(glassCircleBackground)
                }
                .accessibilityLabel("Cancel editing")

                Spacer(minLength: 12)

                VStack(spacing: 4) {
                    Text("Edit Post")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Editing your post")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(reduceTransparency ? 0.94 : 0.58))
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(0.65), lineWidth: 1)
                                )
                        )
                }

                Spacer(minLength: 12)

                Button {
                    if viewModel.hasChanges {
                        viewModel.showDiscardPrompt = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 72, height: 40)
                        .background(glassCapsuleBackground)
                }
                .accessibilityLabel("Cancel")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(reduceTransparency ? 0.97 : 0.88)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 18)
                }
                .ignoresSafeArea(edges: .top)
        )
    }

    private var identityRow: some View {
        HStack(spacing: 14) {
            Group {
                if let urlString = post.authorProfileImageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        avatarFallback
                    }
                } else {
                    avatarFallback
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(post.authorName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(post.category.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(16)
        .background(glassCardBackground)
    }

    private var avatarFallback: some View {
        Circle()
            .fill(Color.black.opacity(0.08))
            .overlay {
                Text(post.authorInitials)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
            }
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Post text")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(viewModel.remainingCharacters)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(viewModel.remainingCharacters < 25 ? .orange : .secondary)
            }

            ZStack(alignment: .topLeading) {
                if viewModel.draftText.isEmpty {
                    Text("Refine your post clearly without overwriting what readers already engaged with.")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                        .padding(.leading, 6)
                }

                TextEditor(text: $viewModel.draftText)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .focused($isTextFocused)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(reduceTransparency ? 0.98 : 0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(viewModel.hasChanges ? Color.black.opacity(0.09) : Color.white.opacity(0.65), lineWidth: 1)
                    )
            )

            if viewModel.hasChanges {
                Text("Changes detected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(glassCardBackground)
    }

    private var metadataRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                EditMetadataChip(
                    icon: "tag",
                    title: viewModel.normalizedTopic ?? "Add topic",
                    action: { viewModel.showTopicPicker = true }
                )
                EditMetadataChip(
                    icon: "square.grid.2x2",
                    title: viewModel.draftCategory.displayName,
                    action: { viewModel.showTypePicker = true }
                )
                EditMetadataChip(
                    icon: "photo.on.rectangle",
                    title: viewModel.draftMedia.isEmpty ? "No media" : "\(viewModel.draftMedia.count) media",
                    action: { }
                )
                EditMetadataChip(
                    icon: "clock",
                    title: timeWindowText,
                    action: { }
                )
            }
            .padding(.horizontal, 2)
        }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Media")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                PhotosPicker(selection: $viewModel.selectedPhotos, maxSelectionCount: 4, matching: .images) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(glassCapsuleBackground)
                }
            }

            if viewModel.draftMedia.isEmpty {
                Text("No media attached. Add, remove, or reorder images here without re-uploading unchanged ones.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(glassInsetBackground)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.draftMedia) { item in
                            EditMediaTile(
                                item: item,
                                isPrimary: item.orderIndex == 0,
                                onRemove: { viewModel.removeMedia(id: item.id) },
                                onMoveLeft: { viewModel.moveMediaLeft(id: item.id) },
                                onMoveRight: { viewModel.moveMediaRight(id: item.id) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(glassCardBackground)
    }

    private var intelligencePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.purple.opacity(0.9))
                Text("Edit intelligence")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(viewModel.intelligence.primaryType.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.intelligence.notices, id: \.self) { notice in
                Text(notice)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.82))
            }

            if let evidenceSuggestion = viewModel.intelligence.evidenceSuggestion {
                Label(evidenceSuggestion, systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if viewModel.intelligence.recommendUpdateInstead {
                Button {
                    viewModel.showUpdateInsteadSheet = true
                } label: {
                    Text("Consider Add Update Instead")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(glassCapsuleBackground)
                }
            }
        }
        .padding(16)
        .background(glassCardBackground)
    }

    private func statusPanel(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(glassInsetBackground)
    }

    private var policyFooter: some View {
        Text("Editing stays within AMEN’s trust-aware window and may show subtle edit context when meaning changes.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button {
                handleDismiss()
            } label: {
                Text(viewModel.hasChanges ? "Discard" : "Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(glassCapsuleBackground)
            }

            Button {
                if viewModel.intelligence.recommendUpdateInstead {
                    viewModel.showUpdateInsteadSheet = true
                } else {
                    Task { await performSave(mode: .edit) }
                }
            } label: {
                Group {
                    switch viewModel.saveState {
                    case .saving:
                        ProgressView().tint(.white)
                    default:
                        Text("Save Changes")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    Capsule()
                        .fill(viewModel.canSave ? Color.black : Color.black.opacity(0.22))
                )
            }
            .disabled(!viewModel.canSave)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10 + safeAreaBottomInset)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(reduceTransparency ? 0.98 : 0.9)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(height: 1)
                }
        )
    }

    private var statusMessage: String? {
        switch viewModel.saveState {
        case .idle:
            return viewModel.toastMessage
        case .saving:
            return "Saving your changes…"
        case .success(let message):
            return message
        case .failed(let message):
            return message
        }
    }

    private var timeWindowText: String {
        guard let expiry = viewModel.eligibility.editWindowExpiresAt else { return "Window unavailable" }
        if expiry < Date() { return "Window closed" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Ends \(formatter.localizedString(for: expiry, relativeTo: Date()))"
    }

    private var glassCardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(reduceTransparency ? 0.96 : 0.70))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 10)
    }

    private var glassInsetBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(reduceTransparency ? 0.97 : 0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
    }

    private var glassCapsuleBackground: some View {
        Capsule()
            .fill(Color.white.opacity(reduceTransparency ? 0.95 : 0.7))
            .overlay(Capsule().stroke(Color.white.opacity(0.62), lineWidth: 1))
    }

    private var glassCircleBackground: some View {
        Circle()
            .fill(Color.white.opacity(reduceTransparency ? 0.95 : 0.7))
            .overlay(Circle().stroke(Color.white.opacity(0.62), lineWidth: 1))
    }

    private var safeAreaBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
    }

    private func handleDismiss() {
        if viewModel.hasChanges {
            viewModel.showDiscardPrompt = true
        } else {
            dismiss()
        }
    }

    private func performSave(mode: EditSaveMode) async {
        if let _ = await viewModel.save(mode: mode) {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            dismiss()
        } else if case .failed(let message) = viewModel.saveState {
            errorMessage = message
            showErrorAlert = true
        }
    }
}

private struct EditMetadataChip: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.7))
                    .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EditMediaTile: View {
    let item: EditPostMediaDraftItem
    let isPrimary: Bool
    let onRemove: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let data = item.localImageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if let remoteURL = item.remoteURL, let url = URL(string: remoteURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Color.black.opacity(0.08)
                            }
                        }
                    } else {
                        Color.black.opacity(0.08)
                    }
                }
                .frame(width: 122, height: 122)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if isPrimary {
                    Text("Primary")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.86))
                        )
                        .padding(8)
                }
            }

            HStack(spacing: 8) {
                smallButton("arrow.left", action: onMoveLeft)
                smallButton("arrow.right", action: onMoveRight)
                smallButton("trash", action: onRemove)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.68))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private func smallButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.82)))
        }
        .buttonStyle(.plain)
    }
}

private struct EditPostTopicPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTopic: String

    private let suggestions = [
        "Prayer",
        "Scripture reflection",
        "Church life",
        "Family",
        "Testimony",
        "Worship",
        "Discipleship",
        "Encouragement",
        "Local church",
        "Recovery"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Suggested topics") {
                    ForEach(suggestions, id: \.self) { topic in
                        Button(topic) {
                            selectedTopic = topic
                            dismiss()
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("Custom") {
                    TextField("Topic", text: $selectedTopic)
                }
            }
            .navigationTitle("Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct EditPostTypePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCategory: Post.PostCategory
    let originalCategory: Post.PostCategory

    var body: some View {
        NavigationStack {
            List {
                ForEach(Post.PostCategory.allCases, id: \.self) { category in
                    Button {
                        if EditIntelligenceEngine.isValidTransition(from: originalCategory, to: category) {
                            selectedCategory = category
                            dismiss()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.displayName)
                                    .foregroundStyle(.primary)
                                if !EditIntelligenceEngine.isValidTransition(from: originalCategory, to: category) {
                                    Text("Not available for this post")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if category == selectedCategory {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .disabled(!EditIntelligenceEngine.isValidTransition(from: originalCategory, to: category))
                }
            }
            .navigationTitle("Post Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct UpdateInsteadFlowSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSaveAsEdit: () -> Void
    let onAddUpdateInstead: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.black.opacity(0.12))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            Text("This looks like a substantive change")
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)

            Text("If earlier replies already depend on the original post, adding an update can preserve context more cleanly.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            VStack(spacing: 12) {
                Button {
                    dismiss()
                    onSaveAsEdit()
                } label: {
                    Text("Save as Edit")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            Capsule().fill(Color.white.opacity(0.72))
                        )
                }

                Button {
                    dismiss()
                    onAddUpdateInstead()
                } label: {
                    Text("Add Update Instead")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().fill(Color.black))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                )
                .ignoresSafeArea()
        )
    }
}

#Preview {
    EditPostSheet(
        post: Post(
            id: UUID(),
            firebaseId: "preview_post",
            authorId: "preview-user",
            authorName: "John Disciple",
            authorInitials: "JD",
            timeAgo: "5m",
            content: "This is a sample post that can be edited thoughtfully with trust-aware guidance.",
            category: .openTable,
            topicTag: "Prayer",
            visibility: .everyone,
            allowComments: true,
            imageURLs: [
                "https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800"
            ],
            createdAt: Date().addingTimeInterval(-120),
            editWindowExpiresAt: Date().addingTimeInterval(600),
            amenCount: 12,
            lightbulbCount: 4,
            commentCount: 3,
            repostCount: 1
        )
    )
}
