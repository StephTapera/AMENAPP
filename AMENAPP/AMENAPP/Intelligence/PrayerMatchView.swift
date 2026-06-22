// PrayerMatchView.swift
// AMENAPP — Prayer Match View
//
// Shows prayer matching cards: requests from network that match user's prayer capacity.
// Privacy-first: no names unless public, no counts anywhere.
//
// States: loading, populated, empty, error
//
// Primary action: PRAY → posts notification to open PrayerComposer (uses existing
//   Notification.Name("amen.openPrayerComposer") to avoid tight coupling)
// Secondary action: DISCUSS → not-implemented sheet
// Loop-closing: "Follow up on your prayer" banner when loopParentId is set

import SwiftUI
import FirebaseAuth

// MARK: - PrayerMatchView

struct PrayerMatchView: View {

    @StateObject private var viewModel = PrayerMatchViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var reportingCard: IntelligenceCard?
    @State private var showingReportSheet = false

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
        .sheet(isPresented: $showingReportSheet) {
            if let card = reportingCard {
                ReportContentSheet(
                    targetType: .post,
                    targetId: card.id,
                    onSubmitted: { _ in showingReportSheet = false },
                    onDismiss: { showingReportSheet = false }
                )
                .presentationDetents([.medium])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Prayer match cards")
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .accessibilityLabel("Loading prayer cards")
            Text("Checking your prayer network…")
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
                    VStack(alignment: .leading, spacing: 4) {
                        // Loop-closing banner above the card
                        if card.formation.loopParentId != nil {
                            loopFollowUpBanner(for: card)
                        }
                        IntelligenceCardView(card: card) { action in
                            viewModel.handleAction(action, on: card)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                reportingCard = card
                                showingReportSheet = true
                            } label: {
                                Label("Report prayer request", systemImage: "flag")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .refreshable {
            await viewModel.load()
        }
        .accessibilityLabel("Prayer match cards")
    }

    // MARK: - Loop Follow-Up Banner

    private func loopFollowUpBanner(for card: IntelligenceCard) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
                .accessibilityHidden(true)

            Text("Follow up on your prayer from last week")
                .font(.caption)
                .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.1), in: Capsule())
        .accessibilityLabel("Follow up: continuing a prayer you started last week")
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "hands.sparkles")
                .font(.systemScaled(48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Your Network Is Quiet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("No prayer requests to match right now. Check back later or share your own.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your network is quiet. No prayer requests to match right now.")
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Couldn't Load Prayer Cards")
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
            .accessibilityHint("Retries loading prayer cards")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        Text("Showing cached prayers — you're offline")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
            .accessibilityLabel("Offline. Showing cached prayer cards.")
    }
}

// MARK: - PrayerMatchViewModel

@MainActor
private final class PrayerMatchViewModel: ObservableObject {

    @Published var state:               IntelligenceUIState = .loading
    @Published var cards:               [IntelligenceCard]  = []
    @Published var notImplementedAction: CardAction?        = nil

    private let service = EventPrayerNeedService.shared

    func load() async {
        state = .loading
        do {
            let fetched = try await service.fetchPrayerCards()
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
            // Open existing PrayerComposer via notification — avoids tight coupling
            NotificationCenter.default.post(
                name: Notification.Name("amen.openPrayerComposer"),
                object: action.target
            )

        case "intelligence.pray_discuss":
            notImplementedAction = action

        default:
            notImplementedAction = action
        }
    }

    func titleForAction(_ action: CardAction) -> String {
        cards.first(where: { card in
            card.actions.contains(where: { $0.id == action.id })
        })?.title ?? "Prayer"
    }
}
