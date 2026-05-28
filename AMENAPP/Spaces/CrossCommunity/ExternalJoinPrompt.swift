// ExternalJoinPrompt.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// Glass card shown ONCE when an external member first enters a shared Space.
// "You're joining as a visitor from [Community Name]"
// [Join as visitor] → writes spaces/{spaceId}/members/{userId}
//
// Shown by SpaceDetailView when:
//   - space.sharedWith contains the user's homeCommunityId, AND
//   - spaces/{spaceId}/members/{userId} does not yet exist.
//
// Spring present/dismiss. Never shown again after join.

import SwiftUI

struct ExternalJoinPrompt: View {

    // MARK: - Parameters

    let spaceId: String
    let spaceTitle: String
    let homeCommunityName: String
    let homeCommunityId: String

    /// Called after successful join write.
    var onJoined: () -> Void
    /// Called when the user dismisses without joining.
    var onDismiss: () -> Void

    // MARK: - State

    @State private var isJoining: Bool = false
    @State private var joinError: String? = nil
    @State private var isVisible: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let service = CrossCommunityLinkService.shared

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Scrim
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Glass card
            cardContent
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .offset(y: isVisible ? 0 : 120)
                .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Motion.liquidSpring) {
                isVisible = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Visitor join prompt")
    }

    // MARK: - Card

    private var cardContent: some View {
        VStack(spacing: 0) {
            // Top glyph
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.amenPurple.opacity(0.12))
                    .frame(width: 60, height: 60)
                LinkedCommunityGlyph(size: 24, communityName: homeCommunityName)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Title
            Text("You're joining as a visitor")
                .font(.title3.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // Subtitle
            Text("from \(homeCommunityName)")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.amenPurple)
                .padding(.top, 4)

            // Body
            Text("You can participate in \"\(spaceTitle)\" as a visitor. Your community membership is visible to members here.")
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 10)

            if let errorText = joinError {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.buttonDestructive)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            // Actions
            VStack(spacing: 10) {
                Button {
                    Task { await join() }
                } label: {
                    HStack(spacing: 8) {
                        if isJoining {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.small)
                        }
                        Text(isJoining ? "Joining…" : "Join as visitor")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AmenTheme.Colors.amenGold, in: RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(isJoining)
                .accessibilityLabel("Join \(spaceTitle) as visitor from \(homeCommunityName)")

                Button("Not now") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .accessibilityLabel("Dismiss join prompt")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                    .fill(AmenTheme.Colors.backgroundPrimary)
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                    .fill(LiquidGlassTokens.blurElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 28, x: 0, y: 10)
    }

    // MARK: - Actions

    private func join() async {
        isJoining = true
        joinError = nil
        do {
            try await service.joinAsExternalMember(
                spaceId: spaceId,
                homeCommunityId: homeCommunityId
            )
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Motion.liquidSpring) {
                isVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onJoined() }
        } catch {
            joinError = error.localizedDescription
        }
        isJoining = false
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Motion.liquidSpring) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onDismiss() }
    }
}

#if DEBUG
#Preview("ExternalJoinPrompt") {
    ExternalJoinPrompt(
        spaceId: "space_1",
        spaceTitle: "Romans Study",
        homeCommunityName: "Hillside Community",
        homeCommunityId: "community_2",
        onJoined: {},
        onDismiss: {}
    )
}
#endif
