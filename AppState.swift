//
//  AppState.swift
//  AMENAPP
//
//  App routing state — enum only. Routing logic lives in AuthenticationViewModel.
//

import Foundation

enum AppState: Equatable {
    case loading
    case unauthenticated
    case awaitingEmailVerification(userId: String, email: String)
    case awaitingOnboarding(userId: String)
    case authenticated(userId: String)

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }
}
// NOTE: AppStateManager was removed — it registered a redundant Firebase auth state
// listener that duplicated work already done by AuthenticationViewModel. All routing
// state is driven by AuthenticationViewModel.isAuthenticated and related @Published
// properties observed in ContentView.
