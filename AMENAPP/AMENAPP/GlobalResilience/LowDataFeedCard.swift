// LowDataFeedCard.swift
// AMEN — Global Resilience System
// Feed card optimised for low-bandwidth environments.
// Respects LowDataModeManager.shared.isEffectiveLowData and defers
// heavy media loads behind explicit user intent.

import SwiftUI
import AVKit

// MARK: - LowDataFeedCard

struct LowDataFeedCard: View {

    // MARK: Parameters

    let title: String
    let textPreview: String
    let thumbnailURL: URL?
    let estimatedDataKb: Int
    let mediaType: String?
    let assetId: String?

    // MARK: Environment

    @ObservedObject private var lowDataManager = LowDataModeManager.shared

    // MARK: Private State

    /// Tracks whether the user has explicitly requested the full image load.
    @State private var loadFullImage: Bool = false

    /// Controls the expanded transcript sheet.
    @State private var showFullTranscript: Bool = false

    // MARK: Computed

    private var isLowData: Bool {
        lowDataManager.isEffectiveLowData
    }

    private var isVideo: Bool {
        mediaType?.lowercased() == "video"
    }

    private var truncatedPreview: String {
        if textPreview.count <= 140 {
            return textPreview
        }
        let index = textPreview.index(textPreview.startIndex, offsetBy: 140)
        return String(textPreview[..<index]) + "…"
    }

    private var needsTruncation: Bool {
        textPreview.count > 140
    }

    // MARK: Body

    var body: some View {
        cardContent
            .glassEffect()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(textPreview)")
            .sheet(isPresented: $showFullTranscript) {
                fullTranscriptSheet
            }
    }

    // MARK: Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                mediaRegion
                    .frame(width: isLowData ? 48 : 80, height: isLowData ? 48 : 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    textPreviewRegion
                }
            }

            if isLowData {
                loadMediaButton
            }
        }
        .padding(16)
    }

    // MARK: Media Region

    @ViewBuilder
    private var mediaRegion: some View {
        if isLowData && !loadFullImage {
            // Low-data placeholder: no network request
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                Image(systemName: isVideo ? "video.slash" : "photo")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        } else if let url = thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.15))
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            // No thumbnail URL: text-only placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        }
    }

    // MARK: Text Preview Region

    private var textPreviewRegion: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(needsTruncation ? truncatedPreview : textPreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(needsTruncation ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)

            if needsTruncation {
                Button("Read more") {
                    showFullTranscript = true
                }
                .font(.caption)
                .foregroundStyle(.blue)
                .accessibilityLabel("Read full preview for \(title)")
            }
        }
    }

    // MARK: Load Media Button

    @ViewBuilder
    private var loadMediaButton: some View {
        if !loadFullImage, thumbnailURL != nil {
            Button {
                loadFullImage = true
            } label: {
                Label(
                    isVideo
                        ? "Load video (≈\(estimatedDataKb)KB)"
                        : "Load image (≈\(estimatedDataKb)KB)",
                    systemImage: isVideo ? "play.circle" : "photo.badge.arrow.down"
                )
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel(
                isVideo
                    ? "Load video, approximately \(estimatedDataKb) kilobytes"
                    : "Load image, approximately \(estimatedDataKb) kilobytes"
            )
        }
    }

    // MARK: Full Transcript Sheet

    private var fullTranscriptSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.title2.bold())
                        .padding(.horizontal)

                    Text(textPreview)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Full Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFullTranscript = false }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Normal mode") {
    LowDataFeedCard(
        title: "Sermon: Walk in the Light",
        textPreview: "Pastor James opened with a reflection on 1 John 1:7, urging the congregation to live transparently in community, shedding the habits of isolation that distance us from one another and from God.",
        thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
        estimatedDataKb: 420,
        mediaType: "image",
        assetId: "asset-001"
    )
    .padding()
}

#Preview("Low data / video") {
    LowDataFeedCard(
        title: "Wednesday Bible Study Recap",
        textPreview: "A deep dive into the book of Romans covering chapters 5 through 8 with small-group discussion highlights.",
        thumbnailURL: URL(string: "https://example.com/video-thumb.jpg"),
        estimatedDataKb: 2800,
        mediaType: "video",
        assetId: "asset-002"
    )
    .padding()
    .environment(\.colorScheme, .dark)
}

#Preview("No thumbnail") {
    LowDataFeedCard(
        title: "Prayer Request",
        textPreview: "Please keep Sister Maria and her family in prayer as they navigate a difficult season of health challenges. The community has rallied around them with meals and encouragement.",
        thumbnailURL: nil,
        estimatedDataKb: 0,
        mediaType: nil,
        assetId: nil
    )
    .padding()
}
#endif
