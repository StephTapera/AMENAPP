// BereanListeningView.swift
// AMEN — Berean Reading Surface: Listening / Voice Mode (W0 shell → W3 implementation)
//
// Flag: bereanListening (default false)
// W0: Shell with correct public signature. Body is a placeholder.
// W3: Implement:
//     - Mic consent gate (mandatory, no capture without explicit grant)
//     - Center VoiceOrb (maps to listening → summarizing per active mode)
//     - Live transcript (You / Berean turns, scripture references cited)
//     - Actions: Pause / Save to Notes / Add Scripture / End Session
//     - Convert transcript: prayer / study plan / summary via Build mode
//     - Full state matrix: no-consent / recording / paused / loading / error / offline
//
// SAFETY: transcript is UGC — routes through Guard before any save or share.
// COPPA: inherits existing age-gate posture from GUARDIAN/Aegis.

import SwiftUI

struct BereanListeningView: View {

    // W3: Replace with @State or injected ObservableObject conforming to
    //     BereanListeningViewModelProtocol.

    var body: some View {
        // W3: Replace with full implementation.
        VStack(spacing: 24) {
            Spacer()

            VoiceOrb(state: .idle)

            Text("Listening Mode")
                .font(BereanType.sectionHeader)
                .foregroundStyle(Color.bereanInk)

            Text("Mic consent gate + voice session — coming in W3")
                .font(BereanType.caption)
                .foregroundStyle(Color.bereanInk.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bereanIvory.ignoresSafeArea())
    }
}

#Preview {
    BereanListeningView()
}
