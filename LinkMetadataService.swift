
//
//  LinkMetadataService.swift
//  AMENAPP
//
//  Fetches and caches rich link metadata using Apple's LinkPresentation framework.
//  No third-party logos are stored in a way that implies partnership.
//  Metadata is cached in-memory with a 10-minute TTL; not persisted to disk.
//
//  For posts that already have linkPreview* fields in Firestore, those are
//  returned immediately without a network fetch.
//

import Foundation
import SwiftUI
import Combine
import LinkPresentation
import UIKit

// MARK: - LinkCardMetadata
// Note: uses a distinct name to avoid collision with the app-wide LinkPreviewMetadata
// in LinkPreviewService.swift which is a richer Codable model with verse support.

/// Lightweight in-memory snapshot used by LinkCardView and LinkMetadataService.
struct LinkCardMetadata: Equatable {
    let url: URL
    var title: String?
    var description: String?
    var imageURL: URL?
    /// Domain label shown under the card (e.g. "nytimes.com").
    var siteName: String?
    /// The raw LPLinkMetadata — only kept in-memory for rendering LPLinkView.
    var lpMetadata: LPLinkMetadata?

    /// Whether this is a real rich preview or a bare URL fallback.
    var isRich: Bool { title != nil || imageURL != nil }

    /// Domain extracted from URL for display (never implying partnership).
    var displayDomain: String {
        url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }
}

// MARK: - LinkMetadataService

@MainActor
final class LinkMetadataService: ObservableObject {

    static let shared = LinkMetadataService()
    private init() {}

    // MARK: - Cache

    private struct CacheEntry {
        let metadata: LinkCardMetadata
        let expiry: Date
    }

    private var cache: [URL: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 600 // 10 minutes

    // MARK: - Active Fetches (dedupe concurrent requests for same URL)

    private var inFlight: [URL: Task<LinkCardMetadata, Never>] = [:]

    // MARK: - Public API

    /// Fetch metadata for a URL. Returns cached result immediately if fresh.
    /// Falls back to a minimal metadata object if fetch fails.
    func metadata(for url: URL) async -> LinkCardMetadata {
        // URL sanitization: only allow http/https
        guard let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return LinkCardMetadata(url: url)
        }

        // Return cached if fresh
        if let entry = cache[url], entry.expiry > Date() {
            return entry.metadata
        }

        // Dedupe concurrent requests
        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<LinkCardMetadata, Never> {
            let result = await fetchMetadata(url: url)
            await MainActor.run {
                cache[url] = CacheEntry(metadata: result, expiry: Date().addingTimeInterval(cacheTTL))
                inFlight.removeValue(forKey: url)
            }
            return result
        }

        inFlight[url] = task
        return await task.value
    }

    /// Invalidate cache for a URL (e.g. after user edits a post's link).
    func invalidate(url: URL) { cache.removeValue(forKey: url) }

    /// Build a FirestorePost-compatible metadata dict for server storage.
    func firestoreFields(for meta: LinkCardMetadata) -> [String: Any] {
        var d: [String: Any] = [:]
        d["linkURL"] = meta.url.absoluteString
        if let t = meta.title { d["linkPreviewTitle"] = t }
        if let desc = meta.description { d["linkPreviewDescription"] = desc }
        if let img = meta.imageURL { d["linkPreviewImageURL"] = img.absoluteString }
        if let site = meta.siteName { d["linkPreviewSiteName"] = site }
        return d
    }

    // MARK: - Private Fetch

    private func fetchMetadata(url: URL) async -> LinkCardMetadata {
        let provider = LPMetadataProvider()
        provider.timeout = 10
        provider.shouldFetchSubresources = false // Don't fetch sub-assets to keep it fast

        do {
            let lp = try await provider.startFetchingMetadata(for: url)
            var meta = LinkCardMetadata(url: url)
            meta.title = lp.title
            meta.siteName = url.host?.replacingOccurrences(of: "www.", with: "")
            meta.lpMetadata = lp

            // Load image if available (bounded to keep memory use sane)
            if let iconProvider = lp.imageProvider ?? lp.iconProvider {
                meta.imageURL = await loadImageURL(provider: iconProvider)
            }

            return meta
        } catch {
            // Graceful fallback: bare URL card
            return LinkCardMetadata(url: url)
        }
    }

