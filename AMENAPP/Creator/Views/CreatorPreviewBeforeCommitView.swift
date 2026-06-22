// CreatorPreviewBeforeCommitView.swift
// AMENAPP — Creator Spotlight / Wave 1
//
// "Preview" section — lets the viewer sample the first session
// before committing to a series or content. Opaque white card.
// If previewUrl is nil: ContentUnavailableView.
// If available: tappable card that opens a sheet.

import SwiftUI

struct CreatorPreviewBeforeCommitView: View {

    let previewUrl: String?
    let format: ContentFormat

    @State private var showPreviewSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)

            if previewUrl != nil {
                availableCard
                    .padding(.horizontal, 20)
            } else {
                ContentUnavailableView(
                    "Preview coming soon",
                    systemImage: "play.rectangle",
                    description: Text("The creator hasn't added a preview yet.")
                )
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showPreviewSheet) {
            PreviewPlaceholderSheet(format: format)
        }
    }

    // MARK: - Available Card

    private var availableCard: some View {
        Button {
            showPreviewSheet = true
        } label: {
            HStack(spacing: 16) {
                // Thumbnail shimmer placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 80, height: 56)
                    Image(systemName: playIcon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(formatLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("No commitment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var playIcon: String {
        switch format {
        case .audio: return "waveform"
        case .video, .live: return "play.fill"
        default: return "text.page"
        }
    }

    private var formatLabel: String {
        switch format {
        case .video:      return "Watch a clip"
        case .audio:      return "Listen to a sample"
        case .text:       return "Read an excerpt"
        case .series:     return "Watch the first episode"
        case .studyGuide: return "Preview the guide"
        case .devotional: return "Read a devotional"
        case .prayer:     return "Preview this prayer"
        case .live:       return "Watch a highlight"
        }
    }
}

// MARK: - Preview Placeholder Sheet

private struct PreviewPlaceholderSheet: View {
    let format: ContentFormat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("Preview")
                    .font(.system(size: 20, weight: .semibold))
                Text("The preview player will be available when the creator publishes a sample.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .background(Color(.systemBackground))
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
