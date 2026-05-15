//
//  BereanIslandButton.swift
//  AMENAPP
//
//  Canonical reusable Berean Live Activity trigger for post surfaces.
//

import SwiftUI

struct BereanIslandButton: View {
    let post: Post
    @State private var isActivationInFlight = false

    var body: some View {
        AISparkleSearchButton {
            handleTap()
        }
        .frame(width: 20, height: 20)
    }

    @MainActor
    private func handleTap() {
        guard !isActivationInFlight else {
            dlog("⏭️ [BereanLiveActivity] BereanIslandButton ignored duplicate tap for post \(post.firestoreId)")
            return
        }

        isActivationInFlight = true
        HapticManager.impact(style: .light)
        BereanLiveActivityService.shared.startActivity(for: post)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            isActivationInFlight = false
        }
    }
}
