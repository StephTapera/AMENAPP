//
//  EditPostViewModel.swift
//  AMENAPP
//

import Foundation
import PhotosUI
import SwiftUI
import FirebaseAuth

@MainActor
final class EditPostViewModel: ObservableObject {
    enum SaveState: Equatable {
        case idle
        case saving
        case success(String)
        case failed(String)
    }

    let originalPost: Post

    @Published var draftText: String
    @Published var draftTopic: String
    @Published var draftCategory: Post.PostCategory
    @Published var draftMedia: [EditPostMediaDraftItem]
    @Published var intelligence: EditIntelligenceResult
    @Published var validation: EditPostValidationResult
    @Published var saveState: SaveState = .idle
    @Published var eligibility: EditEligibility
    @Published var showDiscardPrompt = false
    @Published var showUpdateInsteadSheet = false
    @Published var showTopicPicker = false
    @Published var showTypePicker = false
    @Published var selectedPhotos: [PhotosPickerItem] = []
    @Published var toastMessage: String?

    private var intelligenceTask: Task<Void, Never>?
    private let draftStore = EditPostDraftRecovery.shared

    init(post: Post) {
        self.originalPost = post

        let key = Self.makeDraftKey(for: post)
        let restoredDraft = key.flatMap { EditPostDraftRecovery.shared.loadDraft(for: $0) }
        let useRestoredDraft = restoredDraft?.baseEditVersion == post.editVersion
        let draftText = useRestoredDraft ? (restoredDraft?.text ?? post.content) : post.content
        let draftTopic = useRestoredDraft ? (restoredDraft?.topicTag ?? post.topicTag ?? "") : (post.topicTag ?? "")
        let draftCategory = useRestoredDraft ? (restoredDraft?.category ?? post.category) : post.category
        let draftMedia = useRestoredDraft ? (restoredDraft?.media ?? EditPostMediaDraftItem.fromPost(post)) : EditPostMediaDraftItem.fromPost(post)

        self.draftText = draftText
        self.draftTopic = draftTopic
        self.draftCategory = draftCategory
        self.draftMedia = draftMedia

        let policy = EditWindowPolicyState.forCategory(post.category)
        let expiry = post.editWindowExpiresAt ?? policy.expiryDate(createdAt: post.createdAt)
        self.eligibility = EditEligibility(
            canEdit: Date() <= expiry,
            editWindowExpiresAt: expiry,
            editPolicyType: policy.policyType,
            editRestrictionReason: Date() <= expiry ? nil : .windowExpired
        )

        self.intelligence = EditIntelligenceEngine.analyze(
            original: post,
            text: draftText,
            topicTag: draftTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draftTopic.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draftCategory,
            media: draftMedia
        )
        self.validation = EditIntelligenceEngine.validate(
            original: post,
            text: draftText,
            category: draftCategory,
            media: draftMedia
        )
    }

    var dirtyFields: EditPostDirtyFields {
        EditPostDiffEngine.diff(
            original: originalPost,
            text: draftText,
            topicTag: normalizedTopic,
            category: draftCategory,
            media: draftMedia
        ).dirtyFields
    }

    var hasChanges: Bool { dirtyFields.isDirty }

    var canSave: Bool {
        eligibility.canEdit && validation.canSave && hasChanges && saveState != .saving
    }

    var helperText: String {
        if let notice = intelligence.notices.first {
            return notice
        }
        return EditIntelligenceEngine.helperText(for: draftCategory, text: draftText)
    }

    var normalizedTopic: String? {
        let trimmed = draftTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var remainingCharacters: Int {
        max(0, 500 - draftText.count)
    }

    var shouldShowIntelligencePanel: Bool {
        !intelligence.notices.isEmpty || intelligence.evidenceSuggestion != nil
    }

    func refreshDerivedState() {
        intelligenceTask?.cancel()
        let text = draftText
        let topic = normalizedTopic
        let category = draftCategory
        let media = draftMedia
        intelligenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            intelligence = EditIntelligenceEngine.analyze(
                original: originalPost,
                text: text,
                topicTag: topic,
                category: category,
                media: media
            )
            validation = EditIntelligenceEngine.validate(
                original: originalPost,
                text: text,
                category: category,
                media: media
            )
            persistDraftIfNeeded()
        }
    }

