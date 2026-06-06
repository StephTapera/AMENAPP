// EventIntelligenceView.swift
// AMENAPP — Event Intelligence
//
// Displays event-matched IntelligenceCard[] for the current user.
// States: loading, populated, empty, error
//
// Privacy invariants:
//   - No count-based UI ("N attending" is forbidden)
//   - All cards are finite (no infinite scroll, no load-more)
//   - RSVP confirmation sheet shown inline on SHOW_UP action

import SwiftUI
import FirebaseAuth

// MARK: - EventIntelligenceView

struct EventIntelligenceView: View {

    @StateObject private var viewModel = EventIntelligenceViewModel()
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
        .sheet(item: $viewModel.rsvpConfirmCard) { card in
            RSVPConfirmationSheet(card: card) {
                Task { await viewModel.confirmRSVP(for: card) }
            }
        }
        .sheet(item: $viewModel.notImplementedAction) { action in
            IntelligenceNotImplementedSheet(
                cardTitle: viewModel.titleForAction(action),
                actionLabel: action.label
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Event intelligence")
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .accessibilityLabel("Loading event cards")
            Text("Finding events for you…")
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
        .accessibilityLabel("Event cards, \(viewModel.cards.count) items")
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Upcoming Events")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Follow churches to see upcoming events and services here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No upcoming events. Follow churches to see events here.")
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Couldn't Load Events")
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
            .accessibilityHint("Retries loading event cards")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        Text("Showing cached events — you're offline")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
            .accessibilityLabel("Offline. Showing cached events.")
    }
}

// MARK: - RSVP Confirmation Sheet

private struct RSVPConfirmationSheet: View {
    let card: IntelligenceCard
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                Text(card.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("You're all set. Your RSVP has been recorded.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Done") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Confirm RSVP for \(card.title)")
            }
            .padding(32)
            .navigationTitle("RSVP Confirmed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - EventIntelligenceViewModel

@MainActor
private final class EventIntelligenceViewModel: ObservableObject {

    @Published var state:               IntelligenceUIState = .loading
    @Published var cards:               [IntelligenceCard]  = []
    @Published var rsvpConfirmCard:     IntelligenceCard?   = nil
    @Published var notImplementedAction: CardAction?        = nil

    private let service = EventPrayerNeedService.shared

    func load() async {
        state = .loading
        do {
            let fetched = try await service.fetchEventCards()
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
        case "intelligence.rsvp":
            rsvpConfirmCard = card
        case "intelligence.pray":
            notImplementedAction = action
        case "intelligence.learn":
            notImplementedAction = action
        default:
            notImplementedAction = action
        }
    }

    func confirmRSVP(for card: IntelligenceCard) async {
        // Optimistic removal — RSVP'ed events leave the list
        cards.removeAll { $0.id == card.id }
        if cards.isEmpty { state = .empty }
    }

    func titleForAction(_ action: CardAction) -> String {
        cards.first(where: { card in
            card.actions.contains(where: { $0.id == action.id })
        })?.title ?? "Event"
    }
}
