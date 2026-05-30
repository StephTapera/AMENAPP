// CustomFeedEditorView.swift
// AMENAPP — SocialLayer
//
// "Edit Feeds" modal screen. Presented from the feed tab bar.
// Supports reorder (drag handle), swipe-to-delete (non-built-in only),
// and a "Create New Feed" sheet.
//
// Contract types live in ComposerContract.swift; supplementary types in CustomFeedModels.swift.

import SwiftUI

// MARK: - CustomFeedEditorView

struct CustomFeedEditorView: View {

    @StateObject private var service = CustomFeedService.shared
    var userId: String
    var onDismiss: () -> Void

    @State private var showCreateSheet = false
    @State private var deleteError: String? = nil
    @State private var showDeleteErrorAlert = false

    var body: some View {
        NavigationStack {
            List {
                feedRows
                createButton
            }
            .listStyle(.insetGrouped)
            .background(AmenTheme.Colors.backgroundGrouped)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Feeds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .accessibilityLabel("Done editing feeds")
                }
            }
            .alert("Unable to Delete Feed", isPresented: $showDeleteErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "This feed cannot be deleted.")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateFeedSheet(userId: userId)
        }
        .task {
            await service.loadFeeds(userId: userId)
        }
    }

    // MARK: - Feed rows section

    @ViewBuilder
    private var feedRows: some View {
        Section {
            ForEach(service.feeds) { feed in
                FeedEditorRow(feed: feed)
                    .listRowBackground(AmenTheme.Colors.backgroundGroupedRow)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .onMove { indices, destination in
                moveFeed(from: indices, to: destination)
            }
            .onDelete { indexSet in
                deleteFeeds(at: indexSet)
            }
        }
    }

    // MARK: - Create New Feed button

    @ViewBuilder
    private var createButton: some View {
        Section {
            Button {
                showCreateSheet = true
            } label: {
                Label("Create New Feed", systemImage: "plus.circle.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
            .listRowBackground(AmenTheme.Colors.backgroundGroupedRow)
            .accessibilityLabel("Create a new custom feed")
            .buttonStyle(.plain)
        }
    }

    // MARK: - Move handler

    private func moveFeed(from indices: IndexSet, to destination: Int) {
        var reordered = service.feeds
        reordered.move(fromOffsets: indices, toOffset: destination)

        // Animate locally first for instant feedback
        withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.78))) {
            service.feeds = reordered
        }

        Task {
            try? await service.reorderFeeds(reordered, userId: userId)
        }
    }

    // MARK: - Delete handler

    private func deleteFeeds(at indexSet: IndexSet) {
        for index in indexSet {
            let feed = service.feeds[index]
            guard !feed.isBuiltIn else {
                deleteError = ""\(feed.name)" is a built-in feed and cannot be deleted."
                showDeleteErrorAlert = true
                return
            }
            Task {
                do {
                    try await service.deleteFeed(id: feed.id, userId: userId)
                } catch {
                    deleteError = error.localizedDescription
                    showDeleteErrorAlert = true
                }
            }
        }
    }
}

// MARK: - FeedEditorRow

private struct FeedEditorRow: View {

    let feed: CustomFeedConfig

    var body: some View {
        HStack(spacing: 12) {
            // Feed icon
            Image(systemName: DefaultFeedIcon.symbol(for: feed.name))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(feed.isBuiltIn ? AmenTheme.Colors.amenBlue : AmenTheme.Colors.textSecondary)
                .frame(width: 30, alignment: .center)
                .accessibilityHidden(true)

            // Feed name
            Text(feed.name)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Built-in badge
            if feed.isBuiltIn {
                Text("Built-in")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(AmenTheme.Colors.surfaceChip)
                    )
                    .accessibilityLabel("Built-in feed")
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feed.isBuiltIn ? "\(feed.name), built-in feed" : feed.name)
        .accessibilityHint(feed.isBuiltIn ? "Cannot be deleted" : "Swipe left to delete")
    }
}

