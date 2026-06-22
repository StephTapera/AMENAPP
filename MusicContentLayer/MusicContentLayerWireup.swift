// MusicContentLayerWireup.swift
// AMENAPP — MusicContentLayer
//
// Lightweight wiring: environment injection modifier + shared layer environment.

import SwiftUI

// MARK: - Feature Flag

enum MusicContentLayerFeatureFlag {
    static let isEnabled: Bool = true
}

// MARK: - MusicContentLayerEnvironment

@MainActor
final class MusicContentLayerEnvironment: ObservableObject {
    let graphService = FaithMusicGraphService()
    let rightsService = RightsMonetizationService()
    let intentService = SmartComposerIntentService()
}

// MARK: - View Modifier

private struct MusicContentLayerModifier: ViewModifier {
    @StateObject private var environment = MusicContentLayerEnvironment()

    func body(content: Content) -> some View {
        content
            .environmentObject(environment)
    }
}

// MARK: - View Extension

extension View {
    /// Injects the MusicContentLayer environment objects into the view hierarchy.
    /// Apply once near the root of a screen that uses MusicContentLayer surfaces.
    func amenMusicContentLayer() -> some View {
        modifier(MusicContentLayerModifier())
    }
}
