// BereanPrayerSurfaceView.swift
// AMEN — Berean Reading Surface: Prayer Journal (W0 shell → W6 implementation)
//
// Flag: bereanPrayerJournal (default false)
// W0: Shell with correct public signature. Body is a placeholder.
// W6: Implement:
//     - Four glass card sections: Today's Prayer / Answered / People I'm Praying For / Scripture to Pray
//     - Guided prayer + scripture-to-prayer generator (Build / Reflect modes)
//     - Answered-prayer tagging
//     - FloatingPrimaryCTA: Start Prayer / Continue / Next Reflection
//     - Full state matrix: empty / loading / error / offline
//
// SAFETY: journals are private by default (isPrivate = true).
//         Any move from private → shared requires:
//           1. Explicit confirmation sheet presented to user
//           2. Guard routing before any content leaves device
//         Do NOT expose a share path that bypasses both gates.
//         Child-safety / COPPA posture inherited from GUARDIAN/Aegis.

import SwiftUI

struct BereanPrayerSurfaceView: View {

    // W6: Replace with @State or injected ObservableObject conforming to
    //     BereanPrayerSurfaceViewModelProtocol.

    @State private var todayEntry = ""

    var body: some View {
        // W6: Replace with full implementation.
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Prayer Journal")
                        .font(BereanReaderType.displayTitle)
                        .foregroundStyle(Color.bereanInk)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    BereanReaderCard(header: "Today's Prayer") {
                        TextEditor(text: $todayEntry)
                            .font(BereanReaderType.body)
                            .foregroundStyle(Color.bereanInk)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .padding()
                    }
                    .padding(.horizontal, 16)

                    // W6: Answered / People / Scripture cards here.

                    Spacer(minLength: 100)
                }
            }
            .background(Color.bereanIvory)

            FloatingPrimaryCTA(label: .startPrayer, action: {})
                .padding(.trailing, 24)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bereanIvory.ignoresSafeArea())
    }
}

#Preview {
    BereanPrayerSurfaceView()
}
