// PostProvenanceSheet.swift
// AMENAPP/PostProvenance
//
// Sheet shown when the user taps the ⓘ icon on a post.
// Explains why a post is in their feed (feed provenance) and
// lets them take agency actions (not relevant, mute, hide, etc.).
//
// Phase 3 — "Why you're seeing this" transparency feature.
// Feature-flagged under MasterRunFeatureFlags.whySeeingThis.

import SwiftUI

// MARK: - PostProvenanceSheet

/// Bottom sheet that shows score-ranked provenance reasons for a post
/// and surfaces six calm agency actions so the user can tune their feed.
///
/// Presented by `ProvenanceInfoButton` via `.sheet()`. Uses `GlassSheet`
/// from AmenGlassKit as the chrome container.
struct PostProvenanceSheet: View {

    // MARK: Inputs

    let postId: String
    @Binding var isPresented: Bool

    // MARK: State

    @State private var provenance: PostProvenance? = nil
    @State private var isLoading = true
    @State private var loadError: Error? = nil

    /// Tracks which feedback action is currently in-flight for loading state.
    @State private var pendingFeedback: ProvenanceFeedback? = nil
    /// Which action completed successfully (shows a brief checkmark).
    @State private var confirmedFeedback: ProvenanceFeedback? = nil
    /// Controls the mute confirmation alert.
    @State private var showMuteConfirm = false
    /// Stores the authorId captured when the user taps "Mute" — used by the alert.
    @State private var pendingMuteAuthorId: String? = nil
    /// Controls navigation to FeedIntelligenceSettingsView.
    @State private var showPreferences = false

    // MARK: Environments

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        GlassSheet(
            title: "Why this is in your feed",
            subtitle: subtitleText
        ) {
            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else if let prov = provenance {
                provenanceContent(prov)
            }
        }
        .task {
            await loadProvenance()
        }
        .alert("Mute this author?", isPresented: $showMuteConfirm) {
            Button("Mute", role: .destructive) {
                if let authorId = pendingMuteAuthorId {
                    Task { await sendFeedback(.mute(authorId: authorId)) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see posts from this author in your feed. You can undo this in your feed preferences.")
        }
        .sheet(isPresented: $showPreferences) {
            FeedIntelligenceSettingsView()
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Subtitle

    private var subtitleText: String? {
        guard let addedOn = provenance?.addedInterestOn else { return nil }
        let formatted = addedOn.formatted(date: .abbreviated, time: .omitted)
        return "You added this interest on \(formatted)"
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                AmenGlassLoadingSkeleton(cornerRadius: 12, height: 56)
            }
        }
        .accessibilityLabel("Loading feed provenance")
    }

    // MARK: Error

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .accessibilityHidden(true)
            Text("Couldn't load details right now.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            GlassButton("Try again", icon: "arrow.clockwise", style: .secondary) {
                Task { await loadProvenance() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: Provenance content

    @ViewBuilder
    private func provenanceContent(_ prov: PostProvenance) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // ── Reason list ────────────────────────────────────────
            reasonsList(prov.reasons)

            // ── Agency actions ─────────────────────────────────────
            agencyActions(prov)
        }
    }

    // MARK: Reasons list

    @ViewBuilder
    private func reasonsList(_ reasons: [ProvenanceReason]) -> some View {
        let sorted = reasons.sorted { $0.score > $1.score }

        VStack(alignment: .leading, spacing: 10) {
            Text("Signals in your feed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            ForEach(sorted, id: \.kind) { reason in
                ProvenanceReasonRow(reason: reason)
            }
        }
    }

    // MARK: Agency actions

    @ViewBuilder
    private func agencyActions(_ prov: PostProvenance) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your choices")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.bottom, 8)

            GlassCard {
                VStack(spacing: 0) {
                    // Not relevant
                    GlassActionRow(
                        icon: confirmedIcon(for: .notRelevant(postId: postId), default: "hand.thumbsdown"),
                        label: "Not relevant",
                        subtitle: "Remove this post from your feed"
                    ) {
                        Task { await sendFeedback(.notRelevant(postId: postId)) }
                    }
                    .disabled(pendingFeedback != nil)

                    rowDivider

                    // See your preferences
                    GlassActionRow(
                        icon: "slider.horizontal.3",
                        label: "See your preferences",
                        subtitle: "View and edit what appears in your feed"
                    ) {
                        showPreferences = true
                    }

                    rowDivider

                    // More like this
                    GlassActionRow(
                        icon: confirmedIcon(for: .wantMore(postId: postId), default: "arrow.up.circle"),
                        label: "More like this",
                        subtitle: "Boost this topic in future recommendations"
                    ) {
                        Task { await sendFeedback(.wantMore(postId: postId)) }
                    }
                    .disabled(pendingFeedback != nil)

                    rowDivider

                    // Fewer like this
                    GlassActionRow(
                        icon: confirmedIcon(for: .wantFewer(postId: postId), default: "arrow.down.circle"),
                        label: "Fewer like this",
                        subtitle: "Lower similar posts without removing everything"
                    ) {
                        Task { await sendFeedback(.wantFewer(postId: postId)) }
                    }
                    .disabled(pendingFeedback != nil)

                    rowDivider

                    // Mute author — destructive, requires confirmation
                    // authorId not stored on PostProvenance; A8 will add it.
                    // Using postId as proxy until then.
                    GlassActionRow(
                        icon: confirmedIcon(for: .mute(authorId: postId), default: "speaker.slash"),
                        label: "Mute this author",
                        subtitle: "Stop seeing posts from this person",
                        role: .destructive
                    ) {
                        pendingMuteAuthorId = postId   // A8 wire: replace with real authorId
                        showMuteConfirm = true
                    }
                    .disabled(pendingFeedback != nil)

                    rowDivider

                    // Hide post — destructive, dismisses sheet on completion
                    GlassActionRow(
                        icon: confirmedIcon(for: .hide(postId: postId), default: "eye.slash"),
                        label: "Hide this post",
                        subtitle: "This post won't appear in your feed again",
                        role: .destructive
                    ) {
                        Task {
                            await sendFeedback(.hide(postId: postId))
                            // Dismiss after hide completes
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            isPresented = false
                        }
                    }
                    .disabled(pendingFeedback != nil)
                }
            }
        }
    }

