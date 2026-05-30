// ComposerGIFPickerSheet.swift
// AMENAPP / SocialLayer
//
// Bottom-sheet GIF search powered by Giphy public beta API.
// API key is read from Bundle via GIPHY_API_KEY in Config.xcconfig.
//
// INTEGRATION NOTE (Phase 4 — CreatePostView.swift):
// --------------------------------------------------
// 1. Add state:
//      @State private var showGIFPicker = false
//
// 2. Add toolbar button (inside attachmentToolbar or bottom bar):
//      Button { showGIFPicker = true } label: {
//          Image(systemName: "photo.on.rectangle.angled")
//              .accessibilityLabel("Add GIF")
//      }
//
// 3. Add sheet modifier to the view:
//      .sheet(isPresented: $showGIFPicker) {
//          ComposerGIFPickerSheet { gif in
//              draft.attachments.append(.gif(gif))
//              showGIFPicker = false
//          }
//      }
//
// The onSelect closure receives a ComposerGIFAttachment — append it to your
// draft's attachments array as .gif(gif). No other wiring is required.

import SwiftUI
import Combine

// MARK: - Giphy API Models

private struct GiphySearchResponse: Decodable {
    let data: [GiphyItem]
}

private struct GiphyTrendingResponse: Decodable {
    let data: [GiphyItem]
}

private struct GiphyItem: Decodable, Identifiable {
    let id: String
    let title: String?
    let images: GiphyImages
}

private struct GiphyImages: Decodable {
    let original: GiphyImageData
    let fixed_height_small: GiphyImageData
}

private struct GiphyImageData: Decodable {
    let url: String
    let width: String?
    let height: String?
}

// MARK: - GIF Tab

private enum GIFTab: String, CaseIterable, Identifiable {
    case trending = "Trending"
    case favorites = "Favorites"
    case recent = "Recent"
    var id: String { rawValue }
}

// MARK: - ViewModel

@MainActor
private final class GIFPickerViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [GiphyItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var selectedTab: GIFTab = .trending

    // Persisted per-session recents and favorites
    @Published var recentGIFs: [ComposerGIFAttachment] = []
    @Published var favoriteGIFs: [ComposerGIFAttachment] = []

    private var searchTask: Task<Void, Never>?
    private var debounceTimer: AnyCancellable?

    private var apiKey: String {
        Bundle.main.infoDictionary?["GIPHY_API_KEY"] as? String ?? ""
    }

    // MARK: Query Debounce

    func onQueryChanged(_ newValue: String) {
        debounceTimer?.cancel()
        if newValue.isEmpty {
            loadTrending()
            return
        }
        debounceTimer = Just(newValue)
            .delay(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] q in
                self?.performSearch(query: q)
            }
    }

    // MARK: Trending

    func loadTrending() {
        guard !apiKey.isEmpty else {
            errorMessage = "Giphy API key not configured."
            return
        }
        let urlString = "https://api.giphy.com/v1/gifs/trending?api_key=\(apiKey)&limit=25"
        guard let url = URL(string: urlString) else { return }
        isLoading = true
        errorMessage = nil
        searchTask?.cancel()
        searchTask = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(GiphyTrendingResponse.self, from: data)
                if !Task.isCancelled {
                    results = decoded.data
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Couldn't load GIFs. Check your connection."
                }
            }
            isLoading = false
        }
    }

    // MARK: Search

    func performSearch(query: String) {
        guard !apiKey.isEmpty else {
            errorMessage = "Giphy API key not configured."
            return
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.giphy.com/v1/gifs/search?api_key=\(apiKey)&q=\(encoded)&limit=25"
        guard let url = URL(string: urlString) else { return }
        isLoading = true
        errorMessage = nil
        searchTask?.cancel()
        searchTask = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(GiphySearchResponse.self, from: data)
                if !Task.isCancelled {
                    results = decoded.data
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Search failed. Try again."
                }
            }
            isLoading = false
        }
    }

    // MARK: Attach

    func recordRecent(_ gif: ComposerGIFAttachment) {
        recentGIFs.removeAll { $0.giphyId == gif.giphyId }
        recentGIFs.insert(gif, at: 0)
        if recentGIFs.count > 20 { recentGIFs.removeLast() }
    }

    // MARK: Display items for current tab

    func displayItems(from results: [GiphyItem]) -> [GiphyItem] {
        switch selectedTab {
        case .trending, .favorites, .recent:
            // Trending and search results are always the main `results` list.
            // Favorites and Recents use stored ComposerGIFAttachment — handled separately.
            return results
        }
    }
}

// MARK: - ComposerGIFPickerSheet

struct ComposerGIFPickerSheet: View {
    var onSelect: (ComposerGIFAttachment) -> Void

    @StateObject private var vm = GIFPickerViewModel()
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Tab pills
                tabPills
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                Divider()
                    .background(AmenTheme.Colors.separatorSubtle)

