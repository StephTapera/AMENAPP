// AmenContentRenderer.swift
// AMENAPP
// Renders ContentNode in-feed while preserving existing PostCard behavior.

import SwiftUI

struct AmenContentRenderer: View {
    let node: ContentNode

    var body: some View {
        let route = AmenContentRouter.route(node)
        Group {
            switch route {
            case .postPreview(let post):
                PostCard(post: post)
            case .fallback:
                AmenContentFallbackCard(node: node)
            }
        }
        .onAppear {
            AMENAnalyticsService.shared.track(.contentNodeRendered(type: node.type.rawValue))
        }
    }
}

private struct AmenContentFallbackCard: View {
    let node: ContentNode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(node.author.displayName)
                    .font(.systemScaled(14, weight: .semibold))
                Text(node.createdAt.timeAgoDisplay())
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            if let title = node.title, !title.isEmpty {
                Text(title)
                    .font(.systemScaled(18, weight: .bold))
            }

            if !node.displayText.isEmpty {
                Text(node.displayText)
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(.primary)
            }

            if !node.mediaRefs.isEmpty {
                Text("Media: \(node.mediaRefs.count)")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

struct AmenContentPreviewScreen: View {
    let nodes: [ContentNode]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(nodes) { node in
                    AmenContentRenderer(node: node)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .navigationTitle("Content Preview")
    }
}
