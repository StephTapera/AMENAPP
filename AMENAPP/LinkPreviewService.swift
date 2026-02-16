//
//  LinkPreviewService.swift
//  AMENAPP
//
//  Service for fetching and caching link preview metadata
//

import Foundation
import SwiftUI
import LinkPresentation
import Combine

/// Link preview metadata model
struct LinkPreviewMetadata: Codable, Identifiable, Equatable {
    let id: String
    let url: URL
    let title: String?
    let description: String?
    let imageURL: URL?
    let siteName: String?
    
    init(url: URL, title: String? = nil, description: String? = nil, imageURL: URL? = nil, siteName: String? = nil) {
        self.id = url.absoluteString
        self.url = url
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.siteName = siteName
    }
}

/// Link preview service for fetching metadata
class LinkPreviewService: ObservableObject {
    static let shared = LinkPreviewService()
    
    @Published private(set) var cache: [String: LinkPreviewMetadata] = [:]
    @Published private(set) var isLoading: Set<String> = []
    
    private let metadataProvider = LPMetadataProvider()
    private let cacheQueue = DispatchQueue(label: "com.amen.linkpreview.cache")
    
    private init() {
        loadCacheFromDisk()
    }
    
    // MARK: - Public API
    
    /// Detect URLs in text
    func detectURLs(in text: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        return matches?.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let urlString = String(text[range])
            return URL(string: urlString)
        } ?? []
    }
    
    /// Fetch link preview metadata
    func fetchMetadata(for url: URL) async throws -> LinkPreviewMetadata {
        let urlString = url.absoluteString
        
        // Check cache first
        if let cached = cache[urlString] {
            print("📦 Using cached link preview for: \(urlString)")
            return cached
        }
        
        // Check if already loading
        if isLoading.contains(urlString) {
            print("⏳ Already loading: \(urlString)")
            // Wait a bit and check cache again
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            if let cached = cache[urlString] {
                return cached
            }
        }
        
        // Mark as loading
        await MainActor.run {
            isLoading.insert(urlString)
        }
        
        defer {
            Task { @MainActor in
                isLoading.remove(urlString)
            }
        }
        
        do {
            print("🔍 Fetching link preview for: \(urlString)")
            
            let metadata = try await metadataProvider.startFetchingMetadata(for: url)
            
            let preview = LinkPreviewMetadata(
                url: url,
                title: metadata.title,
                description: metadata.url?.absoluteString,
                imageURL: metadata.imageProvider != nil ? url : nil, // Simplified for now
                siteName: metadata.originalURL?.host
            )
            
            // Cache the result
            await MainActor.run {
                cache[urlString] = preview
            }
            
            saveCacheToDisk()
            
            print("✅ Link preview fetched: \(preview.title ?? "No title")")
            
            return preview
        } catch {
            print("❌ Failed to fetch link preview: \(error)")
            throw error
        }
    }
    
    /// Get cached metadata synchronously
    func getCached(for url: URL) -> LinkPreviewMetadata? {
        return cache[url.absoluteString]
    }
    
    /// Clear cache
    func clearCache() {
        cache.removeAll()
        isLoading.removeAll()
        try? FileManager.default.removeItem(at: cacheFileURL)
    }
    
    // MARK: - Disk Caching
    
    private var cacheFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("link_preview_cache.json")
    }
    
    private func loadCacheFromDisk() {
        cacheQueue.async { [weak self] in
            guard let self = self,
                  let data = try? Data(contentsOf: self.cacheFileURL),
                  let decoded = try? JSONDecoder().decode([String: LinkPreviewMetadata].self, from: data) else {
                return
            }
            
            DispatchQueue.main.async {
                self.cache = decoded
                print("📦 Loaded \(decoded.count) link previews from cache")
            }
        }
    }
    
    private func saveCacheToDisk() {
        cacheQueue.async { [weak self] in
            guard let self = self,
                  let data = try? JSONEncoder().encode(self.cache) else {
                return
            }
            
            try? data.write(to: self.cacheFileURL)
            print("💾 Saved \(self.cache.count) link previews to cache")
        }
    }
}

// MARK: - Link Preview Card View

struct LinkPreviewCard: View {
    let metadata: LinkPreviewMetadata
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Small link icon
                Image(systemName: "link")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.6))
                
                // Compact text - just show host/title
                if let title = metadata.title, !title.isEmpty {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.black.opacity(0.7))
                        .lineLimit(1)
                } else if let host = metadata.url.host {
                    Text(host)
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.black.opacity(0.7))
                        .lineLimit(1)
                } else {
                    Text("Link")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.black.opacity(0.7))
                        .lineLimit(1)
                }
                
                // Tiny external arrow
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.black.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                Color(white: 0.95).opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                Color.black.opacity(0.1),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Link Preview Loading View

struct LinkPreviewLoadingView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Loading preview...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.1))
        )
    }
}
