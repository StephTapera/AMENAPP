import Foundation
import SwiftUI
import Combine

@MainActor
final class BereanPulseViewModel: ObservableObject {
    @Published private(set) var cards: [BereanPulseCard] = []
    @Published private(set) var signals: [BereanPulseSignal] = []
    @Published var selectedMode: BereanPulseMode = .all
    @Published var expandedCardIds: Set<String> = []
    @Published var feedState: BereanPulseFeedState = .loading
    @Published var showCurateSheet = false
    @Published var permissionPromptContext: BereanPulsePermissionPromptContext?
    @Published var preferences: BereanPulsePreference = .default
    @Published var signalsCollapsed = false
    @Published var lastErrorMessage: String?
    @Published var actionUnavailableMessage: String?

    let service: BereanPulseService
    let permissionManager: BereanPulsePermissionManager
    let actionRouter: BereanPulseActionRouter
    private var observationTask: Task<Void, Never>?
    private var currentSnapshotSource: BereanPulseSnapshotSource = .live

    init(
        service: BereanPulseService? = nil,
        permissionManager: BereanPulsePermissionManager? = nil,
        actionRouter: BereanPulseActionRouter? = nil
    ) {
        self.service = service ?? BereanPulseService()
        self.permissionManager = permissionManager ?? BereanPulsePermissionManager()
        self.actionRouter = actionRouter ?? BereanPulseActionRouter()
    }

    deinit {
        observationTask?.cancel()
    }

    var filteredCards: [BereanPulseCard] {
        rankedCards.filter { selectedMode == .all || $0.mode == selectedMode || $0.secondaryModes.contains(selectedMode) }
    }

    private var rankedCards: [BereanPulseCard] {
        cards
            .filter { !$0.isHidden }
            .sorted { lhs, rhs in
                score(lhs) > score(rhs)
            }
    }

    func load() async {
        observationTask?.cancel()
        feedState = .loading
        permissionManager.refreshStatuses()

        do {
            let snapshot = try await service.loadToday()
            currentSnapshotSource = snapshot.source
            cards = mergePermissionAvailability(into: snapshot.cards)
            signals = snapshot.signals
            preferences = snapshot.preferences
            feedState = cards.isEmpty ? .empty : currentLoadedState()
            observeRealtime()
            // On-demand generation: trigger callable when no cards exist for today.
            // The real-time observer will pick up cards as they are written.
            if cards.isEmpty {
                Task { try? await service.triggerOnDemandRefresh() }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                self.lastErrorMessage = nil
            }
            feedState = .error(error.localizedDescription)
        }
    }

    func refresh() async {
        feedState = .refreshing
        await load()
    }

    func toggleExpanded(_ cardId: String) {
        if expandedCardIds.contains(cardId) {
            expandedCardIds.remove(cardId)
        } else {
            expandedCardIds.insert(cardId)
            Task { await track(cardId: cardId, modeForCard(cardId), .expanded) }
        }
    }

    func isExpanded(_ cardId: String) -> Bool {
        expandedCardIds.contains(cardId)
    }

    func openCurate() {
        showCurateSheet = true
        Task { await track(cardId: "feed", .all, .curateOpened) }
    }

