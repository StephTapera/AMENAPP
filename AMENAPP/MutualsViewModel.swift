//
//  MutualsViewModel.swift
//  AMENAPP
//
//  @MainActor ObservableObject for the MutualsAvatarStrip.
//  Scoped to UserProfileView — re-fetches whenever profileUID changes.
//

import Foundation
import Combine
import FirebaseAuth

@MainActor
final class MutualsViewModel: ObservableObject {

    enum State {
        case idle
        case loading
        case loaded([MutualConnection])
    }

    @Published private(set) var state: State = .idle

    var mutuals: [MutualConnection] {
        if case .loaded(let m) = state { return m }
        return []
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var isEmpty: Bool {
        if case .loaded(let m) = state { return m.isEmpty }
        return false
    }

    // MARK: - Load

    func load(profileUID: String) async {
        // Privacy: viewer must be logged in, and not viewing their own profile
        guard let viewerUID = Auth.auth().currentUser?.uid,
              viewerUID != profileUID else {
            state = .loaded([])
            return
        }

        state = .loading

        let result = await MutualsService.shared.fetchMutuals(profileUID: profileUID)
        state = .loaded(result)

        dlog("🤝 Mutuals loaded: \(result.count) for profile \(profileUID)")
    }

    func reset() {
        state = .idle
    }
}
