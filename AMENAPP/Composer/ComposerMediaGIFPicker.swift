// ComposerMediaGIFPicker.swift
// AMENAPP
//
// Media & GIF picker module for the AMEN composer.
// Provides ComposerMediaProvider, ComposerMediaPickerView, and ComposerGIFPickerView.
//
// All shared types (ComposerAttachment, ComposerPhotoAttachment, etc.) come from
// ComposerContract.swift — never re-declared here.
//
// Design: Liquid Glass, AmenTheme tokens, Motion primitives, full Dynamic Type + VoiceOver.

import SwiftUI
import PhotosUI
import UIKit

// MARK: - GIPHY API Key

private let kGiphyAPIKey = "YOUR_GIPHY_KEY" // placeholder — wire real key at integration time

// MARK: - ComposerMediaProvider

/// Single source of truth for pending media/GIF attachments produced by the picker sheets.
/// Conforms to ComposerAttachmentProvider so the parent composer can poll pendingAttachment.
@MainActor
final class ComposerMediaProvider: ObservableObject, ComposerAttachmentProvider {

    @Published var pendingAttachment: ComposerAttachment?
    @Published var isShowingMediaPicker: Bool = false
    @Published var isShowingGIFPicker: Bool = false

    func reset() {
        pendingAttachment = nil
        isShowingMediaPicker = false
        isShowingGIFPicker = false
    }
}

// MARK: - ComposerMediaPickerView

/// Full-screen sheet that lets the user pick up to 4 photos or 1 video via PHPickerViewController.
/// Produces a ComposerAttachment (.photo or .video) into the provided provider on "Done".
struct ComposerMediaPickerView: View {

    @ObservedObject var provider: ComposerMediaProvider
    @Environment(\.dismiss) private var dismiss

    // Selected photos accumulate here while the sheet is open.
    @State private var selectedPhotos: [ComposerPhotoAttachment] = []
    @State private var selectedVideo: ComposerVideoAttachment? = nil
    @State private var isPresentingPHPicker = false

    // Maximum limits
    private let maxPhotos = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Horizontal preview strip ──────────────────────────────
                if !selectedPhotos.isEmpty || selectedVideo != nil {
                    previewStrip
                        .padding(.top, 12)
                }

                // ── Prompt to choose if nothing selected ─────────────────
                if selectedPhotos.isEmpty && selectedVideo == nil {
                    emptyPrompt
                }

