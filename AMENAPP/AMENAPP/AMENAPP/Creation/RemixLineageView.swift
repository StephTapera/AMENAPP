// RemixLineageView.swift
// AMEN App — Attribution chain view for remixed content
//
// Shows the attribution chain from root to current artifact:
//   avatars + names in a vertical chain with connecting lines.
//
// ZERO counters: no "3 remixes", no "built upon 5 times", no counts of any kind.
// User-facing copy: "Build upon this" (not "Remix" — less tech jargon).
//
// Flag-gated: AMENFeatureFlags.shared.remixLineage

import SwiftUI

struct RemixLineageView: View {

    @ObservedObject private var flags = AMENFeatureFlags.shared

    let artifactId: String
    let onBuildUpon: (String) -> Void   // called with artifactId when user taps "Build upon this"

    var body: some View {
        if !flags.remixLineage {
            EmptyView()
        } else {
            RemixLineageContent(
                artifactId: artifactId,
                onBuildUpon: onBuildUpon
            )
        }
    }
}

// MARK: - Content

@MainActor
private struct RemixLineageContent: View {

    let artifactId: String
    let onBuildUpon: (String) -> Void

    @StateObject private var service = RemixService()
    @State private var chain: [RemixLineage] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let error = loadError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            } else if chain.isEmpty {
                // Root artifact — no attribution chain
                buildUponButton
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            } else {
                chainRows
                buildUponButton
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            }
        }
        .task {
            await loadChain()
        }
    }

    // MARK: - Chain rows

    private var chainRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chain.enumerated()), id: \.element.id) { index, link in
                chainRow(link: link, index: index, total: chain.count)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func chainRow(link: RemixLineage, index: Int, total: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                avatarCircle(uid: link.creatorUid)

                // Connecting line — not shown after last item
                if index < total - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                attributionLabel(link: link, index: index, total: total)
                    .padding(.top, 8)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func attributionLabel(link: RemixLineage, index: Int, total: Int) -> some View {
        Group {
            if index == 0 && total == 1 {
                // Single link in chain
                Text("Built upon ")
                    .foregroundStyle(.secondary)
                    .font(.subheadline) +
                Text(displayName(uid: link.creatorUid))
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.primary) +
                Text("'s reflection")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else if index == 0 {
                // Root
                Text("Rooted in ")
                    .foregroundStyle(.secondary)
                    .font(.subheadline) +
                Text(displayName(uid: link.creatorUid))
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.primary) +
                Text("'s testimony")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                // Middle or last links
                Text("Built upon ")
                    .foregroundStyle(.secondary)
                    .font(.subheadline) +
                Text(displayName(uid: link.creatorUid))
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.primary) +
                Text("'s reflection")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
        .onTapGesture {
            navigateToProfile(uid: link.creatorUid)
        }
        .accessibilityAddTraits(.isButton)
    }

    private func avatarCircle(uid: String) -> some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 36, height: 36)
            .overlay(
                Text(uid.prefix(1).uppercased())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            )
            .accessibilityHidden(true)
    }

    // MARK: - Build upon button

    private var buildUponButton: some View {
        Button {
            onBuildUpon(artifactId)
        } label: {
            Text("Build upon this")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .accessibilityLabel("Build upon this reflection")
    }

    // MARK: - Helpers

    private func loadChain() async {
        isLoading = true
        defer { isLoading = false }
        do {
            chain = try await service.lineageChain(for: artifactId)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func displayName(uid: String) -> String {
        // In production this would look up a display name from a user store.
        // Stub returns a sanitized prefix to avoid exposing raw UIDs in UI.
        "a community member"
    }

    private func navigateToProfile(uid: String) {
        // Navigation handled by the parent coordinator — post a notification
        // so callers can route to the profile without coupling this view to nav.
        NotificationCenter.default.post(
            name: .remixLineageProfileTapped,
            object: uid
        )
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let remixLineageProfileTapped = Notification.Name("remixLineageProfileTapped")
}
