// BereanScriptureReaderView.swift
// AMEN — Berean Reading Surface: Scripture Reader (W0 shell → W5 implementation)
//
// Flag: bereanReaderActions (default false)
// W0: Shell with correct public signature. Body is a placeholder.
// W5: Implement:
//     - White reading surface, serif body text
//     - ScriptureActionRow (Save · Share · Pray · Explain · More):
//         scroll-aware collapse on scroll down, restore on stop
//         blurs passage text behind it
//     - Verse-selection menu: Highlight · Note · Cross-Ref · Original Language · Ask Berean
//         Explain → Ask; Cross-Ref / Original Language → Discern
//     - Share: confirmation sheet + Guard routing before share sheet
//     - Full state matrix: loading / empty / error / offline

import SwiftUI

struct BereanScriptureReaderView: View {

    // W5: Replace with @State or injected ObservableObject conforming to
    //     BereanScriptureReaderViewModelProtocol.

    @State private var isActionRowCollapsed = false

    var body: some View {
        // W5: Replace with full implementation.
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("John 1:1")
                        .font(BereanType.sectionHeader)
                        .foregroundStyle(Color.bereanInk)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    Text("In the beginning was the Word, and the Word was with God, and the Word was God.")
                        .font(BereanType.bodyReading)
                        .foregroundStyle(Color.bereanInk)
                        .padding(.horizontal, 24)
                        .lineSpacing(8)

                    Spacer(minLength: 80)
                }
            }
            .background(Color.bereanWhite)

            ScriptureActionRow(
                passageTitle: "John 1:1",
                isCollapsed: isActionRowCollapsed,
                onSave: {},
                onShare: {},
                onPray: {},
                onExplain: {},
                onMore: {}
            )
            .background(Color.bereanIvory.opacity(0.95))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bereanWhite.ignoresSafeArea())
    }
}

#Preview {
    BereanScriptureReaderView()
}
