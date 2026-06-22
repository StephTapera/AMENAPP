// WhyAmISeeingThisView.swift
// AMENAPP
//
// Phase 4 — Discovery transparency.
// Compact "Why?" pill + a sheet that lists the server-derived reasons a post
// surfaced in the user's feed. Every label and explanation comes from the
// `getDiscoveryReasons` Cloud Function. The client never invents a reason.
//
// Liquid Glass:
//   - Glass header (.ultraThinMaterial), solid body
//   - Reduce Transparency falls back to a solid header
//   - Capsule pill, calm motion (no springy bounces)

import SwiftUI

// MARK: - WhyAmISeeingThisPill

struct DiscoveryWhyPill: View {

    let postId: String

    @ObservedObject private var flags = AMENFeatureFlags.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showingSheet = false

    var body: some View {
        Group {
            if flags.smartDiscoveryTransparencyEnabled {
                Button {
                    showingSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "questionmark.circle")
                            .font(.systemScaled(11, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("Why?")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(pillBackground)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Why am I seeing this post?")
                .accessibilityHint("Opens a sheet explaining why this post is in your feed")
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showingSheet) {
            DiscoveryWhySheet(postId: postId, onDismiss: { showingSheet = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
    }

    private var pillBackground: some View {
        Group {
            if reduceTransparency {
                Color(.secondarySystemBackground)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - WhyAmISeeingThisSheet

struct DiscoveryWhySheet: View {

    let postId: String
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var model = DiscoveryWhyModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    intro
                    contentSection
                    disclaimer
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .task(id: postId) {
            await model.load(postId: postId)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Why am I seeing this?")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Reasons are determined by Amen's discovery system")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBackground)
    }

    private var headerBackground: some View {
        Group {
            if reduceTransparency {
                Color(.secondarySystemBackground)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    private var intro: some View {
        Text("This post showed up in your feed for the following reasons. Each reason is recorded server-side and cannot be modified by creators.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var contentSection: some View {
        switch model.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading reasons…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
        case .empty:
            ReasonUnavailableCard(message: "No discovery reasons are available for this post.")
        case .failed(let message):
            ReasonUnavailableCard(message: message)
        case .loaded(let reasons):
            VStack(spacing: 10) {
                ForEach(reasons) { reason in
                    ReasonCard(reason: reason)
                }
            }
        }
    }

    private var disclaimer: some View {
        Text("Discovery reasons are derived from Amen's server-side ranking signals. We don't sell what we know about you and we don't reward content for racking up vanity engagement.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

// MARK: - ReasonCard

private struct ReasonCard: View {
    let reason: TrustSpineService.DiscoveryReasonRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: reason.icon)
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(reason.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(reason.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(reason.label). \(reason.explanation)")
    }
}

// MARK: - ReasonUnavailableCard

private struct ReasonUnavailableCard: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - WhyAmISeeingThisModel

@MainActor
final class DiscoveryWhyModel: ObservableObject {

    enum LoadState {
        case loading
        case loaded([TrustSpineService.DiscoveryReasonRow])
        case empty
        case failed(String)
    }

    @Published private(set) var state: LoadState = .loading

    func load(postId: String) async {
        state = .loading
        do {
            let result = try await TrustSpineService.shared.getDiscoveryReasons(postId: postId)
            if result.reasons.isEmpty {
                state = .empty
            } else {
                state = .loaded(result.reasons)
            }
            TrustSpineAnalytics.track(.discoveryWhyViewed, params: [
                "post_id": postId,
                "reason_count": result.reasons.count,
            ])
        } catch {
            state = .failed("Could not load reasons. Please try again later.")
        }
    }
}

#if DEBUG
#Preview("Why pill") {
    ZStack {
        Color.white
        DiscoveryWhyPill(postId: "preview_post")
    }
}
#endif
