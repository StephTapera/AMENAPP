// LinkInviteSheet.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// Glass sheet presented from SpaceDetailView's settings entry point.
// Allows a Space admin/owner to:
//   1. Search for communities by name.
//   2. Send a link invite to a found community.
//   3. See outgoing pending invites and revoke active links.
//
// Design: ultraThinMaterial background, spring animations, Liquid Glass tokens.
// No Combine — async/await only. No "church" anywhere.

import SwiftUI

struct LinkInviteSheet: View {

    // MARK: - Parameters

    let spaceId: String
    let spaceTitle: String
    let communityId: String
    @Binding var isPresented: Bool

    // MARK: - State

    @StateObject private var viewModel = CrossCommunityViewModel()
    @State private var searchQuery: String = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var pendingCommunity: SpacesCommunity? = nil
    @State private var showConfirm: Bool = false
    @State private var alertItem: LinkSheetAlertItem? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Rectangle()
                    .fill(LiquidGlassTokens.blurThin)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        searchSection
                        pendingOutgoingSection
                        linkedSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Link a community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { isPresented = false }
                        .foregroundStyle(AmenTheme.Colors.amenPurple)
                        .accessibilityLabel("Close sheet")
                }
            }
            .alert(item: $alertItem) { item in
                Alert(title: Text("Error"), message: Text(item.message))
            }
            .onChange(of: viewModel.error?.localizedDescription) { _, newValue in
                if let msg = newValue {
                    alertItem = LinkSheetAlertItem(message: msg)
                }
            }
        }
        .task {
            await viewModel.loadForSpace(spaceId: spaceId, communityId: communityId)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Search section

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Find a community")

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                TextField("Search by name…", text: $searchQuery)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: searchQuery) { _, newValue in
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(280))
                            guard !Task.isCancelled else { return }
                            await viewModel.search(query: newValue)
                        }
                    }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        viewModel.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceInput)
            }

            if !viewModel.searchResults.isEmpty {
                searchResultsList
            }
        }
    }

    private var searchResultsList: some View {
        VStack(spacing: 6) {
            ForEach(viewModel.searchResults) { community in
                CommunityResultRow(
                    community: community,
                    isAlreadyLinked: isAlreadyLinked(community),
                    isPending: isPending(community),
                    isSending: viewModel.isSending
                ) {
                    pendingCommunity = community
                    showConfirm = true
                }
            }
        }
        .confirmationDialog(
            "Invite \(pendingCommunity?.name ?? "this community") to share \(spaceTitle)?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Send invite") {
                guard let community = pendingCommunity,
                      let targetId = community.id else { return }
                Task {
                    await viewModel.sendInvite(
                        toCommunityId: targetId,
                        fromCommunityId: communityId,
                        spaceId: spaceId,
                        scope: "Shared: \(spaceTitle)"
                    )
                    searchQuery = ""
                    viewModel.searchResults = []
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Pending outgoing invites

    @ViewBuilder
    private var pendingOutgoingSection: some View {
        let pending = viewModel.outgoingInvites.filter { $0.status == .pending }
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Waiting for response")
                ForEach(pending) { invite in
                    PendingInviteRow(invite: invite)
                }
            }
        }
    }

    // MARK: - Already linked

    @ViewBuilder
    private var linkedSection: some View {
        if !viewModel.linkedCommunities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Linked communities")
                ForEach(viewModel.linkedCommunities) { community in
                    LinkedCommunityRow(community: community) {
                        Task {
                            await viewModel.revokeLink(
                                link: community,
                                spaceId: spaceId,
                                communityId: communityId
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func isAlreadyLinked(_ community: SpacesCommunity) -> Bool {
        guard let id = community.id else { return false }
        return viewModel.linkedCommunities.contains { $0.id == id }
    }

    private func isPending(_ community: SpacesCommunity) -> Bool {
        guard let id = community.id else { return false }
        return viewModel.outgoingInvites.contains {
            ($0.toCommunityId == id || $0.fromCommunityId == id)
            && $0.status == .pending
        }
    }
}

// MARK: - CommunityResultRow

private struct CommunityResultRow: View {
    let community: SpacesCommunity
    let isAlreadyLinked: Bool
    let isPending: Bool
    let isSending: Bool
    let onInvite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SpaceAvatarView(
                avatarURL: community.avatarURL,
                title: community.name,
                size: 40,
                isShared: isAlreadyLinked,
                sharedCommunityName: community.name
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(community.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text("@\(community.handle)")
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            Spacer()
            if isAlreadyLinked {
                Text("Linked")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AmenTheme.Colors.amenPurple.opacity(0.10), in: Capsule())
            } else if isPending {
                Text("Pending")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.10), in: Capsule())
            } else {
                Button("Invite") { onInvite() }
                    .buttonStyle(GlassButtonStyle(color: AmenTheme.Colors.amenGold))
                    .disabled(isSending)
                    .accessibilityLabel("Invite \(community.name) to share this Space")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - PendingInviteRow

private struct PendingInviteRow: View {
    let invite: CommunityLinkRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.callout)
                .foregroundStyle(.orange)
            Text("Waiting for \(invite.toCommunityId) to accept…")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(AmenTheme.Colors.surfaceChip)
        }
    }
}

// MARK: - LinkedCommunityRow

private struct LinkedCommunityRow: View {
    let community: LinkedCommunityRecord
    let onRevoke: () -> Void
    @State private var showRevokeConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            SpaceAvatarView(
                avatarURL: community.avatarURL,
                title: community.name,
                size: 40,
                isShared: true,
                sharedCommunityName: community.name
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(community.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text("\(community.externalMemberCount) member\(community.externalMemberCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            Spacer()
            Button("Revoke") { showRevokeConfirm = true }
                .buttonStyle(GlassButtonStyle(color: AmenTheme.Colors.amenPurple))
                .accessibilityLabel("Revoke link with \(community.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .stroke(AmenTheme.Colors.amenPurple.opacity(0.25), lineWidth: 0.5)
                }
        }
        .confirmationDialog(
            "Remove access for \(community.name)?",
            isPresented: $showRevokeConfirm,
            titleVisibility: .visible
        ) {
            Button("Revoke access", role: .destructive, action: onRevoke)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Members from \(community.name) will lose access to this Space.")
        }
    }
}

// MARK: - GlassButtonStyle

private struct GlassButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(configuration.isPressed ? 0.18 : 0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.30), lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(Motion.springPress, value: configuration.isPressed)
    }
}

// MARK: - LinkSheetAlertItem helper (Identifiable wrapper for error binding)

private struct LinkSheetAlertItem: Identifiable {
    let id = UUID()
    let message: String
}