    func updatePreferences(_ updated: BereanPulsePreference) async {
        preferences = updated
        cards = mergePermissionAvailability(into: cards)
        do {
            try await service.updatePreferences(updated)
        } catch {
            lastErrorMessage = error.localizedDescription
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                self.lastErrorMessage = nil
            }
        }
    }

    func sendFeedback(_ feedback: BereanPulseFeedbackState, for card: BereanPulseCard) {
        updateCard(card.id) {
            $0.feedbackState = feedback
        }
        let event: BereanPulseEventType = feedback == .liked ? .liked : .disliked
        Task { await track(cardId: card.id, card.mode, event) }
    }

    func toggleSaved(_ card: BereanPulseCard) {
        let newValue = !card.isSaved
        updateCard(card.id) {
            $0.isSaved = newValue
        }
        Task {
            do {
                if newValue {
                    if let updated = cards.first(where: { $0.id == card.id }) {
                        try await service.save(card: updated)
                    }
                    await track(cardId: card.id, card.mode, .saved)
                } else {
                    try await service.unsave(cardId: card.id)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    self.lastErrorMessage = nil
                }
            }
        }
    }

    func hide(_ card: BereanPulseCard) {
        updateCard(card.id) {
            $0.isHidden = true
        }
        feedState = cards.allSatisfy(\.isHidden) ? .cardHidden : currentLoadedState()
        Task {
            do {
                try await service.hide(cardId: card.id)
                await track(cardId: card.id, card.mode, .hidden)
            } catch {
                lastErrorMessage = error.localizedDescription
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    self.lastErrorMessage = nil
                }
            }
        }
    }

    func handlePrimaryAction(for card: BereanPulseCard) async {
        guard card.primaryActionIsAvailable else {
            actionUnavailableMessage = card.unavailableActionExplanation
            return
        }
        await perform(card.primaryAction, for: card)
    }

    func perform(_ action: BereanPulseAction, for card: BereanPulseCard) async {
        if let permission = action.permissionType, action.requiresPermission, permissionManager.status(for: permission) != .granted {
            permissionPromptContext = BereanPulsePermissionPromptContext(
                source: permission,
                title: action.title,
                explanation: permissionManager.limitedExplanation(for: permission)
            )
            feedState = permissionManager.status(for: permission) == .denied ? .permissionDenied(permission) : .permissionRequired(permission)
            await track(cardId: card.id, card.mode, .permissionRequested)
            return
        }

        actionRouter.route(action: action, card: card)
        await track(cardId: card.id, card.mode, .actionTapped)
    }

    func requestPermissionFromPrompt() async {
        guard let prompt = permissionPromptContext else { return }
        let status = await permissionManager.requestPermission(for: prompt.source)
        permissionPromptContext = nil
        switch status {
        case .granted:
            feedState = currentLoadedState()
            await track(cardId: "permission", .all, .permissionGranted)
        case .denied, .limited, .unavailable:
            feedState = .permissionDenied(prompt.source)
            await track(cardId: "permission", .all, .permissionDenied)
        case .notRequested:
            feedState = .permissionRequired(prompt.source)
        }
        cards = mergePermissionAvailability(into: cards)
    }

    func dismissPermissionPrompt() {
        permissionPromptContext = nil
        feedState = currentLoadedState()
    }

    func clearDestination() {
        actionRouter.destination = nil
    }

    func clearShareText() {
        actionRouter.shareText = nil
    }

    func clearUnsupportedMessage() {
        actionRouter.unsupportedMessage = nil
    }

    func clearActionUnavailableMessage() {
        actionUnavailableMessage = nil
    }

    private func observeRealtime() {
        observationTask = Task {
            do {
                let stream = try await service.observeToday()
                for await updatedCards in stream {
                    guard !Task.isCancelled else { return }
                    self.currentSnapshotSource = .live
                    self.cards = self.mergePermissionAvailability(into: updatedCards)
                    self.feedState = self.cards.isEmpty ? .empty : self.currentLoadedState()
                }
            } catch {
                self.lastErrorMessage = error.localizedDescription
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    self.lastErrorMessage = nil
                }
                self.feedState = .error(error.localizedDescription)
            }
        }
    }

    private func mergePermissionAvailability(into cards: [BereanPulseCard]) -> [BereanPulseCard] {
        cards.map { card in
            var mutable = card
            if card.permissionRequirements.contains(where: { permissionManager.status(for: $0) == .denied }) {
                mutable.feedbackState = card.feedbackState
            }
            return mutable
        }
    }

    private func score(_ card: BereanPulseCard) -> Double {
        let freshness = max(0.1, 1.0 - Date().timeIntervalSince(card.updatedAt) / 86_400)
        let permissionPenalty = card.permissionRequirements.contains(where: { permissionManager.status(for: $0) == .denied }) ? 0.15 : 0
        let unavailablePenalty = card.primaryActionIsAvailable ? 0 : 0.3
        let preferenceBoost = preferences.preferredModes.contains(card.mode) || preferences.preferredModes.contains(.all) ? 0.08 : 0
        let suppressedPenalty = preferences.suppressedModes.contains(card.mode) ? 0.3 : 0
        let savedBoost = card.isSaved ? 0.1 : 0
        let openLoopBoost = card.mode == .openLoops ? 0.08 : 0
        return (card.matchScore * 0.36)
            + (card.urgencyScore * 0.18)
            + (card.relevanceScore * 0.18)
            + (freshness * 0.10)
            + preferenceBoost
            + savedBoost
            + openLoopBoost
            - permissionPenalty
            - unavailablePenalty
            - suppressedPenalty
    }

    private func currentLoadedState() -> BereanPulseFeedState {
        if cards.isEmpty { return .empty }
        if cards.contains(where: { !$0.permissionRequirements.isEmpty && $0.permissionRequirements.contains(where: { permissionManager.status(for: $0) != .granted }) }) {
            return .limitedPermissions
        }
        if currentSnapshotSource == .cache {
            return .offlineCached
        }
        return .loaded
    }

    private func modeForCard(_ cardId: String) -> BereanPulseMode {
        cards.first(where: { $0.id == cardId })?.mode ?? .all
    }

    private func updateCard(_ id: String, mutate: (inout BereanPulseCard) -> Void) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        var card = cards[index]
        mutate(&card)
        cards[index] = card
    }

    private func track(cardId: String, _ mode: BereanPulseMode, _ type: BereanPulseEventType) async {
        let topicKey = cards.first(where: { $0.id == cardId }).map { "\($0.primaryIntent):\($0.sourceSignalIds.joined(separator: "|"))" } ?? ""
        let event = BereanPulseEvent(
            id: UUID().uuidString,
            cardId: cardId,
            eventType: type,
            mode: mode,
            timestamp: Date(),
            metadata: [
                "selectedMode": selectedMode.rawValue,
                "topicKey": topicKey,
                "mode": mode.rawValue
            ]
        )
        await service.track(event)
    }
}
