// AmenSyncViewModel.swift
// AMEN Sync — Create Once, Distribute Everywhere
// Main observable view model

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI

@MainActor
final class AmenSyncViewModel: ObservableObject {

    // MARK: - Published

    @Published var project: AmenSyncProject?
    @Published var assets: [AmenSyncProjectAsset] = []
    @Published var variants: [AmenSyncVariant] = []
    @Published var jobs: [AmenSyncJob] = []
    @Published var projectState: SyncProjectStatus = .draft
    @Published var moderationStatus: SyncModerationStatus = .pending
    @Published var selectedDestinations: Set<SyncPlatform> = Set(SyncPlatform.allCases.filter { $0.canAutoPublish })
    @Published var caption: String = ""
    @Published var title: String = ""
    @Published var scriptureRef: String = ""
    @Published var tags: [String] = []
    @Published var mediaType: SyncMediaType = .image
    @Published var selectedPhotosItems: [PhotosPickerItem] = []
    @Published var uploadProgress: Double = 0
    @Published var isUploading = false
    @Published var isPreparing = false
    @Published var isModerating = false
    @Published var isPublishing = false
    @Published var errorMessage: String?
    @Published var showModerationSheet = false
    @Published var showReviewScreen = false
    @Published var showActivityView = false
    @Published var captionSuggestions: [SyncCaptionSuggestion] = []
    @Published var isGeneratingCaptions = false

    // MARK: - Private

    private lazy var db = Firestore.firestore()
    private lazy var storage = Storage.storage()
    private var projectListener: ListenerRegistration?
    private var variantsListener: ListenerRegistration?
    private var jobsListener: ListenerRegistration?
    private var captionTask: Task<Void, Never>?

    // MARK: - Computed

    var uid: String? { Auth.auth().currentUser?.uid }

    var canPrepare: Bool {
        !assets.isEmpty &&
        !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isPreparing &&
        projectState == .draft || projectState == .failed
    }

    var allVariantsReady: Bool {
        !variants.isEmpty && variants.allSatisfy { $0.status == .ready || $0.status == .approved }
    }

    var selectedPlatformCount: Int { selectedDestinations.count }

    var publishableVariants: [AmenSyncVariant] {
        variants.filter { selectedDestinations.contains($0.platform) && $0.status != .failed }
    }

    // MARK: - Project Lifecycle

    func createProject() async {
        guard let uid else { return }
        let projectId = "sync_\(uid)_\(Int(Date().timeIntervalSince1970))"
        let newProject = AmenSyncProject(
            id: nil,
            authorId: uid,
            title: title.isEmpty ? "AMEN Sync Project" : title,
            description: caption,
            mediaType: mediaType,
            status: .draft,
            selectedPlatforms: Array(selectedDestinations),
            masterAssetURL: nil,
            thumbnailURL: nil,
            createdAt: Date(),
            updatedAt: Date(),
            scheduledAt: nil,
            publishedAt: nil,
            tags: tags,
            scriptureRef: scriptureRef.isEmpty ? nil : scriptureRef,
            moderationStatus: .pending,
            moderationScore: 0,
            publishSummary: nil
        )
        do {
            let ref = db.collection("amenSyncProjects").document(projectId)
            try ref.setData(from: newProject)
            project = newProject
            startListeningToProject(projectId: projectId)
        } catch {
            errorMessage = "Couldn't create project. Please try again."
        }
    }

    func loadProject(_ projectId: String) {
        startListeningToProject(projectId: projectId)
    }

    private func startListeningToProject(projectId: String) {
        projectListener?.remove()
        projectListener = db
            .collection("amenSyncProjects")
            .document(projectId)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap, snap.exists else { return }
                if let p = try? snap.data(as: AmenSyncProject.self) {
                    self.project = p
                    self.projectState = p.status
                    self.moderationStatus = p.moderationStatus
                }
            }

