// SpaceFeedView.swift — AMEN App
// Full-screen feed for a single Space/Community

import SwiftUI
import FirebaseAuth

struct SpaceFeedView: View {
    let space: AMENSpace
    @ObservedObject var vm: SpacesViewModel

    @StateObject private var feedVM = SpaceFeedViewModel()
    @State private var showPostSheet = false
    @Environment(\.dismiss) private var dismiss

    private let background    = Color(red: 0.039, green: 0.039, blue: 0.059)
    private let accentPurple  = Color(red: 0.6,   green: 0.35,  blue: 1.0)
    private let accentPurple2 = Color(red: 0.45,  green: 0.2,   blue: 0.85)

    // Media grid columns
    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        ZStack(alignment: .bottom) {
            background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Cover header
                    coverHeader
                        .padding(.bottom, 16)

                    // Filter pills
                    filterPills
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    // Content
                    contentArea
                        .padding(.horizontal, isGridMode ? 0 : 16)
                        .padding(.bottom, 100) // clearance for FAB
                }
            }

            // Floating "Post Here" button
            postHereButton
                .padding(.bottom, 28)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear { feedVM.startListening(spaceId: space.id ?? "") }
        .onDisappear { feedVM.stopListening() }
        .sheet(isPresented: $showPostSheet) {
            PostToSpaceSheet(space: space, feedVM: feedVM)
        }
    }

    // MARK: - Cover Header

    private var coverHeader: some View {
        ZStack(alignment: .bottom) {
            // Cover image or gradient placeholder
            Group {
                if let urlString = space.coverImageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            gradientPlaceholder
                        }
                    }
                } else {
                    gradientPlaceholder
                }
            }
            .frame(height: 220)
            .clipped()
            .overlay(
                // Scrim for legibility
                LinearGradient(
                    colors: [.clear, background.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Overlaid info card
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(space.name)
                        .font(AMENFont.bold(22))
                        .foregroundStyle(.white)

                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("\(space.memberCount.compactFormatted) members")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()

                // Join / Leave button in header
                let isJoined = vm.joinedSpaceIds.contains(space.id ?? "")
                Button {
                    Task { await vm.toggleJoin(space: space) }
                } label: {
                    Text(isJoined ? "Joined" : "Join")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(isJoined ? accentPurple : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isJoined
                                      ? LinearGradient(colors: [accentPurple.opacity(0.15), accentPurple.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                      : LinearGradient(colors: [accentPurple, accentPurple2],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(accentPurple.opacity(isJoined ? 0.45 : 0), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(16)
            .background(
                .ultraThinMaterial
                    .opacity(0.0) // transparent — scrim handles it
            )
        }
        .ignoresSafeArea(edges: .top)
    }

    private var gradientPlaceholder: some View {
        LinearGradient(
            colors: [
                Color(red: 0.25, green: 0.1, blue: 0.55),
                Color(red: 0.12, green: 0.05, blue: 0.35),
                background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Filter Pills

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                contentTypePill(label: "All", icon: "square.grid.2x2",     type: nil)
                contentTypePill(label: "Posts",  icon: "text.bubble",          type: .text)
                contentTypePill(label: "Photos", icon: "photo",                type: .photo)
                contentTypePill(label: "Videos", icon: "play.rectangle.fill",  type: .video)
            }
        }
    }

    private func contentTypePill(label: String, icon: String, type: SpacePost.ContentType?) -> some View {
        let isSelected = feedVM.selectedContentType == type
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                feedVM.selectedContentType = type
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .medium))
                Text(label)
                    .font(AMENFont.semiBold(13))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected
                          ? LinearGradient(colors: [accentPurple, accentPurple2],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(isSelected ? 0 : 0.08), lineWidth: 1)
                    )
                    .shadow(color: accentPurple.opacity(isSelected ? 0.4 : 0), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    private var isGridMode: Bool {
        feedVM.selectedContentType == .photo || feedVM.selectedContentType == .video
    }

    @ViewBuilder
    private var contentArea: some View {
        if feedVM.isLoading {
            ProgressView()
                .tint(accentPurple)
                .scaleEffect(1.2)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else if feedVM.filtered.isEmpty {
            emptyState
                .padding(.top, 60)
        } else if isGridMode {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(feedVM.filtered) { post in
                    MediaCellView(post: post)
                }
            }
        } else {
            LazyVStack(spacing: 14) {
                ForEach(feedVM.filtered) { post in
                    SpacePostRow(post: post)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.open")
                .font(.systemScaled(44, weight: .light))
                .foregroundStyle(accentPurple.opacity(0.7))

            Text("No posts yet in this community")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.white.opacity(0.7))

            Text("Be the first to share something")
                .font(AMENFont.regular(14))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Post Here FAB

    private var postHereButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showPostSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.systemScaled(15, weight: .semibold))
                Text("Post Here")
                    .font(AMENFont.semiBold(15))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accentPurple, accentPurple2],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: accentPurple.opacity(0.5), radius: 14, y: 5)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - SpacePostRow

private struct SpacePostRow: View {
    let post: SpacePost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Author avatar
                AsyncImage(url: URL(string: post.authorPhotoURL ?? "")) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Circle()
                            .fill(Color(red: 0.6, green: 0.35, blue: 1.0).opacity(0.25))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.systemScaled(14))
                                    .foregroundStyle(Color(red: 0.6, green: 0.35, blue: 1.0))
                            )
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(post.authorName ?? "Community Member")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.white)

                    if let date = post.createdAt {
                        Text(date.timeAgoShort)
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                Spacer()
            }

            if let text = post.textContent {
                Text(text)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(3)
            }

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Image(systemName: "heart")
                        .font(.systemScaled(13))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("\(post.likes)")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                        .font(.systemScaled(13))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("\(post.comments)")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

// MARK: - MediaCellView

private struct MediaCellView: View {
    let post: SpacePost

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let urlString = post.mediaURLs.first, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle()
                                .fill(Color(red: 0.1, green: 0.07, blue: 0.2))
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color(red: 0.1, green: 0.07, blue: 0.2))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.white.opacity(0.3))
                        )
                }

                // Play icon for video
                if post.contentType == .video {
                    Circle()
                        .fill(.black.opacity(0.45))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.systemScaled(14, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: 1.5)
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.width) // 1:1
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Date helper

private extension Date {
    var timeAgoShort: String {
        let secs = Int(-timeIntervalSinceNow)
        switch secs {
        case ..<60:        return "now"
        case ..<3600:      return "\(secs / 60)m"
        case ..<86400:     return "\(secs / 3600)h"
        default:           return "\(secs / 86400)d"
        }
    }
}

// Int.compactFormatted is defined app-wide in FollowerAvatarStack.swift
