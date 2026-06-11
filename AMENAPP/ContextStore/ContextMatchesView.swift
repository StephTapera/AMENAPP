// ContextMatchesView.swift
// AMEN Universal Migration & Context System — Wave 4 (matching-engineer)
//
// The GlassKit surface that shows community matches derived from a user's Tier-C context
// facets: groups, Spaces, events, and volunteer opportunities — each with a human
// "Why this community fits you" explanation (the FIT reason, never a score).
//
// HARD RULES honored here (CONTRACTS §9):
//   • Flag-gated on `contextSystemEnabled && contextMatchingEnabled`. Nothing renders unless
//     both are true (shows the shared ContextUnavailableNotice otherwise).
//   • GlassKit surfaces only (capsule surface / ultraThinMaterial cards), no glass-on-glass.
//   • All animation via Motion.adaptive (reduce-motion safe).
//   • No spiritual ranking — the explanation is a reason, never a number/score/level.
//   • The view holds NO facet values; it binds only to ContextMatchingService's {id,type,explanation}.

import SwiftUI

struct ContextMatchesView: View {

    @StateObject private var flags = AMENFeatureFlags.shared
    @StateObject private var service = ContextMatchingService.shared

    /// Set once we've attempted at least one load (drives the empty-vs-not-yet-loaded copy).
    @State private var didAttemptLoad = false

    var body: some View {
        Group {
            if flags.contextSystemEnabled && flags.contextMatchingEnabled {
                content
            } else {
                ContextUnavailableNotice()
            }
        }
        .navigationTitle("Communities that fit you")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadIfNeeded() }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro

                if service.isMatching && service.matches.isEmpty {
                    loadingNotice
                } else if let err = service.lastError, service.matches.isEmpty {
                    errorNotice(err)
                } else if service.matches.isEmpty {
                    emptyNotice
                } else {
                    ForEach(service.matches) { match in
                        matchCard(match)
                    }
                }
            }
            .padding()
        }
        .refreshable { await reload() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("These communities line up with what you've chosen to share — your interests, values, and goals. Matched on fit, never ranked.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AmenAIUsageLabel(text: "AI-assisted · matched on your context")
        }
    }

    // MARK: - Match card

    private func matchCard(_ match: ContextCommunityMatch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: match.type.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(match.type.displayName.uppercased())
                    .font(.caption.weight(.bold))
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // "Why this community fits you" — a reason, never a score.
            Text(match.explanation)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardSurface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(match.type.displayName). Why this fits you: \(match.explanation)")
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    // MARK: - States

    private var loadingNotice: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Finding communities that fit…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var emptyNotice: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No matches yet. Add a few interests, values, or goals to your context and we'll find communities that fit.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func errorNotice(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("We couldn't load matches right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await reload() } }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityHint(message)
    }

    // MARK: - Loading

    private func loadIfNeeded() async {
        guard !didAttemptLoad else { return }
        await reload()
    }

    private func reload() async {
        didAttemptLoad = true
        // Errors surface through service.lastError; we never crash the view on a failed match.
        try? await service.refreshMatches()
        withAnimation(Motion.adaptive(Motion.appearEase)) { }
    }
}
