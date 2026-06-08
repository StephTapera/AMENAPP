// NeedDetectionView.swift
// AMENAPP — Need Detection View
//
// Shows community need detection cards: expressed needs from the user's network.
// Privacy-first: no PII, always "Someone in your community needs..."
// No count-based language anywhere.
//
// States: loading, populated, empty, error
//
// Actions:
//   SHOW_UP → Maps/location or org website (via notImplementedSheet for now)
//   GIVE    → Donation flow (via notImplementedSheet)
//   PRAY    → Opens PrayerComposer (via Notification)
//
// Empty state: scripture encouragement + "Your community needs are met right now"

import SwiftUI

// MARK: - NeedDetectionView

struct NeedDetectionView: View {

    @StateObject private var viewModel = NeedDetectionViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                loadingView
            case .populated:
                populatedView
            case .empty:
                emptyView
            case .error(let message):
                errorView(message)
            case .offlineStale:
                populatedView
                    .overlay(alignment: .top) { offlineBanner }
            case .sensitive:
                emptyView
            }
        }
        .task { await viewModel.load() }
        .sheet(item: $viewModel.notImplementedAction) { action in
            IntelligenceNotImplementedSheet(
                cardTitle: viewModel.titleForAction(action),
                actionLabel: action.label
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Community need cards")
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .accessibilityLabel("Loading community need cards")
            Text("Scanning your community…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Populated

    private var populatedView: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(viewModel.cards) { card in
                    IntelligenceCardView(card: card) { action in
                        viewModel.handleAction(action, on: card)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .refreshable {
            await viewModel.load()
        }
        .accessibilityLabel("Community need cards")
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.fill")
                .font(.systemScaled(48))
                .foregroundStyle(Color(red: 0.2, green: 0.6, blue: 0.4))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Your Community Needs Are Met Right Now")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("No unmet needs detected in your network right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            // Scripture encouragement
            VStack(spacing: 6) {
                Text("\"And my God will supply every need of yours according to his riches in glory in Christ Jesus.\"")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .italic()
                    .multilineTextAlignment(.center)

                Text("— Philippians 4:19")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your community needs are met right now. Philippians 4:19: And my God will supply every need of yours.")
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Couldn't Load Community Needs")
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Retries loading community need cards")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        Text("Showing cached needs — you're offline")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
            .accessibilityLabel("Offline. Showing cached community need cards.")
    }
}

// MARK: - NeedDetectionViewModel

@MainActor
private final class NeedDetectionViewModel: ObservableObject {

    @Published var state:               IntelligenceUIState = .loading
    @Published var cards:               [IntelligenceCard]  = []
    @Published var notImplementedAction: CardAction?        = nil

    private let service = EventPrayerNeedService.shared

    func load() async {
        state = .loading
        do {
            let fetched = try await service.fetchNeedCards()
            cards = fetched
            state = fetched.isEmpty ? .empty : .populated
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func handleAction(_ action: CardAction, on card: IntelligenceCard) {
        Task {
            try? await service.recordAction(
                cardId:   card.id,
                rung:     action.rung,
                targetId: action.target
            )
        }

        switch action.handler {
        case "intelligence.pray":
            // Route to PrayerComposer via existing notification pattern
            NotificationCenter.default.post(
                name: Notification.Name("amen.openPrayerComposer"),
                object: action.target
            )

        case "intelligence.show_up":
            // Location/website for volunteering — show not-implemented until
            // Maps/deep-link integration is wired in the VolunteerOS layer
            notImplementedAction = action

        case "intelligence.give":
            // Donation flow — show not-implemented until DonationOS is wired
            notImplementedAction = action

        default:
            notImplementedAction = action
        }
    }

    func titleForAction(_ action: CardAction) -> String {
        cards.first(where: { card in
            card.actions.contains(where: { $0.id == action.id })
        })?.title ?? "Community Need"
    }
}
