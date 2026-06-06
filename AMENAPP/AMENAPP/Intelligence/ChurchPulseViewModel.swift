// ChurchPulseViewModel.swift
// AMENAPP — Church Pulse ViewModel
//
// Drives ChurchPulseView through the four possible states:
//   .loading   — initial fetch in progress
//   .loaded    — a valid ChurchPulse is available
//   .empty     — church has no meaningful pulse data (score == 0, UNKNOWN engagement)
//   .error     — network/auth/membership failure

import Foundation

// MARK: - ChurchPulseViewModel

@MainActor
final class ChurchPulseViewModel: ObservableObject {

    // MARK: - ViewState

    enum ViewState: Equatable {
        case loading
        case loaded(ChurchPulse)
        case empty
        case error(String)

        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading):   return true
            case (.empty, .empty):       return true
            case (.loaded(let a), .loaded(let b)): return a.churchId == b.churchId
            case (.error(let a), .error(let b)):   return a == b
            default: return false
            }
        }
    }

    // MARK: - Published state

    @Published var state: ViewState = .loading

    // MARK: - Properties

    let churchId: String

    private let service: ChurchPulseService

    // MARK: - Init

    init(churchId: String, service: ChurchPulseService = .shared) {
        self.churchId = churchId
        self.service = service
    }

    // MARK: - Load

    /// Triggers a pulse fetch and transitions `state` accordingly.
    func load() async {
        state = .loading

        do {
            let pulse = try await service.fetchPulse(for: churchId)

            // Treat a zero-score UNKNOWN-engagement pulse as effectively empty
            // so the view can render a gentle "no data yet" state.
            if pulse.pulseScore == 0 && pulse.memberEngagement == .unknown {
                state = .empty
            } else {
                state = .loaded(pulse)
            }
        } catch let error as ChurchPulseServiceError {
            state = .error(error.localizedDescription)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Refresh

    /// Re-fetches the pulse. The server applies a 6-hour cache TTL, so rapid
    /// refreshes return the cached value without additional computation cost.
    func refresh() async {
        await load()
    }
}
