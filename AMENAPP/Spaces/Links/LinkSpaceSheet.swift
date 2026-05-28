// LinkSpaceSheet.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// "Link a community" flow initiated from an existing Space by its owner/admin.
// Create-first / link-second — this sheet only links EXISTING Spaces.
//
// Flow:
//   1. Search step — text field "@handle", debounced 500ms.
//   2. Confirm step — hero invite card + Send invite button.
//   3. Pending state — after invite sent, shows status + Cancel invite option.
//   4. Error — inline display.
//
// Design: AmenLiquidGlassBottomSheet wrapper, tokens only, no local color literals.
// No "church" anywhere.

import SwiftUI

struct LinkSpaceSheet: View {

    // MARK: - Parameters

    /// The Space being shared. Must already exist — create-first / link-second.
    let space: AmenSpaceExtended
    /// The communityId that owns the Space.
    let communityId: String
    @Binding var isPresented: Bool

    // MARK: - State

    @StateObject private var service = SpacesLinksService()
    @State private var inviteState: LinkInviteState = .idle
    @State private var handleInput: String = ""
    @State private var debounceTask: Task<Void, Never>? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        AmenLiquidGlassBottomSheet(
            title: "Link a community",
            subtitle: "Share \"\(space.title)\" with another community",
            aiDisclosure: nil,
            content: {
                VStack(spacing: 20) {
                    searchStep
                    stateContent
                }
                .padding(.bottom, 8)
            },
            footer: {
                Button("Cancel") { isPresented = false }
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel("Close sheet")
            }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Search step

    private var searchStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find by @handle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 10) {
                Image(systemName: "at")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)

                TextField("handle", text: $handleInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: handleInput) { _, newValue in
                        scheduleSearch(handle: newValue)
                    }
                    .accessibilityLabel("Search by community handle")

                if case .searching = inviteState {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Searching")
                } else if !handleInput.isEmpty {
                    Button {
                        handleInput = ""
                        inviteState = .idle
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    .accessibilityLabel("Clear handle")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceInput)
            }

            // "No result" hint
            if handleInput.count > 1 {
                if case .idle = inviteState {
                    Text("No community found for @\(handleInput).")
                        .font(.footnote)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
        }
    }

    // MARK: - State-driven content

    @ViewBuilder
    private var stateContent: some View {
        switch inviteState {
        case .idle, .searching:
            EmptyView()

        case .found(let community):
            foundCommunityCard(community: community)

        case .pendingAcceptance(let linkId):
            pendingCard(linkId: linkId)

        case .active:
            activeBadge

        case .error(let message):
            errorCard(message: message)
        }
    }

    // MARK: - Found community card (confirm step)

    private func foundCommunityCard(community: AmenCommunity) -> some View {
        VStack(spacing: 16) {
            // Hero invite card: your community → link → target community
            heroInviteCard(targetCommunity: community)

            Text("Members from \(community.name) will see this Space.")
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Text("Members from your community will appear in \(community.name)'s member list.")
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            AmenLiquidGlassPillButton(
                title: "Send invite",
                systemImage: "link",
                isLoading: service.isLoading,
                isDisabled: false,
                hint: "Double-tap to send community link invitation."
            ) {
                guard let targetId = community.id else { return }
                sendInvite(targetCommunityId: targetId)
            }
            .accessibilityLabel("Send invite to \(community.name)")
        }
        .padding(.horizontal, 4)
        .animation(reduceMotion ? .easeOut(duration: 0.16) : Motion.liquidSpring, value: inviteState)
    }

    // MARK: - Hero invite card

    private func heroInviteCard(targetCommunity: AmenCommunity) -> some View {
        HStack(spacing: 16) {
            // Source (owning community) — placeholder initials avatar
            communityAvatar(avatarURL: nil, name: communityId, size: 48)

            LinkedGlyph(size: .large)

            // Target community avatar
            communityAvatar(
                avatarURL: targetCommunity.avatarURL,
                name: targetCommunity.name,
                size: 48
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Linking your community with \(targetCommunity.name)")
    }

    // MARK: - Community avatar helper

    private func communityAvatar(avatarURL: String?, name: String, size: CGFloat) -> some View {
        SpaceAvatarView(
            avatarURL: avatarURL,
            title: name,
            size: size,
            isShared: false
        )
    }

    // MARK: - Pending card

    private func pendingCard(linkId: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)

                Text("Invite sent. Waiting for the other community to accept.")
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceChip)
            }

            // Cancel invite (revokes the link)
            Button {
                Task {
                    do {
                        try await service.revokeLink(linkId: linkId, communityId: communityId)
                        withAnimation(reduceMotion ? .easeOut : Motion.liquidSpring) {
                            inviteState = .idle
                        }
                    } catch {
                        inviteState = .error(error.localizedDescription)
                    }
                }
            } label: {
                Text("Cancel invite")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
            }
            .accessibilityLabel("Cancel the pending invite")
        }
        .animation(reduceMotion ? .easeOut(duration: 0.16) : Motion.liquidSpring, value: inviteState)
    }

    // MARK: - Active badge

    private var activeBadge: some View {
        SharedCommunityBanner(mode: .sharedWith(communityName: "community"))
            .frame(maxWidth: .infinity)
    }

    // MARK: - Error card

    private func errorCard(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AmenTheme.Colors.statusError)
            Text(message)
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.statusError)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .fill(AmenTheme.Colors.statusError.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .stroke(AmenTheme.Colors.statusError.opacity(0.25), lineWidth: 0.5)
        }
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Actions

    private func scheduleSearch(handle: String) {
        debounceTask?.cancel()
        let trimmed = handle.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        guard trimmed.count > 1 else {
            inviteState = .idle
            return
        }

        inviteState = .searching

        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            do {
                if let community = try await service.searchCommunity(handle: trimmed) {
                    inviteState = .found(community: community)
                } else {
                    inviteState = .idle
                }
            } catch {
                inviteState = .error(error.localizedDescription)
            }
        }
    }

    private func sendInvite(targetCommunityId: String) {
        guard let spaceId = space.id else { return }
        Task {
            do {
                let linkId = try await service.inviteToLink(
                    fromCommunityId: communityId,
                    targetCommunityId: targetCommunityId,
                    spaceId: spaceId
                )
                withAnimation(reduceMotion ? .easeOut(duration: 0.16) : Motion.liquidSpring) {
                    inviteState = .pendingAcceptance(linkId: linkId)
                }
            } catch {
                inviteState = .error(error.localizedDescription)
            }
        }
    }
}
