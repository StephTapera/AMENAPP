// BereanNotesEditorView.swift
// AMEN — Berean Reading Surface: Sermon & Study Notes Editor (W0 shell → W4 implementation)
//
// Flag: bereanNotesEditor (default false)
// W0: Shell with correct public signature. Body is a placeholder.
// W4: Implement:
//     - Clean writing surface (ivory background, serif body text)
//     - AIKeyboardToolbar anchored above keyboard
//     - Action → mode routing:
//         Summarize / Outline / Study Plan / Turn-into-Prayer / Devotional → Build
//         Cross-Ref / Context / Check Context → Discern
//         Clarify → Ask
//     - Local-first save + sync via existing notes path
//     - Offline: queue + visible "Will sync when online" indicator; never silent loss
//     - Full state matrix: empty / editing / syncing / error / offline

import SwiftUI

struct BereanNotesEditorView: View {

    // W4: Replace with @State or injected ObservableObject conforming to
    //     BereanNotesEditorViewModelProtocol.

    @State private var titleText = ""
    @State private var bodyText  = ""

    var body: some View {
        // W4: Replace with full implementation including AIKeyboardToolbar wiring.
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $titleText)
                .font(BereanType.sectionHeader)
                .foregroundStyle(Color.bereanInk)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Divider()
                .background(Color.bereanTan)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

            TextEditor(text: $bodyText)
                .font(BereanType.bodyReading)
                .foregroundStyle(Color.bereanInk)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bereanWhite.ignoresSafeArea())
    }
}

#Preview {
    BereanNotesEditorView()
}
