// DEFERRED-FEATURE: BereanPerspectiveView mainContent is a static placeholder.
// Multi-perspective analysis feature not yet implemented. (GAP A1-P1)
// BereanPerspectiveView.swift
// AMENAPP — Berean OS

import SwiftUI

struct BereanPerspectiveView: View {
    let projectId: String?

    var body: some View {
        Group {
            if AMENFeatureFlags.shared.bereanOSMultiPerspectiveEnabled {
                mainContent
            } else {
                ContentUnavailableView(
                    "Perspectives",
                    systemImage: "person.3.fill",
                    description: Text("Coming soon")
                )
            }
        }
        .navigationTitle("Perspectives")
        .navigationBarTitleDisplayMode(.large)
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Multi-Perspective Analysis")
                    .font(.largeTitle.bold())
                Text("Explore a topic through multiple theological and scholarly perspectives.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
