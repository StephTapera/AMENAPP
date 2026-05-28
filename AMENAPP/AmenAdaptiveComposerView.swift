// AmenAdaptiveComposerView.swift
// AMENAPP
// Universal adaptive composer (Phase 2).

import SwiftUI
import PhotosUI
import FirebaseAuth

struct AmenAdaptiveComposerView: View {
    let intent: AmenCreationIntent

    @ObservedObject private var featureFlags = AMENFeatureFlags.shared
    @ObservedObject private var draftStore = AmenCreationDraftStore.shared
    @StateObject private var mediaCoordinator = AmenMediaUploadCoordinator()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: AmenCreationDraft
    @State private var showPreview = false
    @State private var showModePicker = false
    @State private var showMediaPicker = false
    @State private var showCamera = false
    @State private var showClassicComposer = false
    @State private var isPublishing = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var saveTask: Task<Void, Never>? = nil
    @State private var showScheduleSheet = false

    @State private var editingCaptionItemId: String? = nil
    @State private var editingCoverItemId: String? = nil
    @State private var editingVoiceoverItemId: String? = nil
    @State private var trimmingItemId: String? = nil

    @StateObject private var aiLayer = AmenCreationAILayer.shared

    init(intent: AmenCreationIntent) {
        self.intent = intent
        let ownerId = Auth.auth().currentUser?.uid ?? ""
        _draft = State(initialValue: AmenCreationDraft(ownerId: ownerId, intent: intent))
    }

    var body: some View {
        coreContent
            .sheet(item: bindingForItem(id: editingCaptionItemId)) { (binding: AmenMediaUploadItem) in
                AmenCaptionEditorView(caption: binding.mediaRef.caption ?? "") { newCaption in
                    mediaCoordinator.updateCaption(itemId: binding.id, caption: newCaption)
                    editingCaptionItemId = nil
                }
            }
            .sheet(item: bindingForItem(id: editingCoverItemId)) { (binding: AmenMediaUploadItem) in
                if let url = binding.localURL {
                    AmenCoverSelectorView(videoURL: url) { time in
                        mediaCoordinator.updateCover(itemId: binding.id, coverTime: time)
                        editingCoverItemId = nil
                    }
                }
            }
            .sheet(item: bindingForItem(id: editingVoiceoverItemId)) { (binding: AmenMediaUploadItem) in
                AmenVoiceoverRecorder { url in
                    if let url {
                        mediaCoordinator.attachVoiceover(itemId: binding.id, voiceoverURL: url)
                    }
                    editingVoiceoverItemId = nil
                }
            }
            .sheet(item: bindingForItem(id: trimmingItemId)) { (binding: AmenMediaUploadItem) in
                if let url = binding.localURL {
                    AmenVideoEditorView(videoURL: url) { trimmedURL in
                        if let trimmedURL {
                            mediaCoordinator.replaceLocalMedia(itemId: binding.id, with: trimmedURL)
                        }
                        trimmingItemId = nil
                    }
                }
            }
    }

    private var textComposer: some View {
        let binding = Binding<String>(get: { draft.text }, set: { updateText($0) })
        return TextEditor(text: binding)
            .font(.system(.body, design: .default))
            .padding(12)
            .frame(minHeight: 140)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
            .accessibilityLabel("Post text")
    }

    @ViewBuilder
    private var coreContentBody: some View {
        VStack(spacing: 12) {
            header
            textComposer

            if !mediaCoordinator.items.isEmpty {
                mediaSection
            }

            if !aiLayer.verseSuggestions.isEmpty {
                versesSuggestionRail
            }

            if !aiLayer.suggestedHashtags.isEmpty {
                hashtagsRail
            }

            Group {
                if let improved = aiLayer.captionImprovement {
                    captionImprovementChip(improved)
                }
            }

            AmenCreationToolbar(
                onAddMedia: { showMediaPicker = true },
                onOpenCamera: { showCamera = true },
                onPreview: { showPreview = true },
                onSwitchMode: { showModePicker = true }
            )

            publishRow
        }
    }

