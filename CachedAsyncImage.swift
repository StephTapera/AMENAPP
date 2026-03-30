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
        guard let url = url else { return }
        guard !isLoading else { return }

        let urlString = url.absoluteString

        // Check cache first — instant return, no network needed
        if let cachedImage = ProfileImageCache.shared.image(for: urlString) {
            loadedImage = cachedImage
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }

            // PERF: Decode UIImage off the main thread to avoid hitch during scroll.
            // Task.detached escapes @MainActor; we hop back via MainActor.run to assign.
            let image: Image? = await Task.detached(priority: .userInitiated) {
                #if os(iOS)
                guard let uiImage = UIImage(data: data) else { return nil }
                // UIImage(data:) decompresses lazily — force decode now on background thread
                // by drawing into a graphics context so the main thread never stalls.
                let size = uiImage.size
                guard size.width > 0, size.height > 0 else { return Image(uiImage: uiImage) }
                let format = UIGraphicsImageRendererFormat()
                format.scale = uiImage.scale
                let decoded = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    uiImage.draw(at: .zero)
                }
                return Image(uiImage: decoded)
                #elseif os(macOS)
                guard let nsImage = NSImage(data: data) else { return nil }
                return Image(nsImage: nsImage)
                #endif
            }.value

            guard !Task.isCancelled, let image else { return }

            // Back on @MainActor — assign and cache
            loadedImage = image
            ProfileImageCache.shared.setImage(image, for: urlString)
        } catch {
            // Cancelled or network error — silently ignore
        }
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

