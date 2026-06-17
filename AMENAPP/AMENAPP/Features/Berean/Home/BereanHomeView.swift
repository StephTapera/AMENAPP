// BereanHomeView.swift
// AMEN — Berean Reading Surface: Home / Study Hub (W0 shell → W2 implementation)
//
// Flag: bereanHomeV2 (default false)
// W0: Shell with correct public signature. Body is a placeholder.
// W2: Implement:
//     - Greeting + adaptive context line (driven by real study history)
//     - BereanHomeChip quick-action grid
//     - "Continue [last study]" LiquidGlassCard (hidden if no history)
//     - LiquidGlassInputBar at bottom → routes to Ask mode
//     - Full state matrix: empty / loading / error / offline
//     All UGC (input text) routes through Guard before submission.

import SwiftUI

struct BereanHomeView: View {

    // W2: Replace with @State or injected ObservableObject conforming to
    //     BereanHomeViewModelProtocol.

    var body: some View {
        // W2: Replace with full implementation.
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Berean")
                    .font(BereanType.displayTitle)
                    .foregroundStyle(Color.bereanInk)
                Text("Your study surface — coming in W2")
                    .font(BereanType.caption)
                    .foregroundStyle(Color.bereanInk.opacity(0.5))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bereanIvory.ignoresSafeArea())
    }
}

#Preview {
    BereanHomeView()
}