    private var coreContent: some View {
        coreContentBody
        .padding(.horizontal)
        .padding(.top, 12)
        .navigationTitle(draft.intent.displayName)
        .onAppear {}
        .task {
            await restoreDraftIfNeeded()
        }
        .onChange(of: mediaCoordinator.items) { _, _ in
            draft.updateMedia(mediaCoordinator.mediaRefs)
            scheduleSave()
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await mediaCoordinator.handlePickedItems(newItems, allowsMultiple: draft.intent.allowsMultipleMedia)
                selectedItems = []
            }
        }
        .modifier(ComposerSheetModifier(
            showPreview: $showPreview,
            showScheduleSheet: $showScheduleSheet,
            showMediaPicker: $showMediaPicker,
            showCamera: $showCamera,
            showClassicComposer: $showClassicComposer,
            draft: draft,
            selectedItems: $selectedItems,
            mediaCoordinator: mediaCoordinator
        ))
        .confirmationDialog("Switch creation mode", isPresented: $showModePicker, actions: modePicker)
    }

    private var header: some View {
        HStack {
            Text(draft.intent.displayName)
                .font(.systemScaled(18, weight: .bold))
            Spacer()
            Button("Classic") {
                showClassicComposer = true
            }
            .font(.systemScaled(12, weight: .semibold))
            .accessibilityLabel("Open classic composer")
        }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attachments")
                .font(.systemScaled(14, weight: .semibold))

            ForEach(mediaCoordinator.items) { item in
                AmenMediaAttachmentCard(
                    item: item,
                    onEditCaption: { editingCaptionItemId = item.id },
                    onSelectCover: { editingCoverItemId = item.id },
                    onVoiceover: { editingVoiceoverItemId = item.id },
                    onTrim: { trimmingItemId = item.id },
                    onRetry: { mediaCoordinator.retryUpload(itemId: item.id) }
                )
            }
        }
    }

    private var publishRow: some View {
        HStack {
            Button {
                showScheduleSheet = true
            } label: {
                Label("Schedule", systemImage: "calendar.badge.clock")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.amenGlass(role: .neutral, size: .compact, shape: .capsule, background: .balanced, placement: .inline))
            .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()

            Button {
                Task { await publishDraft() }
            } label: {
                if isPublishing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Publish")
                }
            }
            .buttonStyle(.amenGlass(role: .primary, size: .compact, shape: .capsule, background: .balanced, placement: .inline))
            .disabled(isPublishing || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Publish content")
        }
    }

    private var versesSuggestionRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scripture suggestions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(aiLayer.verseSuggestions) { hint in
                        Button {
                            let insert = "\n\n\(hint.reference) — \"\(hint.snippet)\""
                            updateText(draft.text + insert)
                            aiLayer.verseSuggestions = []
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hint.reference)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(hint.snippet)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: 180, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
    }

    private var hashtagsRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested hashtags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(aiLayer.suggestedHashtags, id: \.self) { tag in
                        Button {
                            let appended = draft.text.hasSuffix(" ") ? draft.text + tag : draft.text + " " + tag
                            updateText(appended)
                            aiLayer.suggestedHashtags = []
                        } label: {
                            Text(tag)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.08))
                                        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func captionImprovementChip(_ improved: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Berean caption suggestion")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 10) {
                Text(improved)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                Spacer()

                Button("Use") {
                    updateText(improved)
                    aiLayer.captionImprovement = nil
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)

                Button {
                    aiLayer.captionImprovement = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 0.5)
                    )
            )
        }
    }

    private func updateText(_ text: String) {
        draft.updateText(text)
        scheduleSave()
        aiLayer.suggestVerses(for: text, intent: draft.intent)
        Task { await aiLayer.suggestHashtags(for: text, intent: draft.intent) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(750))
            await draftStore.saveDraft(draft)
            // Cross-device sync via AmenDraftPersistenceService
            AmenDraftPersistenceService.shared.save(
                key: "composer_\(draft.intent.rawValue)",
                text: draft.text
            )
        }
    }

    private func restoreDraftIfNeeded() async {
        guard !draft.ownerId.isEmpty else {
            if let uid = Auth.auth().currentUser?.uid {
                draft.ownerId = uid
            }
            return
        }
        if let restored = await draftStore.loadDraft(ownerId: draft.ownerId, intent: draft.intent) {
            draft = restored
            mediaCoordinator.seed(with: restored.mediaRefs)
        } else if draft.text.isEmpty {
            // Fallback: pull cross-device draft from Firestore if local is empty
            let key = "composer_\(draft.intent.rawValue)"
            let local = AmenDraftPersistenceService.shared.load(key: key)
            if !local.isEmpty {
                draft.updateText(local)
            } else if let remote = await AmenDraftPersistenceService.shared.syncDown(key: key) {
                draft.updateText(remote)
            }
        }
    }

    private func publishDraft() async {
        guard !isPublishing else { return }
        isPublishing = true
        do {
            _ = try await draftStore.publishDraft(draft)
            await draftStore.deleteDraft(draft)
            AmenDraftPersistenceService.shared.clear(key: "composer_\(draft.intent.rawValue)")
            isPublishing = false
            dismiss()
        } catch {
            dlog("[AmenAdaptiveComposerView] Publish failed: \(error)")
            isPublishing = false
        }
    }

    @ViewBuilder
    private func modePicker() -> some View {
        ForEach(AmenCreationIntent.allCases, id: \.self) { (option: AmenCreationIntent) in
            Button(option.displayName) { switchMode(to: option) }
        }
    }

    private func switchMode(to option: AmenCreationIntent) {
        guard option != draft.intent else { return }
        draft.intent = option
        draft.updatedAt = Date()
        scheduleSave()
    }

    private func bindingForItem(id: String?) -> Binding<AmenMediaUploadItem?> {
        Binding(
            get: {
                guard let id else { return nil }
                return mediaCoordinator.items.first(where: { $0.id == id }) ?? AmenMediaUploadItem.placeholder(id: id)
            },
            set: { _ in }
        )
    }
}

