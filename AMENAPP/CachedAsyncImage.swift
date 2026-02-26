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
        // Image loading handled by task
    }
    
    @MainActor
    private func loadImage() async {
        guard let url = url else {
            return
        }
        
        let urlString = url.absoluteString
        
        // ✅ Check cache first - instant return for cached images
        if let cachedImage = ProfileImageCache.shared.image(for: urlString) {
            loadedImage = cachedImage
            return
        }
        
        isLoading = true
        
        // ✅ Load from network with proper cancellation handling
        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            
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
                
                // Cache it for next time
                ProfileImageCache.shared.setImage(image, for: urlString)
            }
            #elseif os(macOS)
            if let nsImage = NSImage(data: data) {
                let image = Image(nsImage: nsImage)
                loadedImage = image
                
                // Cache it for next time
                ProfileImageCache.shared.setImage(image, for: urlString)
            }
            #endif
        } catch {
            // Silently fail - cancelled errors are normal during fast scrolling
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
