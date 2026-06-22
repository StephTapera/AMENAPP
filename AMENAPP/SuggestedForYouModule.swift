// SuggestedForYouModule.swift
// AMENAPP
//
// Thin wrapper for the OpenTable feed's "Suggested for you" rail.
// All logic is now delegated to the extracted shared framework:
//   SuggestedRailModels, SuggestedRailService, SuggestedRailViewModel,
//   SuggestionFollowButton, SuggestionAvatarView, SuggestionSkeletonCard.
//
// This file preserves the same public API so existing call sites
// (e.g. ContentView.swift) continue to work unchanged.

import SwiftUI

// MARK: - Module Container

struct SuggestedForYouModule: View {
    @StateObject private var vm = SuggestedRailViewModel(surface: .openTable)
    @State private var profileSheetUserId: String?

    var body: some View {
        Group {
            if vm.isModuleHidden {
                hiddenBanner
            } else if vm.isLoading && vm.items.isEmpty {
                loadingRail
            } else if vm.items.isEmpty {
                EmptyView()
            } else {
                loadedModule
            }
        }
        .task { await vm.load() }
        .sheet(item: $profileSheetUserId) { userId in
            UserProfileView(userId: userId, showsDismissButton: true)
        }
    }

    // MARK: - Loaded State

    private var loadedModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader
            horizontalRail
        }
        .padding(.vertical, 14)
        .onAppear {
            AMENAnalyticsService.shared.track(.suggestionsRailSeen(count: vm.items.count))
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggested for you")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Based on community, trust, and shared activity")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                HapticManager.impact(style: .light)
                vm.hideModule()
            } label: {
                Text("Hide")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide suggestions")
        }
        .padding(.horizontal, 16)
    }

    private var horizontalRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(vm.items) { item in
                    SuggestedAccountCardView(
                        item: item,
                        followState: vm.effectiveFollowState(for: item.id),
                        isLoadingFollow: vm.isLoadingFollow(for: item.id),
                        onFollow: {
                            HapticManager.impact(style: .medium)
                            Task { await vm.follow(id: item.id) }
                        },
                        onCancelRequest: {
                            HapticManager.impact(style: .light)
                            Task { await vm.cancelRequest(id: item.id) }
                        },
                        onUnfollow: {
                            HapticManager.impact(style: .light)
                            Task { await vm.unfollow(id: item.id) }
                        },
                        onDismiss: {
                            HapticManager.impact(style: .light)
                            vm.dismiss(id: item.id)
                        },
                        onOpenProfile: {
                            HapticManager.impact(style: .light)
                            AMENAnalyticsService.shared.track(.suggestionProfileOpen(suggestedUserId: item.id))
                            profileSheetUserId = item.id
                        },
                        onView: {
                            HapticManager.impact(style: .light)
                            AMENAnalyticsService.shared.track(.suggestionProfileOpen(suggestedUserId: item.id))
                            profileSheetUserId = item.id
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92)),
                        removal: .opacity.combined(with: .scale(scale: 0.82).combined(with: .offset(y: 8)))
                    ))
                    .onAppear {
                        vm.loadMoreIfNeeded(currentItem: item)
                        if let position = vm.items.firstIndex(where: { $0.id == item.id }) {
                            AMENAnalyticsService.shared.track(.suggestionImpression(
                                suggestedUserId: item.id,
                                position: position,
                                reasonType: item.reasonType.rawValue
                            ))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    // MARK: - Loading Skeleton

    private var loadingRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(width: 130, height: 14)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemFill).opacity(0.6))
                        .frame(width: 200, height: 10)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in
                        SuggestionSkeletonCard()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: - Hidden Banner

    private var hiddenBanner: some View {
        HStack(spacing: 10) {
            Text("Suggestions hidden")
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Show again") {
                HapticManager.impact(style: .light)
                vm.restoreModule()
            }
            .font(.systemScaled(13, weight: .medium))
            .foregroundStyle(.primary)
            .accessibilityLabel("Show suggestions again")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .buttonStyle(.plain)
    }
}

// MARK: - String+Identifiable for sheet binding

extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Suggested Account Card

struct SuggestedAccountCardView: View {
    let item: SuggestionItem
    let followState: FollowStateManager.FollowState
    let isLoadingFollow: Bool
    let onFollow: () -> Void
    let onCancelRequest: () -> Void
    let onUnfollow: () -> Void
    let onDismiss: () -> Void
    let onOpenProfile: () -> Void
    let onView: () -> Void

    @State private var showUnfollowConfirm = false

    private let cardWidth: CGFloat = 168
    private let cardHeight: CGFloat = 240

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardBody
            dismissButton
        }
        .frame(width: cardWidth)
        .confirmationDialog("Unfollow @\(item.handle)?", isPresented: $showUnfollowConfirm, titleVisibility: .visible) {
            Button("Unfollow", role: .destructive) {
                onUnfollow()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Card Body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            identitySection
                .padding(.horizontal, 12)
                .padding(.top, 14)

            reasonSection
                .padding(.horizontal, 12)
                .padding(.top, 6)

            if item.mutualCount > 0 || item.contextLine != nil {
                mutualContextRow
                    .padding(.horizontal, 12)
                    .padding(.top, 5)
            }

            Spacer(minLength: 0)

            actionButtons
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background { glassBackground }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.displayName), @\(item.handle). \(item.reasonText)")
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: onOpenProfile) {
                SuggestionAvatarView(item: item, size: 48)
            }
            .buttonStyle(.plain)

            HStack(spacing: 3) {
                Text(item.displayName)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if item.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.systemScaled(11))
                        .foregroundStyle(Color.accentColor)
                }
            }

            Text("@\(item.handle)")
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Reason Section

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.reasonText)
                .font(.systemScaled(11, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.9))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let badge = item.accountType.badge {
                Text(badge)
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.systemFill)))
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Mutual Context Row

    private var mutualContextRow: some View {
        HStack(spacing: 4) {
            if !item.mutualAvatarURLs.isEmpty {
                mutualAvatarStack
            }

            if let context = item.contextLine {
                Text(context)
                    .font(.systemScaled(10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if item.mutualCount > 0 {
                Text("Mutuals · community")
                    .font(.systemScaled(10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var mutualAvatarStack: some View {
        HStack(spacing: -6) {
            ForEach(Array(item.mutualAvatarURLs.prefix(3).enumerated()), id: \.offset) { index, urlString in
                AsyncImage(url: URL(string: urlString)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Circle().fill(Color(.systemGray5))
                    }
                }
                .frame(width: 16, height: 16)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                .zIndex(Double(3 - index))
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 6) {
            SuggestionFollowButton(
                state: followState,
                isLoading: isLoadingFollow,
                onFollow: onFollow,
                onCancelRequest: onCancelRequest,
                onUnfollow: {
                    showUnfollowConfirm = true
                }
            )

            Button(action: onView) {
                Text("View")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.55))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
                            )
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(item.displayName)'s profile")
        }
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.systemScaled(9, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.7))
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .fill(Color(.systemBackground).opacity(0.55))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel("Dismiss \(item.displayName)")
    }

    // MARK: - Glass Background

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.45), Color.clear],
                            startPoint: .top,
                            endPoint: .init(x: 0.5, y: 0.3)
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.70), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
    }
}
