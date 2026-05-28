import AVKit
import SwiftUI

struct AmenImmersiveFeedView: View {
    @State private var items: [ContentNode] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading videos")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text("Unable to load feed")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await load() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No approved videos yet")
                        .font(.headline)
                    Text("Approved public video content will appear here when Universal Content is enabled.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView {
                    ForEach(items) { item in
                        AmenVideoFeedCell(content: item)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .background(Color.black)
            }
        }
        .task { await load() }
        .navigationTitle("Video")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        guard AMENFeatureFlags.shared.universalContentModelEnabled else {
            items = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let feed = try await AmenUniversalContentService.shared.fetchFeed(limit: 40)
            items = feed.filter { node in
                node.type == .video || node.mediaRefs.contains { $0.type == .video }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AmenVideoFeedCell: View {
    let content: ContentNode

    private var videoURL: URL? {
        content.mediaRefs.compactMap { ref -> URL? in
            guard ref.type == .video, let raw = ref.url else { return nil }
            return URL(string: raw)
        }.first
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let videoURL {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .ignoresSafeArea()
                    .accessibilityLabel("Video player")
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "video.slash")
                                .font(.largeTitle)
                            Text("Video asset unavailable")
                                .font(.headline)
                            Text("This content is approved, but playback needs a resolved media URL.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white)
                        .padding()
                    }
                    .ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(content.author.displayName)
                    .font(.subheadline.weight(.semibold))
                if let title = content.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                }
                Text(content.displayText)
                    .font(.subheadline)
                    .lineLimit(3)
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(16)
            .accessibilityElement(children: .combine)
        }
    }
}
