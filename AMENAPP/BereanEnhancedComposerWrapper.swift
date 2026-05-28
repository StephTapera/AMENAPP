//
//  BereanEnhancedComposerWrapper.swift
//  AMENAPP
//
//  Wrapper to integrate Liquid Glass composer with existing Berean functionality
//

import SwiftUI

struct BereanEnhancedComposerWrapper: View {
    // Existing Berean bindings
    @Binding var messageText: String
    @FocusState.Binding var isInputFocused: Bool
    @Binding var isGenerating: Bool
    @Binding var responseMode: BereanResponseMode
    @Binding var followUpSuggestions: [BereanFollowUp]
    @Binding var showFollowUps: Bool
    
    // Callbacks
    let onSend: () -> Void
    let onPlusButtonTap: () -> Void
    let onVoice: () -> Void
    var onStop: (() -> Void)? = nil
    
    // Liquid Glass composer state (shared with parent for scroll updates)
    @ObservedObject var composerVM: BereanComposerViewModel = BereanComposerViewModel()
    
    // Local state
    @State private var suggestions: [BereanLiquidSuggestionChip] = BereanLiquidSuggestionChip.defaultSuggestions
    
    var body: some View {
        VStack(spacing: 0) {
            // Mode selector (only when idle)
            if messageText.isEmpty && composerVM.state != .scrollingCompact {
                responseModePickerView
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Follow-up chips (existing functionality)
            if showFollowUps && !followUpSuggestions.isEmpty && messageText.isEmpty {
                followUpChipsView
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Suggestion chips (new - shown when idle)
            if composerVM.state.showSuggestions && messageText.isEmpty {
                BereanSuggestionChipsView(
                    chips: suggestions,
                    onTap: { chip in
                        messageText = chip.text
                        isInputFocused = true
                    },
                    isVisible: true
                )
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Main Liquid Glass composer
            BereanLiquidComposerView(
                composerVM: composerVM,
                messageText: $messageText,
                isFocused: $isInputFocused,
                onSend: onSend,
                onVoice: handleVoiceAction,
                onAction: handleQuickAction,
                onStop: onStop
            )
        }
        .onChange(of: isGenerating) { _, generating in
            if generating {
                composerVM.setState(.streaming)
                composerVM.showStatus(.streaming, duration: 0)
            } else {
                composerVM.setState(.idle)
                composerVM.statusPill = nil
            }
        }
    }
    
    // MARK: - Mode Picker
    
    private var responseModePickerView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BereanResponseMode.allCases, id: \.self) { mode in
                    modeButton(mode)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func modeButton(_ mode: BereanResponseMode) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                responseMode = mode
            }
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .medium))
                
                Text(mode.rawValue)
                    .font(AMENFont.medium(12))
            }
            .foregroundStyle(responseMode == mode ? .white : .primary.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Group {
                    if responseMode == mode {
                        Capsule()
                            .fill(Color.black.opacity(0.85))
                            .shadow(color: Color.black.opacity(0.15), radius: 6, y: 2)
                    } else {
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                            .background(
                                .ultraThinMaterial,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.gray.opacity(0.15), lineWidth: 0.5)
                            )
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Follow-up Chips
    
    private var followUpChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(followUpSuggestions.prefix(3)), id: \.id) { item in
                    followUpChipButton(item)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func followUpChipButton(_ item: BereanFollowUp) -> some View {
        Button {
            messageText = item.prompt
            isInputFocused = true
            withAnimation(.easeOut(duration: 0.2)) {
                showFollowUps = false
            }
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.6))
                
                Text(item.text)
                    .font(AMENFont.medium(13))
                    .foregroundStyle(.primary)
            }
            .suggestionChip()
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Action Handlers
    
    private func handleQuickAction(_ action: BereanLiquidAction.ActionType) {
        switch action {
        case .attachFile, .camera:
            onPlusButtonTap()
        case .voiceNote:
            handleVoiceAction()
        case .verseLookup:
            composerVM.setState(.scriptureMode)
            composerVM.showStatus(.verseLookup)
            messageText = ""
            isInputFocused = true
        case .summarize:
            messageText = "Summarize this: "
            isInputFocused = true
        case .searchScripture:
            composerVM.setState(.searchMode)
            composerVM.showStatus(.searchMode)
            messageText = ""
            isInputFocused = true
        case .explainSimply:
            messageText = "Explain simply: "
            isInputFocused = true
        case .exploreContext:
            messageText = "Give me more context on: "
            isInputFocused = true
        case .crossReference:
            messageText = "Show me cross-references for: "
            isInputFocused = true
        case .prayer:
            messageText = "Pray with me: "
            isInputFocused = true
        case .deepStudy:
            composerVM.setState(.scriptureMode)
            messageText = ""
            isInputFocused = true
        case .addPhoto, .addFile:
            onPlusButtonTap()
        case .createNote, .saveToChurchNotes:
            break
        }
    }
    
    private func handleVoiceAction() {
        onVoice()
        composerVM.setState(.voiceReady)
        composerVM.showStatus(.voiceReady, duration: 0)
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @FocusState var focused: Bool
    @Previewable @State var generating = false
    @Previewable @State var mode: BereanResponseMode = .quick
    @Previewable @State var followUps: [BereanFollowUp] = []
    @Previewable @State var showFollow = false
    @Previewable @StateObject var composerVM = BereanComposerViewModel()
    
    VStack {
        Spacer()
        
        BereanEnhancedComposerWrapper(
            messageText: $text,
            isInputFocused: $focused,
            isGenerating: $generating,
            responseMode: $mode,
            followUpSuggestions: $followUps,
            showFollowUps: $showFollow,
            onSend: { print("Send") },
            onPlusButtonTap: { print("Plus") },
            onVoice: { print("Voice") },
            composerVM: composerVM
        )
    }
    .background(Color.white)
}
