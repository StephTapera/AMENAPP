//
//  LinkPreviewCards.swift
//  AMENAPP
//
//  Threads-style rich link preview and Bible verse card views.
//  Shared by CreatePostView (composer), UnifiedChatView, PostCard (feed).
//
//  Design: AMEN glass / Liquid Glass language — .ultraThinMaterial base,
//  subtle white stroke, no heavy shadows, smooth fade-in on metadata arrival.
//

import SwiftUI
import Combine

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: ComposerLinkPreviewController
// Drives the preview shown while the user is composing.
// Usage:  @StateObject private var linkController = ComposerLinkPreviewController()
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ComposerLinkPreviewController: ObservableObject {

    /// The URL currently being previewed.
    @Published private(set) var activeURL: URL? = nil
    /// Metadata once fetched; nil = still loading.
    @Published private(set) var metadata: LinkPreviewMetadata? = nil
    /// True while the first fetch is in-flight.
    @Published private(set) var isLoading: Bool = false
    /// True if user explicitly dismissed — prevents re-showing same URL.
    private var dismissedURL: URL? = nil

    private var debounceTask: Task<Void, Never>? = nil

    // MARK: Public

    /// Call from onChange(of: postText). Detects first URL, debounces 400ms.
    func handleTextChange(_ text: String) {
        // If we already have a URL locked in, don't override unless text changed
        // enough that the old URL is gone.
        if let current = activeURL, !text.contains(current.absoluteString) {
            clearPreview(cancel: true)
        }

        guard activeURL == nil else { return }  // Already have one — keep it

        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)  // 400 ms
            guard !Task.isCancelled else { return }

            guard let url = LinkPreviewService.shared.detectFirstURL(in: text),
                  url != dismissedURL else { return }

            activeURL = url
            isLoading = true
            metadata = nil

            // Optimistic: check cache first (shows instantly)
            if let cached = LinkPreviewService.shared.getCached(for: url) {
                metadata = cached
                isLoading = false
                return
            }

            do {
                let fetched = try await LinkPreviewService.shared.fetchMetadata(for: url)
                // Guard: URL might have changed during fetch
                guard activeURL == url else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    metadata = fetched
                    isLoading = false
                }
            } catch {
                guard activeURL == url else { return }
                isLoading = false
                // Leave activeURL set so a placeholder card stays visible
            }
        }
    }

    /// User tapped the X button. Permanently hides this URL's preview for
    /// the current composition session.
    func dismissPreview() {
        dismissedURL = activeURL
        clearPreview(cancel: true)
    }

    /// Call on post sent / view dismissed to reset fully.
    func reset() {
        dismissedURL = nil
        clearPreview(cancel: true)
    }

    // MARK: Helpers

    private func clearPreview(cancel: Bool) {
        debounceTask?.cancel()
        debounceTask = nil
        if cancel, let url = activeURL {
            LinkPreviewService.shared.cancelFetch(for: url)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            activeURL = nil
            metadata = nil
            isLoading = false
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: ComposerLinkPreview
// Card shown in the composer while a URL is detected.
// Threads-style: skeleton → loaded with fade, always-visible X.
// ─────────────────────────────────────────────────────────────────────────────

struct ComposerLinkPreview: View {
    @ObservedObject var controller: ComposerLinkPreviewController

    var body: some View {
        if let url = controller.activeURL {
            Group {
                if controller.metadata?.previewType == .verse,
                   let meta = controller.metadata {
                    VersePreviewCard(metadata: meta) {
                        controller.dismissPreview()
                    }
                } else {
                    RichLinkPreviewCard(
                        url: url,
                        metadata: controller.metadata,
                        isLoading: controller.isLoading
                    ) {
                        controller.dismissPreview()
                    }
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: RichLinkPreviewCard
// Threads-style card: thumbnail left | title + domain right | X top-right.
// Used in composer, chat, and feed (pass onRemove: nil for non-editable).
// ─────────────────────────────────────────────────────────────────────────────

struct RichLinkPreviewCard: View {
    let url: URL
    let metadata: LinkPreviewMetadata?
    let isLoading: Bool
    let onRemove: (() -> Void)?

    @State private var linkSafetySheet: AnyView?
    @State private var showLinkSafety = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            LinkSafetyServiceCompat.shared.open(url) { sheet in
                linkSafetySheet = sheet
                showLinkSafety = true
            }
        } label: {
            cardContent
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(alignment: .topTrailing) {
            if let onRemove {
                removeButton(action: onRemove)
            }
        }
        .sheet(isPresented: $showLinkSafety) { linkSafetySheet }
    }

    // MARK: Card layout

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 0) {
            // ── Thumbnail ────────────────────────────────────────────────
            thumbnailView
                .frame(width: 76, height: 76)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 12,
                        bottomLeadingRadius: 12,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )

            // ── Text section ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                if isLoading {
                    skeletonText
                } else {
                    // Domain label
                    if let host = metadata?.siteName ?? url.host {
                        Text(host.lowercased())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    // Title
                    if let title = metadata?.title, !title.isEmpty {
                        Text(title)
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    } else {
                        Text(url.absoluteString)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
        .animation(.easeInOut(duration: 0.25), value: isLoading)
    }

    // MARK: Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if isLoading {
            Rectangle()
                .fill(Color(.systemGray5))
                .overlay(
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.secondary)
                )
                .shimmering()
        } else if let imageURL = metadata?.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure, .empty:
                    linkIconFallback
                @unknown default:
                    linkIconFallback
                }
            }
        } else {
            linkIconFallback
        }
    }

    private var linkIconFallback: some View {
        ZStack {
            Color(.systemGray6)
            Image(systemName: "link")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Skeleton shimmer for loading state

    private var skeletonText: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 60, height: 10)
                .shimmering()
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray4))
                .frame(maxWidth: .infinity)
                .frame(height: 13)
                .shimmering()
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray4))
                .frame(maxWidth: 100)
                .frame(height: 13)
                .shimmering()
        }
    }

    // MARK: Glass background

    private var glassBackground: some View {
        ZStack {
            Color(.systemBackground)
            Color(.secondarySystemBackground).opacity(0.6)
        }
    }

    // MARK: X button

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                action()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 22, height: 22)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: 8, y: -8)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: VersePreviewCard
// Bible verse image-style card. Shown instead of a plain link card when
// a Bible URL is detected.
// ─────────────────────────────────────────────────────────────────────────────

