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
            // MEDIUM FIX: Guard against overwriting active states.
            // Previously, any focus event while .voiceReady or .streaming was active
            // would overwrite the state — e.g. tapping the text field during voice
            // recording would cancel .voiceReady and switch to .focused, silently
            // dropping the voice session. Only transition to .focused from truly idle
            // states (.idle, .scrollingCompact, .expandedActions).
            let isOverridable = composerVM.state == .idle
                || composerVM.state == .scrollingCompact
                || composerVM.state == .expandedActions
            if focused && isOverridable {
                composerVM.setState(.focused)
            } else if !focused && composerVM.state == .focused {
                composerVM.setState(.idle)
            }
        }
    }
    
    // MARK: - Main Composer

    /// Lerp helper: a + (b - a) * t
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * min(max(t, 0), 1)
    }

    private var mainComposer: some View {
        let p = composerVM.collapseProgress

        // Multi-breakpoint interpolated values
        let verticalPad  = lerp(12, 10, p)
        let cornerRadius = lerp(28, 24, p)
        let scaleValue   = lerp(1.0, 0.96, p)
        let opacityValue = lerp(1.0, 0.90, p)
        // glass opacity blends between idle and compact opacity targets
        let glassOpacity = lerp(
            CGFloat(composerVM.state.composerOpacity),
            CGFloat(BereanComposerState.scrollingCompact.composerOpacity),
            p
        )
        let shadowOpacity = lerp(
            CGFloat(composerVM.state.shadowOpacity),
            CGFloat(BereanComposerState.scrollingCompact.shadowOpacity),
            p
        )

        return HStack(spacing: 0) {
            // Plus button — shrinks slightly under collapse
            plusButton
                .padding(.trailing, 10)
                .scaleEffect(lerp(1.0, 0.88, p), anchor: .center)

            // Input field — placeholder crossfades to short form during collapse
            inputField

            // Right controls
            rightControls
                .padding(.leading, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, verticalPad)
        .liquidGlass(
            opacity: Double(glassOpacity),
            shadowOpacity: Double(shadowOpacity),
            cornerRadius: cornerRadius
        )
        .scaleEffect(scaleValue)
        .opacity(Double(opacityValue))
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
                // Dynamic offset: keep the cloud visible on small screens (SE: 667pt)
                // with the keyboard raised. We need to fit within the space above
                // the composer, which shrinks as keyboardHeight grows.
                // actionCloudHeight ≈ 6 actions × 52pt + 24pt padding ≈ 336pt
                // On SE with keyboard (291pt): available ≈ 667 - 291 - composerHeight - safeAreas
                // We cap at -240 for very small phones and use -300 on large ones.
                GeometryReader { geo in
                    Color.clear
                        .onAppear {}
                        .overlay(alignment: .top) {
                            let windowHeight = UIScreen.main.bounds.height
                            let composerBottom = windowHeight - keyboardHeight
                            // Available space above the composer (rough, without safe insets)
                            let availableAbove = composerBottom - geo.frame(in: .global).maxY
                            // Clamp the cloud upward: never more than availableAbove - 16pt margin
                            let maxOffset = -(max(min(availableAbove - 16, 300), 180))
                            actionCloud
                                .offset(y: maxOffset)
                                .transition(.scale.combined(with: .opacity))
                        }
                }
                .frame(width: 0, height: 0) // GeometryReader doesn't affect layout
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
        // HIGH FIX: textHeight was @State private var textHeight: CGFloat = 40 with
        // no update path — the TextEditor was always capped at exactly 40pt regardless
        // of content. Fix: overlay a hidden Text mirror behind the TextEditor and use
        // a GeometryReader background to measure its natural height, then write that
        // back to textHeight via preference. This is a pure-SwiftUI approach that
        // doesn't require UIKit introspection.
        let maxHeight: CGFloat = UIScreen.main.bounds.height < 700 ? 80 : 120

        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if messageText.isEmpty {
                    Text(placeholderText)
                        .font(AMENFont.regular(16))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 10)
                }

                // Hidden text mirror — same font, same horizontal padding — used only
                // to measure the natural height of the content. The "+ 20" accounts
                // for the vertical padding (10pt top + 10pt bottom) that TextEditor
                // adds around its content by default.
                Text(messageText.isEmpty ? " " : messageText)
                    .font(AMENFont.regular(16))
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: TextHeightPreferenceKey.self,
                                    value: geo.size.height + 20
                                )
                        }
                    )

                TextEditor(text: $messageText)
                    .font(AMENFont.regular(16))
                    .foregroundStyle(.primary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    // Cap adapts to screen: SE (667pt) → 80pt, larger → 120pt.
                    // Prevents the composer from consuming the entire visible area
                    // when the keyboard is raised on small devices.
                    .frame(height: min(max(40, textHeight), maxHeight))
                    .focused($isFocused)
            }
        }
        .onPreferenceChange(TextHeightPreferenceKey.self) { measuredHeight in
            let clamped = min(max(40, measuredHeight), maxHeight)
            if abs(clamped - textHeight) > 1 {
                withAnimation(.easeOut(duration: 0.15)) {
                    textHeight = clamped
                }
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
        // CRITICAL FIX: VoiceOver was announcing "Image, button" with no context.
        .accessibilityLabel("Send message")
        .accessibilityHint("Sends your message to Berean")
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
        // CRITICAL FIX: VoiceOver was announcing "Image, button" with no context.
        .accessibilityLabel("Stop generation")
        .accessibilityHint("Stops Berean's current response")
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

// MARK: - Text Height Preference Key

/// Propagates the measured height of the hidden Text mirror upward to the
/// inputField view so that textHeight can track content size in real time.
private struct TextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 40
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
