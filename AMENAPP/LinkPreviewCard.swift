//
//  LinkPreviewCard.swift
//  AMENAPP
//

import SwiftUI
import LinkPresentation
import UIKit

// MARK: - Cache

private enum LinkMetadataCache {
    static let shared = NSCache<NSURL, LPLinkMetadata>()
}

// MARK: - UIViewRepresentable

private struct LPLinkViewRepresentable: UIViewRepresentable {
    let metadata: LPLinkMetadata

    func makeUIView(context: Context) -> LPLinkView {
        let view = LPLinkView(metadata: metadata)
        return view
    }

    func updateUIView(_ uiView: LPLinkView, context: Context) {
        uiView.metadata = metadata
        uiView.sizeToFit()
    }
}

// MARK: - Fallback

private struct LinkFallbackView: View {
    let url: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundColor(.secondary)
            Text(url.host ?? url.absoluteString)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Main View

struct LinkPreviewCard: View {
    let url: URL

    @State private var metadata: LPLinkMetadata? = nil
    @State private var fetchFailed = false

    var body: some View {
        Group {
            if let metadata {
                LPLinkViewRepresentable(metadata: metadata)
            } else {
                LinkFallbackView(url: url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 120)
        .cornerRadius(12)
        .clipped()
        .task(id: url) {
            await fetchMetadata()
        }
    }

    @MainActor
    private func fetchMetadata() async {
        let nsURL = url as NSURL

        if let cached = LinkMetadataCache.shared.object(forKey: nsURL) {
            metadata = cached
            return
        }

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return
        }

        guard !Task.isCancelled else { return }

        let provider = LPMetadataProvider()
        do {
            let fetched = try await provider.startFetchingMetadata(for: url)
            LinkMetadataCache.shared.setObject(fetched, forKey: nsURL)
            metadata = fetched
        } catch {
            fetchFailed = true
        }
    }
}
