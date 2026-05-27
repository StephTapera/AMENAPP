//
//  BereanLiquidComposerView.swift
//  AMENAPP
//
//  Compatibility wrapper for the production Berean compact composer.
//

import SwiftUI

struct BereanLiquidComposerView: View {
    @ObservedObject var composerVM: BereanComposerViewModel
    @Binding var messageText: String
    @FocusState.Binding var isFocused: Bool

    let onSend: () -> Void
    let onVoice: () -> Void
    let onAction: (BereanLiquidAction.ActionType) -> Void
    var onStop: (() -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            VStack {
                Spacer(minLength: 0)
                BereanCompactComposerBar(
                    composerVM: composerVM,
                    messageText: $messageText,
                    isFocused: $isFocused,
                    availableWidth: max(proxy.size.width - 32, 304),
                    selectedMode: .askBerean,
                    onSend: onSend,
                    onVoice: onVoice,
                    onAction: onAction,
                    onTools: {},
                    onStop: onStop
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .frame(minHeight: 72, maxHeight: 180)
    }
}