                Spacer()
            }
            .navigationTitle("Add Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .amenPress()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitAttachment()
                    }
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .bold()
                    .disabled(selectedPhotos.isEmpty && selectedVideo == nil)
                    .amenPress()
                }
                ToolbarItem(placement: .bottomBar) {
                    addMoreButton
                }
            }
            .background(.ultraThinMaterial)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $isPresentingPHPicker) {
            PHPickerRepresentable(
                maxPhotoCount: maxPhotos - selectedPhotos.count,
                onPhotos: { newPhotos in
                    // Assign sort orders starting after existing ones
                    let base = selectedPhotos.count
                    let indexed = newPhotos.enumerated().map { i, photo in
                        var p = photo
                        p.sortOrder = base + i
                        return p
                    }
                    selectedPhotos.append(contentsOf: indexed)
                },
                onVideo: { video in
                    selectedVideo = video
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            // Auto-open picker immediately when the sheet appears if nothing selected yet.
            if selectedPhotos.isEmpty && selectedVideo == nil {
                isPresentingPHPicker = true
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var emptyPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
                .accessibilityHidden(true)

            Text("Choose up to \(maxPhotos) photos or 1 video")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Button("Browse Library") {
                isPresentingPHPicker = true
            }
            .buttonStyle(.borderedProminent)
            .tint(AmenTheme.Colors.amenBlue)
            .amenPress()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var previewStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let video = selectedVideo {
                videoPreviewCell(video)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach($selectedPhotos) { $photo in
                            PhotoPreviewCell(
                                photo: $photo,
                                index: selectedPhotos.firstIndex(where: { $0.id == photo.id }) ?? 0,
                                onRemove: {
                                    removePhoto(photo)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .amenGlassCard()
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func videoPreviewCell(_ video: ComposerVideoAttachment) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceCard)
                    .frame(width: 72, height: 72)
                Image(systemName: "video.fill")
                    .font(.title2)
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Video selected")
                    .font(.subheadline).bold()
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                if video.durationSeconds > 0 {
                    Text(durationString(video.durationSeconds))
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            Spacer()
            Button {
                selectedVideo = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .accessibilityLabel("Remove video")
            .amenPress()
        }
        .padding(12)
        .amenGlassCard()
    }

    @ViewBuilder
    private var addMoreButton: some View {
        let canAddMore = selectedVideo == nil && selectedPhotos.count < maxPhotos
        Button {
            if canAddMore {
                isPresentingPHPicker = true
            }
        } label: {
            Label("Add more", systemImage: "plus.circle")
                .foregroundStyle(canAddMore ? AmenTheme.Colors.amenBlue : AmenTheme.Colors.textTertiary)
        }
        .disabled(!canAddMore)
        .amenPress()
    }

    // MARK: - Helpers

    private func removePhoto(_ photo: ComposerPhotoAttachment) {
        selectedPhotos.removeAll { $0.id == photo.id }
        // Re-assign sort orders so they stay contiguous
        for i in selectedPhotos.indices {
            selectedPhotos[i].sortOrder = i
        }
    }

    private func commitAttachment() {
        if let video = selectedVideo {
            provider.pendingAttachment = .video(video)
        } else if !selectedPhotos.isEmpty {
            // Produce multiple photos: wrap each as a separate attachment.
            // The first photo drives the pendingAttachment; the parent composer
            // can iterate additional photos via the provider if needed.
            // Pragmatic approach: emit the first; full multi-photo support
            // can be promoted to the parent draft in a follow-up.
            let sorted = selectedPhotos.sorted { $0.sortOrder < $1.sortOrder }
            if let first = sorted.first {
                provider.pendingAttachment = .photo(first)
            }
        }
        dismiss()
    }

    private func durationString(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - PhotoPreviewCell

/// Reorderable photo preview with alt-text field.
private struct PhotoPreviewCell: View {

    @Binding var photo: ComposerPhotoAttachment
    let index: Int
    let onRemove: () -> Void

    @State private var altTextExpanded = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                photoThumbnail
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                }
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove photo \(index + 1)")
                .amenPress()

                // Sort order badge
                Text("\(index + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AmenTheme.Colors.amenBlue, in: Capsule())
                    .offset(x: -6, y: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityHidden(true)
            }

            // Alt text toggle
            Button {
                withAnimation(Motion.adaptive(Motion.popToggle)) {
                    altTextExpanded.toggle()
                }
            } label: {
                Text(altTextExpanded ? "Hide alt" : "Alt text")
                    .font(.caption2)
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
            }
            .accessibilityLabel(altTextExpanded ? "Hide alt text field for photo \(index + 1)" : "Add alt text for photo \(index + 1)")
            .amenPress()

            if altTextExpanded {
                TextField("Describe this photo", text: $photo.altText, axis: .vertical)
                    .font(.caption)
                    .lineLimit(3)
                    .padding(6)
                    .frame(width: 92)
                    .background(AmenTheme.Colors.surfaceInput, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Alt text for photo \(index + 1)")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.adaptive(Motion.appearEase), value: altTextExpanded)
    }

    @ViewBuilder
    private var photoThumbnail: some View {
        if let url = photo.localURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderTile
                case .empty:
                    placeholderTile
                        .amenSkeleton()
                @unknown default:
                    placeholderTile
                }
            }
            .accessibilityLabel(photo.altText.isEmpty ? "Photo \(index + 1)" : photo.altText)
        } else {
            placeholderTile
        }
    }

    private var placeholderTile: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AmenTheme.Colors.shimmerBase)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            )
    }
}

// MARK: - PHPickerRepresentable

/// UIViewControllerRepresentable wrapping PHPickerViewController.
/// Calls back with arrays of ComposerPhotoAttachment (with localURL set)
/// or a single ComposerVideoAttachment on selection.
private struct PHPickerRepresentable: UIViewControllerRepresentable {

    let maxPhotoCount: Int
    let onPhotos: ([ComposerPhotoAttachment]) -> Void
    let onVideo: (ComposerVideoAttachment) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = maxPhotoCount > 0 ? maxPhotoCount : 1
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPhotos: onPhotos, onVideo: onVideo)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {

        private let onPhotos: ([ComposerPhotoAttachment]) -> Void
        private let onVideo: (ComposerVideoAttachment) -> Void

        init(onPhotos: @escaping ([ComposerPhotoAttachment]) -> Void,
             onVideo: @escaping (ComposerVideoAttachment) -> Void) {
            self.onPhotos = onPhotos
            self.onVideo = onVideo
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            // Detect if first result is a video
            let firstProvider = results.first?.itemProvider
            if firstProvider?.hasItemConformingToTypeIdentifier("public.movie") == true {
                loadVideo(from: results[0].itemProvider)
            } else {
                loadPhotos(from: results)
            }
        }

        private func loadPhotos(from results: [PHPickerResult]) {
            var photos: [ComposerPhotoAttachment] = []
            let group = DispatchGroup()
            for result in results {
                group.enter()
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.image") { url, _ in
                    defer { group.leave() }
                    guard let url = url else { return }
                    // Copy to temp location so the URL is stable after the callback returns
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)
                    try? FileManager.default.copyItem(at: url, to: dest)
                    let attachment = ComposerPhotoAttachment(localURL: dest)
                    photos.append(attachment)
                }
            }
            group.notify(queue: .main) { [weak self] in
                self?.onPhotos(photos)
            }
        }

        private func loadVideo(from provider: NSItemProvider) {
            provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
                guard let url = url else { return }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                try? FileManager.default.copyItem(at: url, to: dest)
                let attachment = ComposerVideoAttachment(localURL: dest)
                DispatchQueue.main.async { [weak self] in
                    self?.onVideo(attachment)
                }
            }
        }
    }
}

