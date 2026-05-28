// LinkedSpaceDetailSection.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// Reusable section for SpaceDetailView (Agent C) showing all active linked
// communities for a Space. Dropped below the hero header by Agent C.
//
// Data source: space.sharedWith (denormalized — NO per-frame Firestore joins).
// Community name resolution is done ONCE on appear via a batch get (not a listener).
//
// Hard constraints:
//   - NO Firestore listener inside this component.
//   - NO per-frame fetches.
//   - Reads only space.sharedWith and performs a single batch getDocument per communityId.
//   - Money never crosses a link — NO pricing or entitlement UI here.
//   - No "church" anywhere.
//   - Import C's components (SharedCommunityBanner, LinkedGlyph) — never re-implement.

import SwiftUI
import FirebaseFirestore

// MARK: - LinkedSpaceDetailSection

/// Section showing cross-community links for a Space.
/// Drop into SpaceDetailView below the hero header.
/// Uses space.sharedWith — no Firestore joins inside.
struct LinkedSpaceDetailSection: View {

    // MARK: - Parameters

    /// The Space being displayed.
    let space: AmenSpaceExtended
    /// Owning community of the Space.
    let communityId: String
    /// Opens LinkSpaceSheet — called when admin taps "Link a community".
    var onManageLinks: () -> Void

    // MARK: - Internal state

    /// Resolved community names keyed by communityId.
    /// Populated once on appear via a batch Firestore get — no listener.
    @State private var communityNames: [String: String] = [:]
    @State private var isResolvingNames: Bool = false

    private let db = Firestore.firestore()

    // MARK: - Body

    var body: some View {
        if !space.sharedWith.isEmpty || canManageLinks {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader

                ForEach(space.sharedWith, id: \.self) { linkedCommunityId in
                    let name = communityNames[linkedCommunityId] ?? linkedCommunityId
                    SharedCommunityBanner(mode: .sharedWith(communityName: name))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if canManageLinks {
                    manageLinkButton
                }
            }
            .task(id: space.sharedWith.joined()) {
                await resolveNames(for: space.sharedWith)
            }
        }
    }

    // MARK: - Section header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            LinkedGlyph(size: .small)
            Text("Linked communities")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            Spacer(minLength: 0)

            if isResolvingNames {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Resolving community names")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Linked communities section")
    }

    // MARK: - Manage link button (admin-only)

    /// Whether to show the "Link a community" button.
    /// In v1 this is always shown (role-gating happens in SpaceDetailView before
    /// the section is rendered). Agent C owns the conditional rendering.
    private var canManageLinks: Bool { true }

    private var manageLinkButton: some View {
        Button(action: onManageLinks) {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)

                Text("Link a community")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(AmenTheme.Colors.amenPurple.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .stroke(AmenTheme.Colors.amenPurple.opacity(0.22), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Link a community to this Space")
        .accessibilityHint("Double-tap to open the link community flow.")
    }

    // MARK: - Name resolution (single batch get on appear)

    /// Resolves communityIds from sharedWith to display names via a single batch
    /// of getDocument() calls. Uses no listener — called once per unique sharedWith snapshot.
    private func resolveNames(for communityIds: [String]) async {
        let unresolved = communityIds.filter { communityNames[$0] == nil }
        guard !unresolved.isEmpty else { return }

        isResolvingNames = true

        await withTaskGroup(of: (String, String?).self) { group in
            for communityId in unresolved {
                group.addTask {
                    guard let snap = try? await Firestore.firestore()
                        .collection("amenCommunities")
                        .document(communityId)
                        .getDocument(),
                          snap.exists else {
                        return (communityId, nil)
                    }
                    let name = snap.data()?["name"] as? String
                    return (communityId, name)
                }
            }

            for await (id, name) in group {
                if let name {
                    communityNames[id] = name
                }
            }
        }

        isResolvingNames = false
    }
}

#if DEBUG
#Preview("LinkedSpaceDetailSection") {
    let space = AmenSpaceExtended(
        communityId: "community_local",
        type: .chat,
        title: "Romans Study",
        description: nil,
        avatarURL: nil,
        createdBy: "user_1",
        createdAt: nil,
        accessPolicy: .free,
        priceConfig: nil,
        sharedWith: ["community_a", "community_b"],
        isDeleted: false
    )

    ScrollView {
        LinkedSpaceDetailSection(
            space: space,
            communityId: "community_local",
            onManageLinks: { print("manage links tapped") }
        )
        .padding()
    }
    .background(Color.gray.opacity(0.2))
}
#endif
