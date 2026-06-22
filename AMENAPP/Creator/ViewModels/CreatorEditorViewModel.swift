import Foundation
import FirebaseFirestore

@MainActor
final class CreatorEditorViewModel: ObservableObject {
    @Published var project: CreatorProject
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?
    @Published var isUploading: Bool = false
    @Published var uploadProgress: Double = 0
    @Published var uploadStatus: String = ""
    @Published var assets: [CreatorAsset] = []
    @Published var jobs: [CreatorProcessingJob] = []
    @Published var scenesByAssetID: [String: CreatorScene] = [:]

    private let autosaveService: CreatorAutosaveServicing
    private let projectService: CreatorProjectServicing
    @Published var selectedAssetID: String?
    @Published var coverFrameTimeMs: Int = 0
    private let mediaImportService: CreatorMediaImportServicing
    private let assetService: CreatorAssetServicing
    private let sceneService: CreatorSceneServicing
    private let jobService: CreatorJobServicing
    private let videoProcessingService: CreatorVideoProcessingServicing
    private var jobListener: ListenerRegistration?
    private var handledJobIDs: Set<String> = []
    private var trimUpdateTask: Task<Void, Never>?

    init(
        project: CreatorProject,
        autosaveService: CreatorAutosaveServicing? = nil,
        projectService: CreatorProjectServicing? = nil,
        mediaImportService: CreatorMediaImportServicing? = nil,
        assetService: CreatorAssetServicing? = nil,
        sceneService: CreatorSceneServicing? = nil,
        jobService: CreatorJobServicing? = nil,
        videoProcessingService: CreatorVideoProcessingServicing? = nil
    ) {
        self.project = project
        self.autosaveService = autosaveService ?? CreatorAutosaveService()
        self.projectService = projectService ?? CreatorProjectService()
        self.mediaImportService = mediaImportService ?? CreatorMediaImportService()
        self.selectedAssetID = nil
        self.coverFrameTimeMs = project.coverFrameTimeMs ?? 0
        self.assetService = assetService ?? CreatorAssetService()
        self.sceneService = sceneService ?? CreatorSceneService()
        self.jobService = jobService ?? CreatorJobService()
        self.videoProcessingService = videoProcessingService ?? CreatorVideoProcessingService()
    }

    deinit {
        jobListener?.remove()
    }

    func loadAssets() async {
        do {
            assets = try await assetService.fetchAssets(projectID: project.id)
            let scenes = try await sceneService.fetchScenes(projectID: project.id)
            scenesByAssetID = Dictionary(uniqueKeysWithValues: scenes.map { ($0.assetID, $0) })
            if selectedAssetID == nil {
                selectedAssetID = assets.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startJobListener() {
        do {
            jobListener = try jobService.listenJobs(projectID: project.id) { [weak self] jobs in
                Task { @MainActor in
                    self?.jobs = jobs
                    self?.handleCompletedJobs(jobs)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func autosave() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await autosaveService.autosave(project: project)
            try await projectService.updateProject(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importMedia(localIdentifiers: [String]) async {
        guard !localIdentifiers.isEmpty else { return }
        isUploading = true
        uploadStatus = "Preparing"
        uploadProgress = 0

        do {
            let imported = try await mediaImportService.importAssets(
                localIdentifiers: localIdentifiers,
                projectID: project.id,
                onProgress: { [weak self] progress, status in
                    Task { @MainActor in
                        self?.uploadProgress = progress
                        self?.uploadStatus = status
                    }
                }
            )

            assets.append(contentsOf: imported)
            for asset in imported {
                if asset.type == .video {
                    _ = try? await videoProcessingService.createProxy(for: asset)
                    _ = try? await videoProcessingService.generateThumbnail(for: asset)
                }
            }

            uploadStatus = "Complete"
            uploadProgress = 1
        } catch {
            errorMessage = error.localizedDescription
        }

        isUploading = false
    }

    private func handleCompletedJobs(_ jobs: [CreatorProcessingJob]) {
        let completed = jobs.filter { $0.status == .completed && !handledJobIDs.contains($0.id) }
        guard !completed.isEmpty else { return }

        for job in completed {
            handledJobIDs.insert(job.id)
            guard let assetID = job.inputRefs.first else { continue }

            Task {
                let output = job.outputRefs.first
                let resolvedOutput: String?
                if let output {
                    resolvedOutput = output
                } else if let storagePath = job.outputStoragePath {
                    resolvedOutput = try? await assetService.resolveDownloadURL(storagePath: storagePath)
                } else {
                    resolvedOutput = nil
                }

                guard let finalOutput = resolvedOutput else { return }

                if job.type == .thumbnail {
                    try? await assetService.updateAsset(assetID: assetID, fields: ["thumbnailURL": finalOutput])
                    if let index = assets.firstIndex(where: { $0.id == assetID }) {
                        assets[index].thumbnailURL = finalOutput
                    }
                } else if job.type == .proxy {
                    try? await assetService.updateAsset(assetID: assetID, fields: ["proxyURL": finalOutput])
                    if let index = assets.firstIndex(where: { $0.id == assetID }) {
                        assets[index].proxyURL = finalOutput
                    }
                }
            }
        }
    }

    func setCover(asset: CreatorAsset, frameTimeMs: Int? = nil) async {
        project.coverAssetID = asset.id
        project.coverImageURL = asset.thumbnailURL ?? asset.downloadURL
        if let frameTimeMs {
            project.coverFrameTimeMs = frameTimeMs
        }
        coverFrameTimeMs = project.coverFrameTimeMs ?? 0
        try? await projectService.updateProject(project)
    }

    func trimValues(for assetID: String) -> (start: Double, end: Double) {
        guard let scene = scenesByAssetID[assetID], let durationMs = assets.first(where: { $0.id == assetID })?.durationMs, durationMs > 0 else {
            return (0, 1)
        }
        let start = Double(scene.startTimeMs ?? 0) / Double(durationMs)
        let end = Double(scene.endTimeMs ?? durationMs) / Double(durationMs)
        return (start, end)
    }

    func updateTrim(for assetID: String, start: Double, end: Double) {
        guard let durationMs = assets.first(where: { $0.id == assetID })?.durationMs, durationMs > 0 else { return }
        let startMs = Int(Double(durationMs) * start)
        let endMs = Int(Double(durationMs) * end)

        if var scene = scenesByAssetID[assetID] {
            scene.startTimeMs = startMs
            scene.endTimeMs = endMs
            scenesByAssetID[assetID] = scene
            trimUpdateTask?.cancel()
            trimUpdateTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                try? await sceneService.updateScene(sceneID: scene.id, fields: [
                    "startTimeMs": startMs,
                    "endTimeMs": endMs
                ])
            }
        }
    }
}