    func handleSelectedPhotosChange() async {
        guard !selectedPhotos.isEmpty else { return }
        var newMedia = draftMedia
        var oversized = 0
        for item in selectedPhotos {
            if let data = try? await item.loadTransferable(type: Data.self) {
                if data.count > 10 * 1024 * 1024 {
                    oversized += 1
                    continue
                }
                newMedia.append(
                    EditPostMediaDraftItem(
                        id: UUID().uuidString,
                        remoteURL: nil,
                        localImageData: data,
                        orderIndex: newMedia.count
                    )
                )
            }
        }
        draftMedia = normalizedMedia(newMedia)
        selectedPhotos = []
        if oversized > 0 {
            toastMessage = "\(oversized) image(s) were skipped because they exceeded the size limit."
        }
        refreshDerivedState()
    }

    func removeMedia(id: String) {
        draftMedia.removeAll { $0.id == id }
        draftMedia = normalizedMedia(draftMedia)
        refreshDerivedState()
    }

    func moveMediaLeft(id: String) {
        guard let index = draftMedia.firstIndex(where: { $0.id == id }), index > 0 else { return }
        draftMedia.swapAt(index, index - 1)
        draftMedia = normalizedMedia(draftMedia)
        refreshDerivedState()
    }

    func moveMediaRight(id: String) {
        guard let index = draftMedia.firstIndex(where: { $0.id == id }), index < draftMedia.count - 1 else { return }
        draftMedia.swapAt(index, index + 1)
        draftMedia = normalizedMedia(draftMedia)
        refreshDerivedState()
    }

    func discardChanges() {
        if let key = Self.makeDraftKey(for: originalPost) {
            draftStore.clearDraft(for: key)
        }
    }

    func save(mode: EditSaveMode = .edit) async -> EditPostResult? {
        validation = EditIntelligenceEngine.validate(
            original: originalPost,
            text: draftText,
            category: draftCategory,
            media: draftMedia
        )
        guard validation.canSave else {
            saveState = .failed("Your edit still needs a few fixes before it can be saved.")
            return nil
        }
        guard eligibility.canEdit else {
            saveState = .failed("The edit window has closed for this post.")
            return nil
        }

        saveState = .saving
        do {
            let request = EditPostRequest(
                postId: originalPost.firebaseId ?? originalPost.id.uuidString,
                expectedVersion: originalPost.editVersion,
                editedText: draftText.trimmingCharacters(in: .whitespacesAndNewlines),
                topicTag: normalizedTopic,
                category: draftCategory,
                media: normalizedMedia(draftMedia),
                clientEditSessionStartedAt: Date(),
                intelligence: intelligence,
                saveMode: mode
            )
            let result = try await PostsManager.shared.submitEdit(request: request, localPostId: originalPost.id)
            if let key = Self.makeDraftKey(for: originalPost) {
                draftStore.clearDraft(for: key)
            }
            eligibility = result.eligibility
            saveState = .success(mode == .edit ? "Changes saved" : "Update added")
            return result
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            saveState = .failed(message)
            return nil
        }
    }

    private func persistDraftIfNeeded() {
        guard hasChanges, let key = Self.makeDraftKey(for: originalPost) else { return }
        let snapshot = EditPostDraftSnapshot(
            postId: key.postId,
            baseEditVersion: originalPost.editVersion,
            text: draftText,
            topicTag: normalizedTopic,
            category: draftCategory,
            media: normalizedMedia(draftMedia),
            savedAt: Date()
        )
        draftStore.saveDraft(snapshot, for: key)
    }

    private func normalizedMedia(_ media: [EditPostMediaDraftItem]) -> [EditPostMediaDraftItem] {
        media.enumerated().map { index, item in
            var updated = item
            updated.orderIndex = index
            return updated
        }
    }

    private static func makeDraftKey(for post: Post) -> PostEditSessionDraftKey? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        return PostEditSessionDraftKey(userId: userId, postId: post.firebaseId ?? post.id.uuidString)
    }
}
