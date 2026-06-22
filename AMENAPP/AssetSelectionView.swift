// AssetSelectionView.swift
// AMEN Creator — Asset Selection
// Photo/video picker with multi-selection

import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - Asset Picker Wrapper

struct AssetPickerButton: View {
    @ObservedObject var vm: SceneBuilderViewModel
    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var isLoading = false

    var body: some View {
        PhotosPicker(
            selection: $photosPickerItems,
            maxSelectionCount: 10,
            matching: .any(of: [.images, .videos])
        ) {
            HStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.systemScaled(18))
                Text("Add Media")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .onChange(of: photosPickerItems) { _, items in
            guard !items.isEmpty else { return }
            isLoading = true
            Task {
                var loaded: [CreationAsset] = []
                for item in items {
                    if let asset = await loadAsset(from: item) {
                        loaded.append(asset)
                    }
                }
                vm.addAssets(loaded)
                photosPickerItems = []
                isLoading = false
            }
        }
    }

    private func loadAsset(from item: PhotosPickerItem) async -> CreationAsset? {
        let assetId = UUID().uuidString

        // Try video first
        if let movie = try? await item.loadTransferable(type: VideoAssetTransferable.self) {
            return CreationAsset(
                id: assetId,
                type: .video,
                localURL: movie.url.absoluteString,
                remoteURL: nil,
                thumbnailURL: nil,
                duration: await extractVideoDuration(url: movie.url),
                width: nil,
                height: nil,
                createdAt: Date()
            )
        }

        // Try image
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            // Save to temp file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(assetId).jpg")
            if let compressed = image.jpegData(compressionQuality: 0.75) {
                try? compressed.write(to: tempURL)
            }
            return CreationAsset(
                id: assetId,
                type: .image,
                localURL: tempURL.absoluteString,
                remoteURL: nil,
                thumbnailURL: nil,
                duration: nil,
                width: Int(image.size.width),
                height: Int(image.size.height),
                createdAt: Date()
            )
        }
        return nil
    }

    private func extractVideoDuration(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        return duration.map { CMTimeGetSeconds($0) }
    }
}

// MARK: - Video Transferable

struct VideoAssetTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(received.file.lastPathComponent)
            try? FileManager.default.copyItem(at: received.file, to: dest)
            return VideoAssetTransferable(url: dest)
        }
    }
}

// MARK: - Asset Grid

struct AssetGridView: View {
    @ObservedObject var vm: SceneBuilderViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Media (\(vm.selectedAssets.count))")
                    .font(.custom("OpenSans-Bold", size: 15))
                Spacer()
                AssetPickerButton(vm: vm)
            }
            .padding(.horizontal, 20)

            if vm.selectedAssets.isEmpty {
                emptyAssetsState
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(vm.selectedAssets) { asset in
                        AssetThumbnailCard(asset: asset) {
                            vm.removeAsset(asset)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var emptyAssetsState: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                ForEach(["photo.fill", "video.fill", "book.fill"], id: \.self) { icon in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.gray.opacity(0.07))
                        Image(systemName: icon)
                            .font(.systemScaled(22))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 80)
                }
            }
            .padding(.horizontal, 20)

            Text("Add photos or videos to get started")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Asset Thumbnail

struct AssetThumbnailCard: View {
    let asset: CreationAsset
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Group {
                        if let localPath = asset.localURL,
                           let url = URL(string: localPath),
                           asset.type == .image {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: asset.type == .video ? "video.fill" : "photo.fill")
                                    .font(.systemScaled(22))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Image(systemName: asset.type == .video ? "video.fill" : "photo.fill")
                                .font(.systemScaled(22))
                                .foregroundStyle(.secondary)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Video badge
            if asset.type == .video, let dur = asset.duration {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(DurationBadge(seconds: dur).label)
                            .font(.custom("OpenSans-Bold", size: 10))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .padding(6)
                    }
                }
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.systemScaled(20))
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .padding(6)
        }
    }
}