struct VersePreviewCard: View {
    let metadata: LinkPreviewMetadata
    let onRemove: (() -> Void)?

    @State private var linkSafetySheet: AnyView?
    @State private var showLinkSafety = false

    init(metadata: LinkPreviewMetadata, onRemove: (() -> Void)? = nil) {
        self.metadata = metadata
        self.onRemove = onRemove
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            LinkSafetyServiceCompat.shared.open(metadata.url) { sheet in
                linkSafetySheet = sheet
                showLinkSafety = true
            }
        } label: {
            cardContent
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(alignment: .topTrailing) {
            if let onRemove {
                xButton(action: onRemove)
            }
        }
        .sheet(isPresented: $showLinkSafety) { linkSafetySheet }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Top decoration strip ──────────────────────────────────────
            LinearGradient(
                colors: [Color.accentColor.opacity(0.75), Color.accentColor.opacity(0.4)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 3)

            // ── Body ──────────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 12) {
                // Book icon
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    // Reference pill
                    if let ref = metadata.verseReference {
                        Text(ref)
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(Color.accentColor)
                    }
                    // Verse text (if available)
                    if let verseText = metadata.verseText, !verseText.isEmpty {
                        Text(verseText)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.primary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        // Fallback: show domain hint
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(metadata.url.host?.replacingOccurrences(of: "www.", with: "") ?? "Open Bible")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(verseCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var verseCardBackground: some View {
        ZStack {
            Color(.systemBackground)
            Color.accentColor.opacity(0.04)
        }
    }

    private func xButton(action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                action()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 22, height: 22)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: 8, y: -8)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: FeedLinkPreviewCard
// Non-removable (no X) card for rendering in PostCard / chat bubbles.
// Switches between RichLinkPreviewCard and VersePreviewCard based on type.
// ─────────────────────────────────────────────────────────────────────────────

struct FeedLinkPreviewCard: View {
    let url: URL
    let metadata: LinkPreviewMetadata?

    var body: some View {
        if let meta = metadata, meta.previewType == .verse {
            VersePreviewCard(metadata: meta, onRemove: nil)
        } else {
            RichLinkPreviewCard(url: url, metadata: metadata, isLoading: false, onRemove: nil)
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Shimmer modifier
// ─────────────────────────────────────────────────────────────────────────────

private struct LinkPreviewShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.35),
                        Color.clear
                    ],
                    startPoint: .init(x: phase, y: 0.5),
                    endPoint: .init(x: phase + 0.4, y: 0.5)
                )
                .blendMode(.plusLighter)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

private extension View {
    /// Lightweight shimmer used only on skeleton loading placeholders.
    func shimmering() -> some View {
        self.modifier(LinkPreviewShimmerModifier())
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Compact pill (feed inline) — kept for backward compat
// ─────────────────────────────────────────────────────────────────────────────

/// Small inline link chip shown in the feed when only a URL is available
/// but no metadata has been fetched yet.
struct LinkPreviewCard: View {
    let metadata: LinkPreviewMetadata
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: metadata.previewType == .verse ? "book.closed.fill" : "link")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(metadata.previewType == .verse ? Color.accentColor.opacity(0.8) : .black.opacity(0.6))

                if let title = metadata.title ?? metadata.verseReference, !title.isEmpty {
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
                }

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.black.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(pillBackground)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var pillBackground: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.9), Color(white: 0.95).opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Legacy loading view (kept for compiler compat)
// ─────────────────────────────────────────────────────────────────────────────

struct LinkPreviewLoadingView: View {
    var body: some View {
        RichLinkPreviewCard(
            url: URL(string: "https://example.com")!,
            metadata: nil,
            isLoading: true,
            onRemove: nil
        )
    }
}
