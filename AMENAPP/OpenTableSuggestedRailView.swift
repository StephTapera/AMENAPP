// OpenTableSuggestedRailView.swift
// AMENAPP
//
// Surface renderer for the Suggested Accounts rail in the OpenTable feed.
// "Suggested for you" — discovery-first, snappy animations.

import SwiftUI

struct OpenTableSuggestedRailView: View {
    @StateObject private var vm = SuggestedRailViewModel(surface: .openTable)
    @State private var profileSheetUserId: String?
    @State private var peekItem: SuggestionItem?
    @State private var showWhyShownAlert = false

    private let config = SuggestionRailConfig.openTable

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
        .sheet(item: $peekItem) { item in
            SuggestedAccountPeekSheet(item: item, surface: .openTable) { userId in
                profileSheetUserId = userId
            }
            .presentationDetents([.fraction(0.45), .fraction(0.90)])
            .presentationCornerRadius(32)
            .presentationBackground(.ultraThinMaterial)
            .presentationDragIndicator(.visible)
        }
        .alert("Why am I seeing this?", isPresented: $showWhyShownAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(SuggestionSurface.openTable.whyShownExplanation)
        }
    }

    // MARK: - Loaded State

    private var loadedModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            SuggestedRailHeader(
                surface: .openTable,
                onHide: { vm.hideModule() },
                onShowFewer: {
                    SuggestedRailAnalytics.trackShowFewer(surface: .openTable)
                },
                onWhyShown: {
                    SuggestedRailAnalytics.trackWhyShown(surface: .openTable)
                    showWhyShownAlert = true
                }
            )
            horizontalRail
        }
        .padding(.vertical, 14)
        .onAppear {
            AMENAnalyticsService.shared.track(.suggestionsRailSeen(count: vm.items.count))
        }
    }

    private var horizontalRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(vm.items) { item in
                    SuggestedAccountCard(
                        item: item,
                        surface: .openTable,
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
                            if AMENFeatureFlags.shared.suggestedRailPeekSheetEnabled {
                                peekItem = item
                            } else {
                                AMENAnalyticsService.shared.track(.suggestionProfileOpen(suggestedUserId: item.id))
                                profileSheetUserId = item.id
                            }
                        },
                        onView: {
                            HapticManager.impact(style: .light)
                            if AMENFeatureFlags.shared.suggestedRailPeekSheetEnabled {
                                peekItem = item
                            } else {
                                AMENAnalyticsService.shared.track(.suggestionProfileOpen(suggestedUserId: item.id))
                                profileSheetUserId = item.id
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92)),
                        removal: .opacity.combined(with: .scale(scale: 0.82).combined(with: .offset(y: 8)))
                    ))
                    .onAppear {
                        vm.loadMoreIfNeeded(currentItem: item)
                        vm.recordImpression(for: item.id)
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
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
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
