//
//  MutualContextViewModel.swift
//  AMENAPP
//
//  @MainActor ObservableObject that loads context signals for a given userId
//  via MutualContextService. Exposes sorted signals and loading state.
//

import Foundation

@MainActor
final class MutualContextViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded([MutualContextSignal])
    }

    @Published private(set) var state: State = .idle

    var signals: [MutualContextSignal] {
        if case .loaded(let s) = state { return s }
        return []
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var isEmpty: Bool {
        if case .loaded(let s) = state { return s.isEmpty }
        return false
    }

    /// The primary (highest relevance) signal, if any.
    var primarySignal: MutualContextSignal? {
        signals.first
    }

    // MARK: - Load

    func load(profileUID: String) async {
        state = .loading
        let result = await MutualContextService.shared.fetchContextSignals(profileUID: profileUID)
        state = .loaded(result)
        dlog("MutualContextViewModel: loaded \(result.count) signal(s) for \(profileUID)")
    }

    func reset() {
        state = .idle
    }
}
