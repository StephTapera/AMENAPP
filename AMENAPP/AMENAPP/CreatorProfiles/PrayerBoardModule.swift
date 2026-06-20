// PrayerBoardModule.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3 UI
//
// Public, moderated prayer board. Shows ONLY approved, non-private requests.
//
// HONESTY: the passed-in array is already approved-only from the server, but we defensively
// filter `status == .approved && !isPrivate`. If the viewer's OWN pending requests are passed
// in (status == .pending), they are surfaced separately with an explicit pending banner — never
// rendered as if live on the public board.
//
// Exact initializer (mandated): PrayerBoardModule(creatorId: String, requests: [CreatorHubPrayerRequest]).
//
// Conventions: white bg / black text; translucent glass rows on plain background (no glass-on-glass);
// AmenTheme.Colors.* tokens; Dynamic Type; VoiceOver labels; reduce-motion safe (optimistic +1
// uses no implicit animation that would conflict with reduce-motion).

import SwiftUI

struct PrayerBoardModule: View {
    let creatorId: String

    @State private var requests: [CreatorHubPrayerRequest]
    @State private var prayedLocally: Set<String> = []        // optimistic "I prayed"
    @State private var localPrayedCounts: [String: Int] = [:] // id → displayed count
    @State private var showingComposer = false

    init(creatorId: String, requests: [CreatorHubPrayerRequest]) {
        self.creatorId = creatorId
        _requests = State(initialValue: requests)
    }

    // Public board = approved & not private only.
    private var publicRequests: [CreatorHubPrayerRequest] {
        requests.filter { $0.status == .approved && !$0.isPrivate }
    }

    // The viewer's own not-yet-public items (if any were passed in).
    private var pendingRequests: [CreatorHubPrayerRequest] {
        requests.filter { $0.status == .pending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !pendingRequests.isEmpty {
                pendingBanner
            }

            if publicRequests.isEmpty {
                emptyState
            } else {
                ForEach(publicRequests) { request in
                    row(for: request)
                }
            }

            Text("That's everything for now.")
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingComposer) {
            PrayerRequestComposer(creatorId: creatorId)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Prayer board")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showingComposer = true
            } label: {
                Label("Request prayer", systemImage: "hands.and.sparkles")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
            .background(
                Capsule().fill(AmenTheme.Colors.buttonPrimary)
            )
            .accessibilityLabel("Request prayer")
            .accessibilityHint("Opens a form to submit a prayer request for review.")
        }
    }

    // MARK: Pending banner (honest)

    private var pendingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your pending requests", systemImage: "clock.badge")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.statusWarning)
            ForEach(pendingRequests) { request in
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.body)
                        .font(.callout)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pending review — not yet public")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AmenTheme.Colors.statusWarning.opacity(0.10))
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Pending review, not yet public. \(request.body)")
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: Row

    private func row(for request: CreatorHubPrayerRequest) -> some View {
        let didPray = prayedLocally.contains(request.id)
        let count = localPrayedCounts[request.id] ?? request.prayedCount

        return VStack(alignment: .leading, spacing: 10) {
            Text(request.body)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let praise = request.praiseReport, !praise.isEmpty {
                Label(praise, systemImage: "sparkles")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.statusSuccess)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(AmenTheme.Colors.statusSuccess.opacity(0.12))
                    )
                    .accessibilityLabel("Praise report. \(praise)")
            }

            HStack(spacing: 12) {
                Button {
                    pray(request)
                } label: {
                    Label(didPray ? "Praying" : "I prayed",
                          systemImage: didPray ? "hands.and.sparkles.fill" : "hands.and.sparkles")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .foregroundStyle(didPray ? AmenTheme.Colors.buttonPrimaryText : AmenTheme.Colors.textPrimary)
                .background(
                    Capsule().fill(didPray ? AmenTheme.Colors.buttonPrimary : AmenTheme.Colors.surfaceChip)
                )
                .disabled(didPray)
                .accessibilityLabel(didPray ? "You prayed for this" : "I prayed")

                Text("\(count) praying")
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenGlassCard(cornerRadius: 18)
        .accessibilityElement(children: .contain)
    }

    // MARK: Optimistic prayer

    private func pray(_ request: CreatorHubPrayerRequest) {
        guard !prayedLocally.contains(request.id) else { return }
        prayedLocally.insert(request.id)
        let base = localPrayedCounts[request.id] ?? request.prayedCount
        localPrayedCounts[request.id] = base + 1
        // Server "prayed" call is wired by the host once the prayed callable exists; the
        // optimistic local state keeps the UI honest about the viewer's own action.
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "hands.and.sparkles")
                .font(.largeTitle)
                .foregroundStyle(AmenTheme.Colors.iconSecondary)
            Text("No prayer requests yet")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("Be the first to ask for prayer.")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No prayer requests yet. Be the first to ask for prayer.")
    }
}

#if DEBUG
#Preview("PrayerBoardModule") {
    ScrollView {
        PrayerBoardModule(creatorId: "demo", requests: [
            CreatorHubPrayerRequest(id: "1", creatorId: "demo", authorId: "u1",
                                    body: "Please pray for my mother's recovery.",
                                    isPrivate: false, status: .approved,
                                    prayedCount: 12, praiseReport: nil),
            CreatorHubPrayerRequest(id: "2", creatorId: "demo", authorId: "u2",
                                    body: "Thankful — got the job!",
                                    isPrivate: false, status: .approved,
                                    prayedCount: 30, praiseReport: "Answered!")
        ])
    }
    .background(AmenTheme.Colors.backgroundPrimary)
}
#endif
