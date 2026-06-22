//
//  VoiceWisdomView.swift
//  AMENAPP
//
//  Feature 7 — Voice Wisdom inline panel.
//  Collapsible mic pill → waveform recording card → processing shimmer
//  → transcription card with "Insert into Notes".
//
//  Implementation lives in VoiceToWisdomView.swift.
//  This file provides the canonical Feature 7 type name used in the integration guide.
//

import SwiftUI

// MARK: - VoiceWisdomView

/// Feature 7: inline collapsible voice capture + Berean AI enhancement.
/// Tap the green mic pill → recording expands → AI processes audio →
/// transcribed text is injected directly into the note body.
struct VoiceWisdomView: View {
    @StateObject var viewModel: VoiceToWisdomViewModel
    @Binding var noteBody: String

    var body: some View {
        VoiceToWisdomView(viewModel: viewModel, noteBody: $noteBody)
    }
}
