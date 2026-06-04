// BereanFeedItemCard.swift
// AMENAPP — Berean OS
//
// Card view for a single BereanFeedItem.
// Displays type badge, title, summary, author, timestamp,
// knowledge quality bar, and community action counts.
// Tap opens a detail sheet.

import SwiftUI

// MARK: - BereanFeedItemCard

struct BereanFeedItemCard: View {

    let item: BereanFeedItem

    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            BereanFeedItemDetailSheet(item: item)
        }
    }

    // MARK: - Card Layout

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            typeBadge
            titleAndSummary
            authorRow
            qualityBar
            communityRow
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Type Badge

    private var typeBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: item.itemType.systemIcon)
                .font(.caption2.weight(.semibold))
            Text(item.itemType.displayName)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(item.itemType.accentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(item.itemType.accentColor.opacity(0.12))
        )
    }

    // MARK: - Title + Summary

    private var titleAndSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    // MARK: - Author Row

    private var authorRow: some View {
        HStack(spacing: 8) {
            // Avatar initial
            Circle()
                .fill(item.itemType.accentColor.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(item.authorId.prefix(1)).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.itemType.accentColor)
                )

            Text(item.authorId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(item.publishedAt.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Knowledge Quality Bar

    private var qualityBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Knowledge Quality")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 4) {
                // Usefulness segment
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemFill))
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.blue.opacity(0.8))
                            .frame(width: geo.size.width * item.usefulnessScore, height: 6)
                    }
                }
                .frame(height: 6)

                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Trust segment
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemFill))
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.green.opacity(0.8))
                            .frame(width: geo.size.width * item.communityTrustScore, height: 6)
                    }
                }
                .frame(height: 6)
            }

            HStack {
                Label("Useful", systemImage: "hand.thumbsup.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Trusted", systemImage: "checkmark.shield.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Community Actions Row

    private var communityRow: some View {
        HStack(spacing: 14) {
            communityBadge(icon: "hand.thumbsup", count: Int(item.usefulnessScore * 20))
            communityBadge(icon: "bubble.left", count: Int(item.communityTrustScore * 10))
            communityBadge(icon: "arrow.2.squarepath", count: Int(item.rankedScore * 5))
            Spacer()
        }
    }

    private func communityBadge(icon: String, count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Detail Sheet (placeholder)

private struct BereanFeedItemDetailSheet: View {

    let item: BereanFeedItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Badge
                    HStack(spacing: 6) {
                        Image(systemName: item.itemType.systemIcon)
                        Text(item.itemType.displayName)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.itemType.accentColor)

                    // Title
                    Text(item.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Divider()

                    // Summary
                    Text(item.summary)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Divider()

                    // Metadata
                    VStack(alignment: .leading, spacing: 6) {
                        Label(item.authorId, systemImage: "person.fill")
                        Label(item.publishedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if let projectId = item.projectId {
                        Label("Project: \(projectId)", systemImage: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Full Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