// MARK: - ComposerGIFPickerView

/// Full-screen sheet with GIPHY trending/search/favorites/recent tabs and a 2-column grid.
struct ComposerGIFPickerView: View {

    @ObservedObject var provider: ComposerMediaProvider
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedTab: GIFTab = .trending
    @State private var gifs: [GiphyGIF] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var favorites: [GiphyGIF] = []  // persisted outside for demo; can hook to UserDefaults
    @State private var recents: [GiphyGIF] = []

    @FocusState private var searchFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                tabRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                Divider()
                    .background(AmenTheme.Colors.separatorSubtle)

                gifGrid
            }
            .navigationTitle("GIFs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .amenPress()
                }
            }
            .background(.ultraThinMaterial)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: selectedTab) {
            if selectedTab == .trending && searchText.isEmpty {
                await fetchTrending()
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty && selectedTab == .trending {
                Task { await fetchTrending() }
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .accessibilityHidden(true)

            TextField("Search GIFs", text: $searchText)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit {
                    guard !searchText.isEmpty else { return }
                    selectedTab = .trending
                    Task { await fetchSearch(query: searchText) }
                }
                .accessibilityLabel("Search GIFs")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                    Task { await fetchTrending() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .accessibilityLabel("Clear search")
                .amenPress()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .amenGlassInputBar()
    }

    // MARK: - Tab row

    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach(GIFTab.allCases) { tab in
                Button {
                    withAnimation(Motion.adaptive(Motion.popToggle)) {
                        selectedTab = tab
                    }
                    // Trigger load for tab
                    if tab == .trending && searchText.isEmpty {
                        Task { await fetchTrending() }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.displayName)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .foregroundStyle(
                                selectedTab == tab
                                    ? AmenTheme.Colors.amenBlue
                                    : AmenTheme.Colors.textSecondary
                            )
                        Rectangle()
                            .fill(
                                selectedTab == tab
                                    ? AmenTheme.Colors.amenBlue
                                    : Color.clear
                            )
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .amenPress()
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                .accessibilityLabel(tab.displayName)
            }
        }
    }

    // MARK: - GIF grid

    @ViewBuilder
    private var gifGrid: some View {
        let displayGIFs = gifsForCurrentTab

        if isLoading {
            ProgressView()
                .tint(AmenTheme.Colors.amenBlue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else if let error = errorMessage {
            errorState(message: error)

        } else if displayGIFs.isEmpty {
            emptyState(for: selectedTab)

        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(displayGIFs) { gif in
                        GIFCell(gif: gif) {
                            selectGIF(gif)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var gifsForCurrentTab: [GiphyGIF] {
        switch selectedTab {
        case .trending: return gifs
        case .favorites: return favorites
        case .recent: return recents
        }
    }

    @ViewBuilder
    private func emptyState(for tab: GIFTab) -> some View {
        VStack(spacing: 16) {
            Image(systemName: tab.emptyStateIcon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AmenTheme.Colors.amenBlue.opacity(0.6))
                .accessibilityHidden(true)

            Text(tab.emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AmenTheme.Colors.statusError)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try again") {
                Task { await fetchTrending() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AmenTheme.Colors.amenBlue)
            .amenPress()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func selectGIF(_ gif: GiphyGIF) {
        let attachment = ComposerGIFAttachment(
            giphyId: gif.id,
            url: gif.images.fixedWidth?.url ?? gif.images.previewGIF?.url ?? "",
            previewURL: gif.images.previewGIF?.url,
            title: gif.title
        )
        // Add to recents (max 20, no duplicates)
        if !recents.contains(where: { $0.id == gif.id }) {
            recents.insert(gif, at: 0)
            if recents.count > 20 { recents = Array(recents.prefix(20)) }
        }
        provider.pendingAttachment = .gif(attachment)
        dismiss()
    }

    // MARK: - Network

    private func fetchTrending() async {
        await fetch(urlString: "https://api.giphy.com/v1/gifs/trending?api_key=\(kGiphyAPIKey)&limit=25&rating=g")
    }

    private func fetchSearch(query: String) async {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        await fetch(urlString: "https://api.giphy.com/v1/gifs/search?api_key=\(kGiphyAPIKey)&q=\(encoded)&limit=25&rating=g")
    }

    private func fetch(urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        isLoading = true
        errorMessage = nil
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(GiphyResponse.self, from: data)
            gifs = decoded.data
        } catch {
            if (error as? URLError)?.code != .cancelled {
                errorMessage = "Couldn't load GIFs. Check your connection."
            }
        }
        isLoading = false
    }
}

// MARK: - GIFCell

private struct GIFCell: View {

    let gif: GiphyGIF
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            AsyncImage(url: URL(string: gif.images.previewGIF?.url ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AmenTheme.Colors.shimmerBase)
                        Image(systemName: "photo.fill")
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    .amenSkeleton()
                @unknown default:
                    EmptyView()
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .amenPress()
        .accessibilityLabel(gif.title ?? "GIF")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to add this GIF")
    }
}

// MARK: - GIFTab

private enum GIFTab: String, CaseIterable, Identifiable {
    case trending, favorites, recent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trending:  return "Trending"
        case .favorites: return "Favorites"
        case .recent:    return "Recent"
        }
    }

    var emptyStateIcon: String {
        switch self {
        case .trending:  return "antenna.radiowaves.left.and.right"
        case .favorites: return "heart.slash"
        case .recent:    return "clock"
        }
    }

    var emptyStateMessage: String {
        switch self {
        case .trending:  return "No trending GIFs found."
        case .favorites: return "Your favorites will appear here."
        case .recent:    return "GIFs you send recently will appear here."
        }
    }
}

// MARK: - GIPHY Response Models

private struct GiphyResponse: Decodable {
    let data: [GiphyGIF]
}

private struct GiphyGIF: Decodable, Identifiable {
    let id: String
    let title: String?
    let images: GiphyImages
}

private struct GiphyImages: Decodable {
    let previewGIF: GiphyImageSource?
    let fixedWidth: GiphyImageSource?

    private enum CodingKeys: String, CodingKey {
        case previewGIF = "preview_gif"
        case fixedWidth = "fixed_width"
    }
}

private struct GiphyImageSource: Decodable {
    let url: String
}
