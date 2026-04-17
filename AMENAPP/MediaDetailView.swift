//
//  MediaDetailView.swift
//  AMENAPP
//
//  Media-first post detail view.
//  Opens focused on the selected image/video with swipe navigation.
//  Provides access to author, caption, verse, engagement, and
//  a "View full post" action to jump to the original post detail.
//  Liquid Glass design system.
//

import SwiftUI

struct MediaDetailView: View {
    let item: EnrichedMediaGridItem
    var onViewFullPost: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentIndex: Int
    @State private var showChrome = true
    @State private var dragDismissOffset: CGFloat = 0
    @State private var showFullCaption = false

    init(item: EnrichedMediaGridItem, onViewFullPost: ((String) -> Void)? = nil) {
        self.item = item
        self.onViewFullPost = onViewFullPost
        _currentIndex = State(initialValue: item.indexInPost)
    }

    private var dismissOpacity: Double {
        let progress = abs(dragDismissOffset) / 220.0
        return Double(max(0, 1.0 - progress))
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .opacity(dismissOpacity)
                .ignoresSafeArea()

            // Media pager
            mediaPager
                .offset(y: dragDismissOffset)
                .gesture(dismissDragGesture)

            // Chrome overlay
            if showChrome {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomPanel
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden()
        .onTapGesture { toggleChrome() }
    }

    // MARK: - Media Pager

    @ViewBuilder
    private var mediaPager: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(item.allImageURLs.enumerated()), id: \.offset) { index, url in
                mediaPage(url: url)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: item.isCarousel ? .automatic : .never))
    }

    @ViewBuilder
    private func mediaPage(url: String) -> some View {
        CachedAsyncImage(
            url: URL(string: url),
            size: CGSize(width: 800, height: 800)
        ) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            ProgressView()
                .tint(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Author info
            HStack(spacing: 8) {
                authorAvatar
                VStack(alignment: .leading, spacing: 1) {
                    if let name = item.authorName {
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(item.postTimestamp)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.5), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var authorAvatar: some View {
        if let urlString = item.authorProfileImageURL, let url = URL(string: urlString) {
            CachedAsyncImage(url: url, size: CGSize(width: 64, height: 64)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle().fill(Color.white.opacity(0.2))
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String((item.authorName ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                )
        }
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Caption preview
            captionSection

            // Verse pill
            if let verse = item.verseReference, !verse.isEmpty {
                versePill(verse)
            }

            // Page indicator + actions
            HStack {
                if item.isCarousel {
                    Text("\(currentIndex + 1) of \(item.carouselCount)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                // View full post button
                if onViewFullPost != nil {
                    Button {
                        onViewFullPost?(item.postId)
                    } label: {
                        HStack(spacing: 4) {
                            Text("View post")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.18))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                                )
                        )
                    }
                    .accessibilityLabel("View full post")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var captionSection: some View {
        if !item.postContent.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.postContent)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(showFullCaption ? nil : 2)
                    .onTapGesture { showFullCaption.toggle() }

                if item.postContent.count > 100 && !showFullCaption {
                    Text("more")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .onTapGesture { showFullCaption = true }
                }
            }
        }
    }

    private func versePill(_ verse: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 10, weight: .medium))
            Text(verse)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.white.opacity(0.15))
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .accessibilityLabel("Verse: \(verse)")
    }

    // MARK: - Gestures

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if abs(value.translation.height) > abs(value.translation.width) {
                    dragDismissOffset = value.translation.height
                }
            }
            .onEnded { value in
                if abs(value.translation.height) > 120 {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)) {
                        dragDismissOffset = 0
                    }
                }
            }
    }

    private func toggleChrome() {
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) {
            showChrome.toggle()
        }
    }
}