// MARK: - CreateFeedSheet

struct CreateFeedSheet: View {

    var userId: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CustomFeedService.shared

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var isPublic: Bool = false
    @State private var selectedTopics: Set<FeedTopic> = []
    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var showSaveErrorAlert = false
    @State private var nameTouched = false

    private var isNameValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canSave: Bool { isNameValid && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                descriptionSection
                visibilitySection
                topicsSection
            }
            .scrollContentBackground(.hidden)
            .background(AmenTheme.Colors.backgroundGrouped)
            .navigationTitle("New Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
            .alert("Could Not Save Feed", isPresented: $showSaveErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Please try again.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Form sections

    @ViewBuilder
    private var nameSection: some View {
        Section {
            TextField("Feed name", text: $name)
                .autocorrectionDisabled()
                .onChange(of: name) { _, _ in nameTouched = true }
                .accessibilityLabel("Feed name (required)")

            if nameTouched && !isNameValid {
                Label("Name is required", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.statusError)
                    .accessibilityLabel("Feed name is required")
            }
        } header: {
            Text("Name")
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        Section {
            TextField("Optional description", text: $description, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityLabel("Feed description, optional")
        } header: {
            Text("Description")
        }
    }

    @ViewBuilder
    private var visibilitySection: some View {
        Section {
            Toggle("Public", isOn: $isPublic)
                .tint(AmenTheme.Colors.amenBlue)
                .accessibilityLabel("Make this feed public")
        } header: {
            Text("Visibility")
        } footer: {
            Text("Public feeds can be discovered and followed by others.")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private var topicsSection: some View {
        Section {
            ForEach(FeedTopic.allCases) { topic in
                topicRow(topic)
            }
        } header: {
            Text("Topics")
        } footer: {
            Text("Posts matching these topics will appear in your feed.")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private func topicRow(_ topic: FeedTopic) -> some View {
        let isSelected = selectedTopics.contains(topic)
        Button {
            withAnimation(Motion.adaptive(Motion.popToggle)) {
                if isSelected {
                    selectedTopics.remove(topic)
                } else {
                    selectedTopics.insert(topic)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: topic.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? AmenTheme.Colors.amenBlue : AmenTheme.Colors.textSecondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(topic.rawValue)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(topic.rawValue)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Save button

    @ViewBuilder
    private var saveButton: some View {
        Button {
            nameTouched = true
            guard canSave else { return }
            Task { await save() }
        } label: {
            if isSaving {
                ProgressView()
                    .tint(AmenTheme.Colors.amenBlue)
                    .frame(width: 44, height: 20)
            } else {
                Text("Save")
                    .fontWeight(.semibold)
                    .foregroundStyle(canSave ? AmenTheme.Colors.amenBlue : AmenTheme.Colors.textTertiary)
            }
        }
        .disabled(!canSave)
        .accessibilityLabel(isSaving ? "Saving feed" : "Save feed")
    }

    // MARK: - Save action

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        let sortOrder = service.feeds.count   // append after existing feeds
        let config = CustomFeedConfig(
            id: UUID(),
            firestoreId: nil,
            name: name.trimmingCharacters(in: .whitespaces),
            feedDescription: description.trimmingCharacters(in: .whitespaces),
            isPublic: isPublic,
            profileIds: [],
            topicIds: selectedTopics.map(\.rawValue),
            sortOrder: sortOrder,
            createdAt: Date(),
            ownerId: userId,
            isBuiltIn: false
        )

        do {
            try await service.createFeed(config)
            dismiss()
        } catch {
            saveError = error.localizedDescription
            showSaveErrorAlert = true
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Editor") {
    CustomFeedEditorView(userId: "preview_user", onDismiss: {})
}

#Preview("Create Sheet") {
    CreateFeedSheet(userId: "preview_user")
}
#endif
