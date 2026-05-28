//
//  CachedAsyncImage.swift
//  AMENAPP
//
//  Performant async image loading with in-memory caching
//  Uses existing ImageCache for efficient memory management
//

import SwiftUI

// MARK: - Cached Async Image

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let size: CGSize
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var hasFailed = false
    
    init(
        url: URL?,
        size: CGSize = CGSize(width: 600, height: 600),
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.size = size
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = loadedImage {
                content(Image(uiImage: image))
                    .transition(.opacity)
            } else if hasFailed || url == nil {
                placeholder()
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary.opacity(0.3))
                    )
            } else {
                placeholder()
                    .overlay(AMENLoader.inline.accessibilityLabel("Loading image"))
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard !isLoading, let url = url else { return }
        
        await MainActor.run {
            isLoading = true
            hasFailed = false
        }
        
        // Use existing ImageCache
        if let image = await ImageCache.shared.loadImage(url: url.absoluteString, size: size) {
            await MainActor.run {
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.25)) {
                    loadedImage = image
                }
                isLoading = false
            }
        } else {
            await MainActor.run {
                isLoading = false
                hasFailed = true
            }
        }
    }
}

// MARK: - Convenience Initializer

extension CachedAsyncImage where Placeholder == Color {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            url: url,
            content: content,
            placeholder: { Color(.systemGray6) }
        )
    }
}