private struct ComposerSheetModifier: ViewModifier {
    @Binding var showPreview: Bool
    @Binding var showScheduleSheet: Bool
    @Binding var showMediaPicker: Bool
    @Binding var showCamera: Bool
    @Binding var showClassicComposer: Bool
    let draft: AmenCreationDraft
    @Binding var selectedItems: [PhotosPickerItem]
    let mediaCoordinator: AmenMediaUploadCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showPreview) {
                NavigationStack { AmenCreationPreviewRenderer(draft: draft) }
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showScheduleSheet) {
                AmenSchedulePostSheet(draft: draft) { _ in }
            }
            .sheet(isPresented: $showMediaPicker) {
                AmenMediaPickerSheet(selection: $selectedItems)
            }
            .sheet(isPresented: $showCamera) {
                AmenCameraView { capture in
                    showCamera = false
                    guard let capture else { return }
                    let _: Task<Void, Never> = Task {
                        await mediaCoordinator.handleCameraCapture(capture, allowsMultiple: draft.intent.allowsMultipleMedia)
                    }
                }
            }
            .sheet(isPresented: $showClassicComposer) {
                Group { CreatePostView(initialCategory: CreatePostView.PostCategory.openTable) }
                    .presentationDragIndicator(.visible)
            }
    }
}

private struct AmenMediaPickerSheet: View {
    @Binding var selection: [PhotosPickerItem]

    var body: some View {
        VStack(spacing: 20) {
            Text("Add media")
                .font(.systemScaled(18, weight: .bold))
            PhotosPicker(selection: $selection, matching: .any(of: [.images, .videos])) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .font(.systemScaled(14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
            }
            .accessibilityLabel("Choose media from library")
        }
        .padding(24)
    }
}

private struct AmenMediaAttachmentCard: View {
    let item: AmenMediaUploadItem
    let onEditCaption: () -> Void
    let onSelectCover: () -> Void
    let onVoiceover: () -> Void
    let onTrim: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.mediaRef.type.rawValue.capitalized)
                    .font(.systemScaled(12, weight: .semibold))
                Spacer()
                AmenMediaProcessingStatusView(state: item.mediaRef.processingState ?? .processing, progress: item.progress, errorMessage: item.errorMessage)
            }

            if let caption = item.mediaRef.caption, !caption.isEmpty {
                Text(caption)
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Caption", action: onEditCaption)
                if item.mediaRef.type == .video {
                    Button("Cover", action: onSelectCover)
                    Button("Trim", action: onTrim)
                    Button("Voiceover", action: onVoiceover)
                }
                if item.mediaRef.processingState == .failed {
                    Button("Retry", action: onRetry)
                }
            }
            .font(.systemScaled(12, weight: .semibold))
            .accessibilityElement(children: .combine)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
    }
}