    // MARK: Row divider

    private var rowDivider: some View {
        Divider()
            .background(AmenTheme.Colors.separatorSubtle)
            .padding(.horizontal, 16)
    }

    // MARK: Icon helper

    /// Returns a confirmed checkmark icon if this feedback was just completed;
    /// otherwise returns the default icon name.
    private func confirmedIcon(for feedback: ProvenanceFeedback, default defaultIcon: String) -> String {
        confirmedFeedback == feedback ? "checkmark.circle.fill" : defaultIcon
    }

    // MARK: Data loading

    private func loadProvenance() async {
        isLoading = true
        loadError = nil
        do {
            let result = try await PostProvenanceService.shared.fetchProvenance(postId: postId)
            withAnimation(reduceMotion ? .none : Motion.adaptive(Motion.appearEase)) {
                provenance = result
                isLoading = false
            }
        } catch {
            isLoading = false
            loadError = error
        }
    }

    // MARK: Feedback

    private func sendFeedback(_ feedback: ProvenanceFeedback) async {
        guard pendingFeedback == nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? .none : Motion.adaptive(Motion.springPress)) {
            pendingFeedback = feedback
        }
        do {
            try await PostProvenanceService.shared.sendFeedback(feedback)
            withAnimation(reduceMotion ? .none : Motion.adaptive(Motion.popToggle)) {
                confirmedFeedback = feedback
                pendingFeedback = nil
            }
        } catch {
            withAnimation(reduceMotion ? .none : Motion.adaptive(Motion.springPress)) {
                pendingFeedback = nil
            }
        }
    }
}

// MARK: - ProvenanceReasonRow

/// A single reason row: icon + label + subtle confidence bar.
private struct ProvenanceReasonRow: View {

    let reason: ProvenanceReason

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Icon
            Image(systemName: iconName(for: reason.kind))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .frame(width: 24)
                .accessibilityHidden(true)

            // Label + confidence bar
            VStack(alignment: .leading, spacing: 5) {
                Text(reason.label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Confidence bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AmenTheme.Colors.separatorSubtle)
                            .frame(height: 3)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AmenTheme.Colors.amenGold.opacity(0.8),
                                        AmenTheme.Colors.amenGold
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * reason.score, height: 3)
                            .animation(
                                reduceMotion
                                    ? .none
                                    : .spring(response: 0.5, dampingFraction: 0.82),
                                value: reason.score
                            )
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.clear)
        .amenGlass(.regular, cornerRadius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(accessibilityIconDescription(for: reason.kind)): \(reason.label), \(Int(reason.score * 100)) percent confidence"
        )
    }

    // MARK: Icon mapping

    private func iconName(for kind: ProvenanceReasonKind) -> String {
        switch kind {
        case .following:         return "person.2.fill"
        case .communityTrending: return "chart.line.uptrend.xyaxis"
        case .sharedInterest:    return "heart.fill"
        case .churchGroup:       return "building.columns.fill"
        case .scripture:         return "book.fill"
        case .recencyBoost:      return "clock.fill"
        case .curatedByBerean:   return "sparkles"
        }
    }

    private func accessibilityIconDescription(for kind: ProvenanceReasonKind) -> String {
        switch kind {
        case .following:         return "Following"
        case .communityTrending: return "Trending in your community"
        case .sharedInterest:    return "Shared interest"
        case .churchGroup:       return "Church group"
        case .scripture:         return "Scripture"
        case .recencyBoost:      return "Recently posted"
        case .curatedByBerean:   return "Berean recommendation"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("PostProvenanceSheet") {
    Color.black.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            PostProvenanceSheet(
                postId: "preview_post_001",
                isPresented: .constant(true)
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
}
#endif
