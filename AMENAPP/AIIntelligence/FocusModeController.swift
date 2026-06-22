// FocusModeController.swift
// AMENAPP
//
// Wave 5 — Focus / Reflection / Sabbath / Digital-Fast modes.
//
// Real, persisted mode state. Surfaces consult this to GENUINELY hide likes,
// notifications, and the feed (via the .hiddenInFocus modifier) and to swap in
// scripture + journal prompts. Anti-engagement, consistent with CalmCap.
//
// Gated by AMENFeatureFlags.shared.focusModesEnabled (default OFF).

import SwiftUI

enum FocusMode: String, CaseIterable, Identifiable {
    case off
    case focus        // hides likes + notifications; feed stays
    case reflection   // hides like counts + notifications; calmer feed
    case sabbath      // hides feed + likes + notifications; scripture forward
    case digitalFast  // hides all social surfaces

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:          return "Off"
        case .focus:        return "Focus"
        case .reflection:   return "Reflection"
        case .sabbath:      return "Sabbath"
        case .digitalFast:  return "Digital Fast"
        }
    }

    var blurb: String {
        switch self {
        case .off:          return "Everything as normal."
        case .focus:        return "Hide likes and notifications. Keep what you came for."
        case .reflection:   return "Quiet the counts. Read slower."
        case .sabbath:      return "Set the feed down. Scripture and prayer forward."
        case .digitalFast:  return "Step away from the social surfaces entirely."
        }
    }

    var hidesLikes: Bool { self != .off }
    var hidesNotifications: Bool { self == .focus || self == .reflection || self == .sabbath || self == .digitalFast }
    var hidesFeed: Bool { self == .sabbath || self == .digitalFast }
    var surfacesScripture: Bool { self == .sabbath || self == .digitalFast }
}

@MainActor
final class FocusModeController: ObservableObject {
    static let shared = FocusModeController()

    @AppStorage("trust.focusMode") private var storedMode: String = FocusMode.off.rawValue

    @Published var mode: FocusMode = .off {
        didSet { storedMode = mode.rawValue }
    }

    private init() {
        mode = FocusMode(rawValue: storedMode) ?? .off
    }

    var isActive: Bool { mode != .off }
}

// MARK: - Hide modifier (consulted at the real hide sites)

enum FocusAspect {
    case likes
    case notifications
    case feed
}

extension View {
    /// Hides this content when the active focus mode hides the given aspect.
    /// Fail-open: when the flag is off, content always shows.
    @MainActor @ViewBuilder
    func hiddenInFocus(_ aspect: FocusAspect) -> some View {
        if AMENFeatureFlags.shared.focusModesEnabled && shouldHide(aspect, mode: FocusModeController.shared.mode) {
            EmptyView()
        } else {
            self
        }
    }
}

private func shouldHide(_ aspect: FocusAspect, mode: FocusMode) -> Bool {
    switch aspect {
    case .likes:         return mode.hidesLikes
    case .notifications: return mode.hidesNotifications
    case .feed:          return mode.hidesFeed
    }
}
