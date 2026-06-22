// ModerationQueueView.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3 UI
//
// Creator-facing moderation queue. Lists PENDING prayer + community items and offers
// Approve / Reject / Hide per row, calling CreatorHubService.moderate(creatorId:target:refId:action:).
// On action we optimistically remove the row from the queue (and re-insert on failure).
//
// Conventions: white bg / black text; translucent glass rows on plain background (no
// glass-on-glass); AmenTheme.Colors.* tokens; Dynamic Type; VoiceOver labels; reduce-motion safe.

import SwiftUI

struct ModerationQueueView: View {
    let creatorId: String

    @State private var prayerItems: [CreatorHubPrayerRequest]
    @State private var communityItems: [CreatorHubCommunityPost]
    @State private var inFlight: Set<String> = []
    @State private var errorMessage: String?

    /// Wire targets for the moderate callable.
    private enum Target {
        static let prayer = "prayer"
        static let community = "community"
    }
    private enum Action {
        static let approve = "approve"
        static let reject  = "reject"
        static let hide    = "hide"
    }

    init(
        creatorId: String,
        prayerItems: [CreatorHubPrayerRequest] = [],
        communityItems: [CreatorHubCommunityPost] = []
    ) {
        self.creatorId = creatorId
        _prayerItems = State(initialValue: prayerItems.filter { $0.status == .pending })
        _communityItems = State(initialValue: communityItems.filter { $0.status == .pending })
    }

    private var isEmpty: Bool { prayerItems.isEmpty && communityItems.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(AmenTheme.Colors.statusError)
            }

            if isEmpty {
                emptyState
            } else {
                if !prayerItems.isEmpty {
                    sectionTitle("Prayer requests")
                    ForEach(prayerItems) { item in
                        moderationRow(
                            id: item.id,
                            target: Target.prayer,
                            body: item.body,
                            badge: item.isPrivate ? "Private" : "Public"
                        )
                    }
                }
                if !communityItems.isEmpty {
                    sectionTitle("Community posts")
                    ForEach(communityItems) { item in
                        moderationRow(
                            id: item.id,
                            target: Target.community,
                            body: item.body,
                            badge: kindLabel(item.kind)
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header / section

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Review queue")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Approve what's ready, set aside the rest.")
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Row

    private func moderationRow(id: String, target: String, body: String, badge: String) -> some View {
        let busy = inFlight.contains(id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(body)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(badge)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AmenTheme.Colors.surfaceChip))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 10) {
                actionButton("Approve", systemImage: "checkmark", tint: AmenTheme.Colors.statusSuccess, busy: busy) {
                    Task { await act(id: id, target: target, action: Action.approve) }
                }
                actionButton("Reject", systemImage: "xmark", tint: AmenTheme.Colors.statusError, busy: busy) {
                    Task { await act(id: id, target: target, action: Action.reject) }
                }
                actionButton("Hide", systemImage: "eye.slash", tint: AmenTheme.Colors.textSecondary, busy: busy) {
                    Task { await act(id: id, target: target, action: Action.hide) }
                }
                Spacer(minLength: 0)
                if busy { ProgressView() }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenGlassCard(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(badge) item pending review. \(body)")
    }

    private func actionButton(_ label: String, systemImage: String, tint: Color, busy: Bool, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(label, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(Capsule().fill(tint.opacity(0.12)))
        .disabled(busy)
        .accessibilityLabel(label)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(AmenTheme.Colors.statusSuccess)
            Text("All caught up")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("Nothing is waiting for review.")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("All caught up. Nothing is waiting for review.")
    }

    // MARK: Moderate (optimistic)

    private func act(id: String, target: String, action: String) async {
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        errorMessage = nil

        // Optimistic removal — snapshot for rollback.
        let removedPrayer = prayerItems.first(where: { $0.id == id })
        let removedCommunity = communityItems.first(where: { $0.id == id })
        prayerItems.removeAll { $0.id == id }
        communityItems.removeAll { $0.id == id }

        do {
            try await CreatorHubService.shared.moderate(
                creatorId: creatorId, target: target, refId: id, action: action
            )
        } catch {
            // Roll back on failure.
            if let removedPrayer { prayerItems.append(removedPrayer) }
            if let removedCommunity { communityItems.append(removedCommunity) }
            errorMessage = "Couldn't apply that action. Please try again."
        }
        inFlight.remove(id)
    }

    // MARK: Labels

    private func kindLabel(_ kind: CreatorHubCommunityKind) -> String {
        switch kind {
        case .question:        return "Question"
        case .testimony:       return "Testimony"
        case .studyNote:       return "Study note"
        case .eventDiscussion: return "Discussion"
        }
    }
}

#if DEBUG
#Preview("ModerationQueueView") {
    ScrollView {
        ModerationQueueView(
            creatorId: "demo",
            prayerItems: [
                CreatorHubPrayerRequest(id: "p1", creatorId: "demo", authorId: "u1",
                                        body: "Pray for my exams.", isPrivate: false,
                                        status: .pending, prayedCount: 0, praiseReport: nil)
            ],
            communityItems: [
                CreatorHubCommunityPost(id: "c1", creatorId: "demo", authorId: "u2",
                                        kind: .testimony, body: "God healed my friend.",
                                        parentRef: nil, status: .pending)
            ]
        )
    }
    .background(AmenTheme.Colors.backgroundPrimary)
}
#endif
