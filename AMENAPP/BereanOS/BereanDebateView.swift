// DEFERRED-FEATURE: BereanDebateView mainContent is a static placeholder.
// Debate engine AI feature not yet implemented. (GAP A1-P1)
// BereanDebateView.swift
// AMENAPP — Berean OS

import SwiftUI

struct BereanDebateView: View {
    let projectId: String?

    var body: some View {
        Group {
            if AMENFeatureFlags.shared.bereanOSDebateEngineEnabled {
                mainContent
            } else {
                ContentUnavailableView(
                    "Debate Engine",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    description: Text("Coming soon")
                )
            }
        }
        .navigationTitle("Debate")
        .navigationBarTitleDisplayMode(.large)
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Debate Engine")
                    .font(.largeTitle.bold())
                Text("Generate balanced pro and con arguments on any topic, grounded in scripture.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