    /// Writes the image to a temp file and returns its URL for AsyncImage.
    private func loadImageURL(provider: NSItemProvider) async -> URL? {
        return await withCheckedContinuation { cont in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.8) else {
                    cont.resume(returning: nil)
                    return
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).jpg")
                try? data.write(to: url)
                cont.resume(returning: url)
            }
        }
    }
}

// MARK: - LinkCardView

/// Rich link preview card for use inside post composers and feed cells.
/// Three states: loading / loaded-rich / loaded-bare / error.
/// Frosted glass pill style matching AMEN's liquid-glass design language.
struct LinkCardView: View {

    let urlString: String
    /// When true, shows a ✕ remove button (used in composer).
    var onRemove: (() -> Void)? = nil

    @StateObject private var vm = LinkCardViewModel()
    @State private var didAppear = false
    @State private var linkSafetySheet: AnyView?
    @State private var showLinkSafety = false

    var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:
                loadingCard
            case .loaded(let meta):
                if meta.isRich {
                    richCard(meta: meta)
                } else {
                    bareCard(url: meta.url)
                }
            case .error:
                bareCard(url: URL(string: urlString))
            }
        }
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            vm.load(urlString: urlString)
        }
        .onChange(of: urlString) { _, newVal in
            didAppear = false
            vm.load(urlString: newVal)
        }
        .animation(.easeInOut(duration: 0.2), value: vm.state.isLoading)
    }

    // MARK: - Loading

    private var loadingCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.15))
                .frame(width: 44, height: 44)
                .linkCardShimmering()

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.15))
                    .frame(height: 12).frame(maxWidth: .infinity).linkCardShimmering()
                RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.10))
                    .frame(height: 10).frame(width: 140).linkCardShimmering()
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12), lineWidth: 0.8))
    }

    // MARK: - Rich Card

    private func richCard(meta: LinkCardMetadata) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let imgURL = meta.imageURL {
                AsyncImage(url: imgURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    default:
                        domainInitialView(meta: meta)
                    }
                }
            } else {
                domainInitialView(meta: meta)
            }

            // Text
            VStack(alignment: .leading, spacing: 3) {
                if let title = meta.title {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                }
                Text(meta.displayDomain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // Remove button (composer only)
            if let remove = onRemove {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.tertiarySystemBackground), in: Circle())
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            if let url = vm.url {
                LinkSafetyServiceCompat.shared.open(url) { sheet in
                    linkSafetySheet = sheet
                    showLinkSafety = true
                }
            }
        }
        .sheet(isPresented: $showLinkSafety) { linkSafetySheet }
    }

    // MARK: - Bare Card (no OG data)

    private func bareCard(url: URL?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(url?.absoluteString ?? urlString)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let remove = onRemove {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.10), lineWidth: 0.8))
    }

    private func domainInitialView(meta: LinkCardMetadata) -> some View {
        let letter = meta.displayDomain.first.map { String($0).uppercased() } ?? "L"
        return Text(letter)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(
                LinearGradient(colors: [.blue.opacity(0.7), .indigo.opacity(0.8)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 8)
            )
    }
}

// MARK: - LinkCardViewModel

@MainActor
final class LinkCardViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded(LinkCardMetadata)
        case error
        var isLoading: Bool { if case .loading = self { return true }; return false }
    }

    @Published var state: State = .idle
    var url: URL? { if case .loaded(let m) = state { return m.url }; return nil }

    private var fetchTask: Task<Void, Never>?

    func load(urlString: String) {
        fetchTask?.cancel()
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            state = .error
            return
        }
        state = .loading
        fetchTask = Task { [weak self] in
            let meta = await LinkMetadataService.shared.metadata(for: url)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.state = .loaded(meta) }
        }
    }
}

// MARK: - Shimmer Modifier (file-private, named to avoid module-level conflicts)

private struct LinkCardShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: phase - 0.3),
                        .init(color: .white.opacity(0.4), location: phase),
                        .init(color: .clear, location: phase + 0.3),
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

private extension View {
    func linkCardShimmering() -> some View { modifier(LinkCardShimmerModifier()) }
}
