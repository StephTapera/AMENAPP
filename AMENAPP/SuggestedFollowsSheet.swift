//
//  SuggestedFollowsSheet.swift
//  AMENAPP
//
//  System 13: Suggested Follows
//  Compact Liquid Glass half-sheet anchored from the profile header.
//  Shows up to 8 recommended users with reason pills, staggered entrance
//  animation, and a friction banner when FollowBurstCoordinator detects
//  abnormal follow velocity.
//

import SwiftUI

struct SuggestedFollowsSheet: View {
    @StateObject var viewModel: SuggestedFollowsViewModel
    @StateObject private var burstCoordinator = FollowBurstCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Canvas background matching the profile view
                ProfileDesignTokens.canvasBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Friction banner (only shown when coordinator detects burst)
                    if let message = burstCoordinator.frictionState.userMessage {
                        frictionBanner(message)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Group {
                        if viewModel.isLoading {
                            loadingState
                        } else if viewModel.suggestions.isEmpty {
                            emptyState
                        } else {
                            suggestionsList
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: burstCoordinator.frictionState)
            }
            .navigationTitle("Suggested")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.systemScaled(15, weight: .semibold))
                }
            }
            .task {
                await viewModel.loadSuggestions()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(ProfileDesignTokens.canvasBackground)
    }

    // MARK: - Suggestions List

    private var suggestionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header block
                headerBlock
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Rows with stagger
                ForEach(Array(viewModel.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    SuggestedUserRow(
                        recommendation: suggestion,
                        index: index,
                        onFollowed: {
                            viewModel.removeFollowed(userId: suggestion.id)
                        },
                        onDismissed: {
                            viewModel.dismiss(userId: suggestion.id)
                        }
                    )
                    .padding(.horizontal, 16)

                    if suggestion.id != viewModel.suggestions.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }

                // Footer
                footerView
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Header Block

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Suggested to follow")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundStyle(ProfileDesignTokens.textPrimary)

            Text("Based on shared interests, mutual connections, and healthy activity.")
                .font(.systemScaled(13))
                .foregroundStyle(ProfileDesignTokens.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footerView: some View {
        Button {
            Task { await viewModel.loadMoreSuggestions() }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isLoadingMore {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text("See more suggestions")
                        .font(.systemScaled(14, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.systemScaled(12, weight: .medium))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule().strokeBorder(ProfileDesignTokens.hairlineBorder, lineWidth: 0.5)
                    )
            )
        }
        .disabled(viewModel.isLoadingMore)
    }

    // MARK: - Friction Banner

    private func frictionBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: burstCoordinator.frictionState == .cooldown
                  ? "hourglass" : "heart.text.clipboard")
                .font(.systemScaled(15))
                .foregroundStyle(burstCoordinator.frictionState == .cooldown ? .orange : .blue)

            Text(message)
                .font(.systemScaled(13))
                .foregroundStyle(ProfileDesignTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill((burstCoordinator.frictionState == .cooldown ? Color.orange : Color.blue)
                            .opacity(0.06))
                )
        )
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView("Finding people you may know…")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.systemScaled(40))
                .foregroundStyle(.tertiary)
            Text("No suggestions right now")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("We'll have recommendations once you've connected with more people.")
                .font(.systemScaled(14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
