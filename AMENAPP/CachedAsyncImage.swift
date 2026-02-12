//
//  CachedAsyncImage.swift
//  AMENAPP
//
//  Fast loading async image with in-memory caching
//

import SwiftUI

/// Async image with caching for faster loading
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var loadedImage: Image?
    @State private var isLoading = false
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let loadedImage = loadedImage {
                content(loadedImage)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            // Load image when URL changes
            await loadImage()
        }
        .onAppear {
            #if DEBUG
            // Log when CachedAsyncImage appears (DEBUG only)
            if let url = url {
                print("📸 [CACHED-IMAGE] View appeared for URL: \(url.absoluteString.prefix(60))...")
                print("   loadedImage: \(loadedImage != nil ? "✅ LOADED" : "❌ nil")")
                print("   isLoading: \(isLoading)")
            }
            #endif
        }
    }
    
    @MainActor
    private func loadImage() async {
        guard let url = url else {
            return
        }
        
        let urlString = url.absoluteString
        
        // ✅ Check cache first - instant return for cached images
        if let cachedImage = ProfileImageCache.shared.image(for: urlString) {
            #if DEBUG
            print("🎯 [CACHED-IMAGE] Found in cache: \(urlString.prefix(60))...")
            #endif
            loadedImage = cachedImage
            return
        }
        
        #if DEBUG
        print("🌐 [CACHED-IMAGE] Not in cache, loading from network: \(urlString.prefix(60))...")
        #endif
        
        isLoading = true
        
        // ✅ Load from network with proper cancellation handling
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            #if DEBUG
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 [CACHED-IMAGE] HTTP Response: \(httpResponse.statusCode) for \(urlString.prefix(60))...")
                print("   Content-Length: \(data.count) bytes")
            }
            #endif
            
            // ✅ Check if task was cancelled during download
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            
            #if os(iOS)
            if let uiImage = UIImage(data: data) {
                let image = Image(uiImage: uiImage)
                await MainActor.run {
                    loadedImage = image
                }
                #if DEBUG
                print("✅ [CACHED-IMAGE] Successfully loaded and cached: \(urlString.prefix(60))...")
                print("   Image size: \(Int(uiImage.size.width))x\(Int(uiImage.size.height))")
                #endif
                
                // Cache it for next time
                ProfileImageCache.shared.setImage(image, for: urlString)
            } else {
                #if DEBUG
                print("⚠️ [CACHED-IMAGE] Failed to create UIImage from data: \(urlString.prefix(60))...")
                print("   Data size: \(data.count) bytes")
                print("   Data prefix: \(data.prefix(20).map { String(format: "%02x", $0) }.joined())")
                #endif
            }
            #elseif os(macOS)
            if let nsImage = NSImage(data: data) {
                let image = Image(nsImage: nsImage)
                loadedImage = image
                #if DEBUG
                print("✅ [CACHED-IMAGE] Successfully loaded and cached: \(urlString.prefix(60))...")
                #endif
                
                // Cache it for next time
                ProfileImageCache.shared.setImage(image, for: urlString)
            } else {
                #if DEBUG
                print("⚠️ [CACHED-IMAGE] Failed to create NSImage from data: \(urlString.prefix(60))...")
                #endif
            }
            #endif
        } catch {
            // Log errors for debugging profile image loading issues
            #if DEBUG
            if !Task.isCancelled {
                print("❌ [CACHED-IMAGE] Failed to load image from \(url.absoluteString.prefix(80))")
                print("   Error: \(error.localizedDescription)")
            }
            // Cancelled errors are normal during fast scrolling
            #endif
        }
        
        isLoading = false
    }
}

// Convenience initializer for SwiftUI
extension CachedAsyncImage where Content == Image, Placeholder == Color {
    init(url: URL?) {
        self.init(
            url: url,
            content: { $0 },
            placeholder: { Color.gray.opacity(0.2) }
        )
    }
}