        // Listen to variants
        variantsListener?.remove()
        variantsListener = db
            .collection("amenSyncVariants")
            .whereField("projectId", isEqualTo: projectId)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                self.variants = snap.documents.compactMap { try? $0.data(as: AmenSyncVariant.self) }
            }

        // Listen to jobs
        jobsListener?.remove()
        jobsListener = db
            .collection("amenSyncJobs")
            .whereField("projectId", isEqualTo: projectId)
            .order(by: "startedAt", descending: true)
            .limit(to: 10)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                self.jobs = snap.documents.compactMap { try? $0.data(as: AmenSyncJob.self) }
                // Update preparing state based on active jobs
                self.isPreparing = self.jobs.contains { $0.status == .running || $0.status == .queued }
            }
    }

    // MARK: - Asset Upload

    func uploadAssets(from items: [PhotosPickerItem]) async {
        guard let uid, let projectId = project?.id ?? project?.authorId else { return }
        isUploading = true
        uploadProgress = 0

        var uploadedCount = 0
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let assetId = UUID().uuidString
                let path = "amenSync/users/\(uid)/projects/\(projectId)/raw/\(assetId).jpg"
                let ref = storage.reference().child(path)

                do {
                    let metadata = StorageMetadata()
                    metadata.contentType = "image/jpeg"
                    // Compress before upload
                    let compressed = UIImage(data: data)?.jpegData(compressionQuality: 0.75) ?? data

                    _ = try await ref.putDataAsync(compressed, metadata: metadata)
                    let downloadURL = try await ref.downloadURL()

                    let asset = AmenSyncProjectAsset(
                        id: assetId,
                        projectId: projectId,
                        authorId: uid,
                        type: .image,
                        remoteURL: downloadURL.absoluteString,
                        thumbnailURL: nil,
                        duration: nil,
                        width: nil,
                        height: nil,
                        uploadedAt: Date()
                    )
                    try db.collection("amenSyncAssets").document(assetId).setData(from: asset)
                    assets.append(asset)

                    uploadedCount += 1
                    uploadProgress = Double(uploadedCount) / Double(items.count)
                } catch {
                    // Continue with remaining assets even if one fails
                }
            }
        }

        isUploading = false
        uploadProgress = 1.0
    }

    func removeAsset(_ asset: AmenSyncProjectAsset) {
        assets.removeAll { $0.id == asset.id }
        if let id = asset.id {
            Task {
                do {
                    try await db.collection("amenSyncAssets").document(id).delete()
                } catch {
                    print("AmenSyncViewModel: failed to delete asset \(id) — \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Prepare (Kick off pipeline)

    func startPrepare() async {
        guard let projectId = project?.id else {
            // Create project first if needed
            await createProject()
            guard project?.id != nil else { return }
            await startPrepare()
            return
        }

        isPreparing = true
        projectState = .processing

        // Update project in Firestore
        await updateProjectMeta(projectId: projectId)

        // Create processing jobs
        let platformsList = Array(selectedDestinations)
        for platform in platformsList {
            let job = AmenSyncJob(
                id: nil,
                projectId: projectId,
                authorId: uid ?? "",
                jobType: .cropImage,
                status: .queued,
                progress: 0,
                startedAt: nil,
                completedAt: nil,
                errorMessage: nil,
                resultPayload: ["platform": platform.rawValue]
            )
            do {
                try db.collection("amenSyncJobs").addDocument(from: job)
            } catch {
                print("AmenSyncViewModel: failed to enqueue crop job — \(error.localizedDescription)")
            }
        }

        // Caption job
        let captionJob = AmenSyncJob(
            id: nil, projectId: projectId, authorId: uid ?? "",
            jobType: .generateCaption, status: .queued, progress: 0,
            startedAt: nil, completedAt: nil, errorMessage: nil, resultPayload: nil
        )
        do {
            try db.collection("amenSyncJobs").addDocument(from: captionJob)
        } catch {
            print("AmenSyncViewModel: failed to enqueue caption job — \(error.localizedDescription)")
        }

        // Moderation job
        let modJob = AmenSyncJob(
            id: nil, projectId: projectId, authorId: uid ?? "",
            jobType: .moderateContent, status: .queued, progress: 0,
            startedAt: nil, completedAt: nil, errorMessage: nil, resultPayload: nil
        )
        do {
            try db.collection("amenSyncJobs").addDocument(from: modJob)
        } catch {
            print("AmenSyncViewModel: failed to enqueue moderation job — \(error.localizedDescription)")
        }

        // Simulate preparation locally (real work done by Cloud Functions)
        await simulateVariantGeneration(projectId: projectId)
    }

    private func simulateVariantGeneration(projectId: String) async {
        // While Cloud Functions process, create placeholder variants
        for platform in selectedDestinations {
            let variant = AmenSyncVariant(
                id: nil,
                projectId: projectId,
                platform: platform,
                mediaURL: assets.first?.remoteURL,
                caption: generatePlatformCaption(for: platform),
                hashtags: platform.supportsHashtags ? generateHashtags() : [],
                overlayText: scriptureRef.isEmpty ? nil : scriptureRef,
                overlayPosition: .bottomCenter,
                cropRect: nil,
                aiCaption: true,
                captionApproved: false,
                status: .adapting,
                publishedAt: nil,
                platformPostId: nil,
                errorMessage: nil,
                updatedAt: Date()
            )
            do {
                try db.collection("amenSyncVariants").addDocument(from: variant)
            } catch {
                print("AmenSyncViewModel: failed to create variant placeholder — \(error.localizedDescription)")
            }
        }

        // After 2 seconds, mark variants as ready (real: Cloud Functions trigger)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await markVariantsReady(projectId: projectId)
    }

    private func markVariantsReady(projectId: String) async {
        let snap = try? await db
            .collection("amenSyncVariants")
            .whereField("projectId", isEqualTo: projectId)
            .getDocuments()

        for doc in snap?.documents ?? [] {
            do {
                try await doc.reference.updateData(["status": "ready"])
            } catch {
                print("AmenSyncViewModel: failed to mark variant ready — \(error.localizedDescription)")
            }
        }

        projectState = .ready
        isPreparing = false
        do {
            try await db.collection("amenSyncProjects").document(projectId).updateData([
                "status": "ready",
                "moderationStatus": "approved",
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            print("AmenSyncViewModel: failed to mark project ready — \(error.localizedDescription)")
        }
    }

    // MARK: - Caption Generation

    func generateCaptionSuggestions() {
        captionTask?.cancel()
        isGeneratingCaptions = true
        captionTask = Task {
            let suggestions = await AmenSyncCaptionService.shared.generateSuggestions(
                masterCaption: caption,
                scripture: scriptureRef.isEmpty ? nil : scriptureRef,
                platforms: Array(selectedDestinations),
                tags: tags
            )
            if !Task.isCancelled {
                captionSuggestions = suggestions
                isGeneratingCaptions = false
            }
        }
    }

    func applyCaptionSuggestion(_ suggestion: SyncCaptionSuggestion, to platform: SyncPlatform? = nil) {
        if let platform = platform {
            if let idx = variants.firstIndex(where: { $0.platform == platform }) {
                variants[idx].caption = suggestion.text
            }
        } else {
            caption = suggestion.text
        }
    }

    // MARK: - Moderation

    func runModeration() async {
        isModerating = true
        let result = await AmenSyncModerationService.shared.moderate(
            caption: caption,
            title: title,
            overlayTexts: [scriptureRef],
            tags: tags
        )
        isModerating = false
        moderationStatus = result.passed ? .approved : (result.blocked ? .rejected : .flagged)

        if moderationStatus == .flagged || moderationStatus == .rejected {
            showModerationSheet = true
        }

        // Update Firestore
        if let projectId = project?.id {
            do {
                try await db.collection("amenSyncProjects").document(projectId).updateData([
                    "moderationStatus": moderationStatus.rawValue,
                    "moderationScore": result.score,
                ])
            } catch {
                print("AmenSyncViewModel: failed to update moderation status — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Publish

    func publish(selectedVariants: [AmenSyncVariant]) async {
        guard let projectId = project?.id else { return }
        isPublishing = true

        var results: [String: SyncPlatformResult] = [:]
        var successCount = 0

        for variant in selectedVariants {
            // For AMEN native publish, post directly
            if variant.platform == .amenFeed {
                do {
                    try await publishToAmenFeed(variant: variant)
                    results[variant.platform.rawValue] = SyncPlatformResult(
                        platform: variant.platform.rawValue,
                        success: true, postURL: nil,
                        errorMessage: nil, publishedAt: Date()
                    )
                    successCount += 1
                } catch {
                    results[variant.platform.rawValue] = SyncPlatformResult(
                        platform: variant.platform.rawValue,
                        success: false, postURL: nil,
                        errorMessage: error.localizedDescription, publishedAt: nil
                    )
                }
            } else {
                // For other platforms — package for export/share
                results[variant.platform.rawValue] = SyncPlatformResult(
                    platform: variant.platform.rawValue,
                    success: true, postURL: nil,
                    errorMessage: nil, publishedAt: Date()
                )
                successCount += 1
            }
        }

        // Update project
        let summary = SyncPublishSummary(
            totalPlatforms: selectedVariants.count,
            successCount: successCount,
            failedCount: selectedVariants.count - successCount,
            platformResults: results
        )

        do {
            try await db.collection("amenSyncProjects").document(projectId).updateData([
                "status": "published",
                "publishedAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            print("AmenSyncViewModel: failed to mark project published — \(error.localizedDescription)")
        }

        projectState = .published
        isPublishing = false
    }

    private func publishToAmenFeed(variant: AmenSyncVariant) async throws {
        guard let uid else { return }
        let postData: [String: Any] = [
            "authorId":      uid,
            "text":          variant.caption,
            "imageURLs":     [variant.mediaURL ?? ""].filter { !$0.isEmpty },
            "postType":      "sync",
            "tags":          tags,
            "scriptureRef":  scriptureRef,
            "createdAt":     FieldValue.serverTimestamp(),
            "syncProjectId": project?.id ?? "",
        ]
        try await db.collection("posts").addDocument(data: postData)
    }

    // MARK: - Helpers

    private func generatePlatformCaption(for platform: SyncPlatform) -> String {
        let base = caption.isEmpty ? "Sharing something meaningful today." : caption
        let maxLen = platform.maxCaptionLength

        if base.count <= maxLen { return base }
        let truncated = String(base.prefix(maxLen - 3)) + "..."
        return truncated
    }

    private func generateHashtags() -> [String] {
        var tags: [String] = ["faith", "amen", "blessed"]
        if !scriptureRef.isEmpty { tags.append("scripture") }
        return tags
    }

    private func updateProjectMeta(projectId: String) async {
        do {
            try await db.collection("amenSyncProjects").document(projectId).updateData([
                "title":            title.isEmpty ? "Untitled" : title,
                "description":      caption,
                "selectedPlatforms": Array(selectedDestinations).map { $0.rawValue },
                "tags":             tags,
                "scriptureRef":     scriptureRef,
                "status":           "processing",
                "updatedAt":        FieldValue.serverTimestamp(),
            ])
        } catch {
            print("AmenSyncViewModel: failed to update project meta — \(error.localizedDescription)")
        }
    }

    // MARK: - Platform Selection

    func togglePlatform(_ platform: SyncPlatform) {
        if selectedDestinations.contains(platform) {
            selectedDestinations.remove(platform)
        } else {
            selectedDestinations.insert(platform)
        }
    }

    func updateVariantCaption(_ variantId: String?, caption: String) {
        guard let id = variantId,
              let idx = variants.firstIndex(where: { $0.id == id }) else { return }
        variants[idx].caption = caption
        Task {
            do {
                try await db.collection("amenSyncVariants").document(id).updateData(["caption": caption])
            } catch {
                print("AmenSyncViewModel: failed to update variant caption — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        projectListener?.remove()
        variantsListener?.remove()
        jobsListener?.remove()
        captionTask?.cancel()
    }

    deinit {
        projectListener?.remove()
        variantsListener?.remove()
        jobsListener?.remove()
    }
}

// MARK: - Project Asset Model

struct AmenSyncProjectAsset: Identifiable, Codable {
    @DocumentID var id: String?
    var projectId: String
    var authorId: String
    var type: SyncMediaType
    var remoteURL: String?
    var thumbnailURL: String?
    var duration: Double?
    var width: Int?
    var height: Int?
    var uploadedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, projectId, authorId, type, remoteURL, thumbnailURL, duration, width, height, uploadedAt
    }
}

// MARK: - Moderation Result

struct SyncModerationResult {
    let passed: Bool
    let blocked: Bool
    let score: Double
    let notes: [String]
}
