//
//  BereanLiquidComposerView.swift
//  AMENAPP
//
//  Production-quality Liquid Glass composer for Berean AI
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
    
    @State private var textHeight: CGFloat = 40
    @State private var showActions = false
    @State private var keyboardHeight: CGFloat = 0
    
    private let quickActions: [BereanLiquidAction] = [
        BereanLiquidAction(icon: "doc.fill", title: "Attach", color: .blue, action: .attachFile),
        BereanLiquidAction(icon: "camera.fill", title: "Camera", color: .purple, action: .camera),
        BereanLiquidAction(icon: "waveform", title: "Voice", color: .orange, action: .voiceNote),
        BereanLiquidAction(icon: "book.fill", title: "Verse", color: .green, action: .verseLookup),
        BereanLiquidAction(icon: "doc.text.magnifyingglass", title: "Summary", color: .indigo, action: .summarize),
        BereanLiquidAction(icon: "magnifyingglass", title: "Search", color: .cyan, action: .searchScripture)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Floating status pill (above composer)
            if let status = composerVM.statusPill {
                self.floatingStatusPill(status)
                    .padding(.bottom, 8)
                    .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Main composer container
            mainComposer
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = keyboardFrame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
        .onChange(of: messageText) { _, newValue in
            if !newValue.isEmpty && composerVM.state == .idle {
                composerVM.setState(.typing)
            } else if newValue.isEmpty && composerVM.state == .typing {
                composerVM.setState(.idle)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused && composerVM.state != .typing {
                composerVM.setState(.focused)
            } else if !focused && composerVM.state == .focused {
                composerVM.setState(.idle)
            }
        }
    }
    
    // MARK: - Main Composer
    
    private var mainComposer: some View {
        HStack(spacing: 0) {
            // Plus button
            plusButton
                .padding(.trailing, 10)
            
            // Input field
            inputField
            
            // Right controls
            rightControls
                .padding(.leading, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, composerVM.state.isCompact ? 10 : 12)
        .liquidGlass(
            opacity: composerVM.state.composerOpacity,
            shadowOpacity: composerVM.state.shadowOpacity,
            cornerRadius: composerVM.state.isCompact ? 24 : 28
        )
        .scaleEffect(composerVM.state.isCompact ? 0.96 : 1.0)
        .opacity(composerVM.state.isCompact ? 0.9 : 1.0)
        .composerCompression(composerVM.state == .typing || isFocused)
    }
    
    // MARK: - Plus Button
    
    private var plusButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                showActions.toggle()
                composerVM.setState(showActions ? .expandedActions : .idle)
            }
            HapticManager.impact(style: .light)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                )
                .rotationEffect(.degrees(showActions ? 45 : 0))
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(alignment: .top) {
            if showActions {
                actionCloud
                    .offset(y: -60)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Action Cloud
    
    private var actionCloud: some View {
        VStack(spacing: 8) {
            ForEach(Array(quickActions.enumerated()), id: \.element.id) { index, action in
                actionPillButton(action)
                    .transition(.scale.combined(with: .opacity))
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.7)
                            .delay(Double(index) * 0.05),
                        value: showActions
                    )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.10))
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 20)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
        )
    }
    
    private func actionPillButton(_ action: BereanLiquidAction) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showActions = false
                composerVM.setState(.idle)
            }
            onAction(action.action)
            HapticManager.impact(style: .medium)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(action.color)
                    .frame(width: 24)
                
                Text(action.title)
                    .font(AMENFont.medium(15))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .actionPill(color: action.color)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Input Field
    
    private var inputField: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Auto-growing text editor
            ZStack(alignment: .topLeading) {
                if messageText.isEmpty {
                    Text(placeholderText)
                        .font(AMENFont.regular(16))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 10)
                }
                
                TextEditor(text: $messageText)
                    .font(AMENFont.regular(16))
                    .foregroundStyle(.primary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(height: min(max(40, textHeight), 120))
                    .focused($isFocused)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .inputGlass(
            opacity: composerVM.state.inputOpacity,
            isFocused: isFocused
        )
    }
    
    private var placeholderText: String {
        switch composerVM.state {
        case .voiceReady: return "Listening..."
        case .scriptureMode: return "Enter verse reference..."
        case .searchMode: return "Search scripture..."
        case .streaming: return "Berean is thinking..."
        default: return "Ask Berean"
        }
    }
    
    // MARK: - Right Controls
    
    private var rightControls: some View {
        HStack(spacing: 8) {
            if composerVM.state == .streaming {
                stopButton
            } else if composerVM.state == .voiceReady {
                voiceWaveform
            } else if !messageText.isEmpty {
                sendButton
            } else {
                micButton
            }
        }
    }
    
    private var sendButton: some View {
        Button {
            onSend()
            HapticManager.impact(style: .medium)
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
        }
        .buttonStyle(PlainButtonStyle())
        .transition(.scale.combined(with: .opacity))
    }
    
    private var micButton: some View {
        Button {
            onVoice()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                composerVM.setState(.voiceReady)
            }
            HapticManager.impact(style: .light)
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.gray)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.10))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .transition(.scale.combined(with: .opacity))
    }
    
    private var stopButton: some View {
        Button {
            onStop?()
            HapticManager.impact(style: .medium)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .transition(.scale.combined(with: .opacity))
    }
    
    private var voiceWaveform: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                VoiceWaveformBar(index: index, isActive: composerVM.state == .voiceReady)
            }
        }
        .frame(width: 42, height: 36)
        .padding(.horizontal, 6)
    }
    
    // MARK: - Floating Status Pill
    
    private func floatingStatusPill(_ type: BereanStatusPillType) -> some View {
        HStack(spacing: 8) {
            Image(systemName: type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            
            Text(type.text)
                .font(AMENFont.medium(13))
                .foregroundStyle(.primary)
        }
        .floatingPill()
    }
}

// MARK: - Voice Waveform Bar

private struct VoiceWaveformBar: View {
    let index: Int
    let isActive: Bool
    
    @State private var height: CGFloat = 4
    
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 24
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.blue,
                        Color.blue.opacity(0.7)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 3, height: height)
            .onChange(of: isActive) { _, active in
                if active {
                    startAnimating()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        height = minHeight
                    }
                }
            }
            .onAppear {
                if isActive {
                    startAnimating()
                }
            }
    }
    
    private func startAnimating() {
        let delay = Double(index) * 0.15
        let duration = 0.4 + Double(index) * 0.1
        
        withAnimation(
            .easeInOut(duration: duration)
                .repeatForever(autoreverses: true)
                .delay(delay)
        ) {
            height = maxHeight - CGFloat(index) * 2
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @FocusState var focused: Bool
    @Previewable @StateObject var vm = BereanComposerViewModel()
    
    VStack {
        Spacer()
        
        BereanLiquidComposerView(
            composerVM: vm,
            messageText: $text,
            isFocused: $focused,
            onSend: { print("Send") },
            onVoice: { print("Voice") },
            onAction: { print("Action: \($0)") }
        )
    }
    .background(Color.white)
}