                // Content
                contentArea
            }
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle("GIFs")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(32)
        .onAppear {
            withAnimation(Motion.adaptive(Motion.appearEase)) {
                vm.loadTrending()
            }
        }
        .onChange(of: vm.query) { _, newValue in
            vm.onQueryChanged(newValue)
        }
        .onChange(of: vm.selectedTab) { _, _ in
            if vm.query.isEmpty { vm.loadTrending() }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .accessibilityHidden(true)

            TextField("Search GIFs…", text: $vm.query)
                .font(AMENFont.regular(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search GIFs")

            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .amenGlassInputBar(cornerRadius: 12)
    }

    // MARK: - Tab Pills

    private var tabPills: some View {
        HStack(spacing: 8) {
            ForEach(GIFTab.allCases) { tab in
                Button {
                    withAnimation(Motion.adaptive(Motion.springPress)) {
                        vm.selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(AMENFont.medium(13))
                        .foregroundStyle(
                            vm.selectedTab == tab
                                ? AmenTheme.Colors.amenGold
                                : AmenTheme.Colors.textSecondary
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(
                                    vm.selectedTab == tab
                                        ? AmenTheme.Colors.amenGold.opacity(0.14)
                                        : AmenTheme.Colors.surfaceChip
                                )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    vm.selectedTab == tab
                                        ? AmenTheme.Colors.amenGold.opacity(0.35)
                                        : Color.clear,
                                    lineWidth: 0.5
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.rawValue) GIFs")
                .accessibilityAddTraits(vm.selectedTab == tab ? [.isSelected] : [])
                .animation(Motion.adaptive(Motion.springPress), value: vm.selectedTab)
            }
            Spacer()
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        Group {
            switch vm.selectedTab {
            case .trending, .favorites:
                // Trending: use vm.results (loaded on appear / tab switch)
                // Favorites: show stored favorites as shimmer-compatible grid items
                if vm.selectedTab == .favorites {
                    favoritesGrid
                } else {
                    mainGrid(items: vm.results)
                }
            case .recent:
                recentsGrid
            }
        }
    }

    // MARK: - Main Grid (trending / search)

    private func mainGrid(items: [GiphyItem]) -> some View {
        Group {
            if vm.isLoading && items.isEmpty {
                shimmerGrid
            } else if let error = vm.errorMessage, items.isEmpty {
                errorView(message: error)
            } else if items.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(items) { gif in
                            GIFCell(gif: gif) {
                                handleSelect(gif)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Favorites Grid

    private var favoritesGrid: some View {
        Group {
            if vm.favoriteGIFs.isEmpty {
                emptyStateView(
                    icon: "heart.fill",
                    message: "No favorites yet.\nTap and hold a GIF to save it."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(vm.favoriteGIFs) { attachment in
                            StoredGIFCell(attachment: attachment) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                vm.recordRecent(attachment)
                                onSelect(attachment)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Recents Grid

    private var recentsGrid: some View {
        Group {
            if vm.recentGIFs.isEmpty {
                emptyStateView(
                    icon: "clock.fill",
                    message: "GIFs you pick will appear here."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(vm.recentGIFs) { attachment in
                            StoredGIFCell(attachment: attachment) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                vm.recordRecent(attachment)
                                onSelect(attachment)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Shimmer Grid

    private var shimmerGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AmenTheme.Colors.shimmerBase)
                        .frame(height: 100)
                        .amenSkeleton()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Empty / Error States

    private var emptyView: some View {
        emptyStateView(icon: "photo.on.rectangle.angled", message: "No GIFs found.\nTry a different search.")
    }

    private func errorView(message: String) -> some View {
        emptyStateView(icon: "wifi.exclamationmark", message: message)
    }

    private func emptyStateView(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text(message)
                .font(AMENFont.regular(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Select Handler

    private func handleSelect(_ item: GiphyItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let attachment = ComposerGIFAttachment(
            giphyId: item.id,
            url: item.images.original.url,
            previewURL: item.images.fixed_height_small.url,
            title: item.title
        )
        vm.recordRecent(attachment)
        withAnimation(Motion.adaptive(Motion.springRelease)) {
            onSelect(attachment)
        }
    }
}

// MARK: - GIFCell (live GiphyItem — AsyncImage with shimmer)

private struct GIFCell: View {
    let gif: GiphyItem
    let onTap: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            AsyncImage(url: URL(string: gif.images.fixed_height_small.url)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AmenTheme.Colors.shimmerBase)
                        .amenSkeleton()
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity.animation(reduceMotion ? .none : .easeIn(duration: 0.18)))
                case .failure:
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceInput)
                        .overlay(
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                        )
                @unknown default:
                    Color.clear
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
            )
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(Motion.adaptive(Motion.springPress), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(gif.title.map { $0.isEmpty ? "GIF" : $0 } ?? "GIF")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to add this GIF to your post")
    }
}

// MARK: - StoredGIFCell (ComposerGIFAttachment — Recents / Favorites)

private struct StoredGIFCell: View {
    let attachment: ComposerGIFAttachment
    let onTap: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            AsyncImage(url: URL(string: attachment.previewURL ?? attachment.url)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AmenTheme.Colors.shimmerBase)
                        .amenSkeleton()
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity.animation(reduceMotion ? .none : .easeIn(duration: 0.18)))
                case .failure:
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceInput)
                        .overlay(
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                        )
                @unknown default:
                    Color.clear
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
            )
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(Motion.adaptive(Motion.springPress), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(attachment.title.map { $0.isEmpty ? "GIF" : $0 } ?? "GIF")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to add this GIF to your post")
    }
}
