import SwiftUI

import PhotosUI

struct CreatorEditorView: View {
    @StateObject private var viewModel: CreatorEditorViewModel
    @State private var autosaveTask: Task<Void, Never>?
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showImportPicker: Bool = false
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 1
    @State private var coverFrameMs: Int = 0

    init(project: CreatorProject) {
        _viewModel = StateObject(wrappedValue: CreatorEditorViewModel(project: project))
    }

    var body: some View {
        VStack(spacing: 16) {
            CreatorTopBar(title: "Editor", subtitle: "Edit details")

            CreatorGlassCard {
                TextField("Project title", text: $viewModel.project.title)
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(Color.black)
            }

            if let coverURL = viewModel.project.coverImageURL, let url = URL(string: coverURL) {
                CreatorGlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cover")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(Color.black.opacity(0.6))

                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView().tint(.black)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Image(systemName: "photo")
                                    .foregroundStyle(Color.black.opacity(0.4))
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }

            if viewModel.isUploading {
                CreatorProcessingStatusPill(title: viewModel.uploadStatus, progress: viewModel.uploadProgress)
            } else if let activeJob = viewModel.jobs.first(where: { $0.status == .running || $0.status == .queued }) {
                CreatorProcessingStatusPill(title: activeJob.type.rawValue.capitalized, progress: activeJob.progress)
            }

            CreatorGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Canvas")
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(Color.black.opacity(0.6))

                    if let selectedID = viewModel.selectedAssetID,
                       let selectedAsset = viewModel.assets.first(where: { $0.id == selectedID }),
                       let url = URL(string: selectedAsset.thumbnailURL ?? selectedAsset.downloadURL ?? "") {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView().tint(.black)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Image(systemName: "photo")
                                    .foregroundStyle(Color.black.opacity(0.4))
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        Text("Add media to start")
                            .font(AMENFont.medium(13))
                            .foregroundStyle(Color.black.opacity(0.45))
                            .frame(maxWidth: .infinity, minHeight: 240)
                            .background(Color.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }

            if !viewModel.assets.isEmpty {
                CreatorTimelineStripView(assets: viewModel.assets, selectedAssetID: $viewModel.selectedAssetID)

                if let selectedID = viewModel.selectedAssetID,
                   let selectedAsset = viewModel.assets.first(where: { $0.id == selectedID }) {
                    CreatorGlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Timeline")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(Color.black.opacity(0.6))

                            if selectedAsset.type == .video {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Trim in / out")
                                        .font(AMENFont.medium(12))
                                        .foregroundStyle(Color.black.opacity(0.6))

                                    CreatorTimelineGridView(asset: selectedAsset, trimStart: $trimStart, trimEnd: $trimEnd)

                                    Slider(value: $trimStart, in: 0...max(0.01, trimEnd))
                                    Slider(value: $trimEnd, in: trimStart...1)
                                }

                                if let duration = selectedAsset.durationMs,
                                   let urlString = selectedAsset.proxyURL ?? selectedAsset.downloadURL,
                                   let url = URL(string: urlString) {
                                    CreatorCoverFrameScrubber(videoURL: url, durationMs: duration, frameTimeMs: $coverFrameMs) {
                                        Task {
                                            await viewModel.setCover(asset: selectedAsset, frameTimeMs: coverFrameMs)
                                        }
                                    }
                                }
                            }

                            CreatorToolbar {
                                CreatorSecondaryCTA(title: "Set Cover") {
                                    Task {
                                        let frameMs: Int?
                                        if selectedAsset.type == .video, let duration = selectedAsset.durationMs {
                                            frameMs = Int(Double(duration) * trimStart)
                                        } else {
                                            frameMs = nil
                                        }
                                        await viewModel.setCover(asset: selectedAsset, frameTimeMs: frameMs)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            CreatorToolbar {
                CreatorSecondaryCTA(title: "Import") {
                    showImportPicker = true
                }
                CreatorPrimaryCTA(title: "Save") {
                    Task { await viewModel.autosave() }
                }
            }

            CreatorBottomRail(
                primaryActionTitle: "Export",
                secondaryActionTitle: "Publish",
                primaryAction: {},
                secondaryAction: {}
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .task {
            await viewModel.loadAssets()
            viewModel.startJobListener()
            if let assetID = viewModel.selectedAssetID {
                let trim = viewModel.trimValues(for: assetID)
                trimStart = trim.start
                trimEnd = trim.end
                coverFrameMs = viewModel.coverFrameTimeMs
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            let identifiers = newItems.compactMap { $0.itemIdentifier }
            guard !identifiers.isEmpty else { return }
            Task { await viewModel.importMedia(localIdentifiers: identifiers) }
        }
        .onChange(of: viewModel.selectedAssetID) { _, newValue in
            guard let assetID = newValue else { return }
            let trim = viewModel.trimValues(for: assetID)
            trimStart = trim.start
            trimEnd = trim.end
            coverFrameMs = viewModel.coverFrameTimeMs
        }
        .onChange(of: trimStart) { _, newValue in
            guard let assetID = viewModel.selectedAssetID else { return }
            viewModel.updateTrim(for: assetID, start: newValue, end: trimEnd)
        }
        .onChange(of: trimEnd) { _, newValue in
            guard let assetID = viewModel.selectedAssetID else { return }
            viewModel.updateTrim(for: assetID, start: trimStart, end: newValue)
        }
        .onChange(of: viewModel.project) { _, _ in
            autosaveTask?.cancel()
            autosaveTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(CreatorConstants.autosaveDebounceSeconds * 1_000_000_000))
                await viewModel.autosave()
            }
        }
        .photosPicker(
            isPresented: $showImportPicker,
            selection: $selectedItems,
            matching: .any(of: [.images, .videos])
        )
        .background(Color.white)
    }
}
