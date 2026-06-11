//
//  BereanComposerBar.swift
//  AMENAPP
//
//  Safari-inspired floating Berean composer with progressive scroll collapse.
//

import SwiftUI

struct BereanComposerBar: View {
    @ObservedObject var composerVM: BereanComposerViewModel
    @Binding var messageText: String
    @FocusState.Binding var isFocused: Bool

    let availableWidth: CGFloat
    let onSend: () -> Void
    let onVoice: () -> Void
    let onAction: (BereanLiquidAction.ActionType) -> Void
    let onTools: () -> Void
    var onStop: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showActions = false
    @State private var keyboardHeight: CGFloat = 0

    private let expandedPlaceholder = "Ask Berean"
    private let compactPlaceholder = "Ask Berean"

    private let quickActions: [BereanLiquidAction] = [
        BereanLiquidAction(icon: "book.closed", title: "Add Bible verse", color: Color.black.opacity(0.78), action: .bibleVerse),
        BereanLiquidAction(icon: "hands.sparkles", title: "Add prayer request", color: Color.black.opacity(0.74), action: .prayerRequest),
        BereanLiquidAction(icon: "note.text", title: "Add church notes", color: Color.black.opacity(0.74), action: .churchNotes),
        BereanLiquidAction(icon: "camera", title: "Add photo safely", color: Color.black.opacity(0.72), action: .safePhoto),
        BereanLiquidAction(icon: "waveform", title: "Add voice note", color: Color.black.opacity(0.72), action: .voiceNote),
        BereanLiquidAction(icon: "waveform.badge.magnifyingglass", title: "Add sermon clip", color: Color.black.opacity(0.72), action: .sermonClip),
        BereanLiquidAction(icon: "bell.badge", title: "Add reminder", color: Color.black.opacity(0.72), action: .reminder),
        BereanLiquidAction(icon: "person.2.badge.plus", title: "Share to Space", color: Color.black.opacity(0.76), action: .shareToSpace)
    ]

    var body: some View {
        let progress = effectiveCollapseProgress
        let shellWidth = interpolatedWidth(for: progress)
        let cornerRadius = interpolate(28, 22, progress)
        let verticalOffset = interpolate(0, 12, progress)
        let scale = interpolate(1.0, 0.97, progress)
        let shellPadding = interpolate(8, 6, progress)
        let innerSpacing = interpolate(8, 6, progress)
        let glassOpacity = interpolate(0.06, 0.04, progress)
        let shadowOpacity = interpolate(0.13, 0.09, progress)

        VStack(spacing: 0) {
            if let status = composerVM.statusPill {
                floatingStatusPill(status)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 0) {
                utilityButton(progress: progress)
                    .padding(.trailing, innerSpacing)

                ComposerTextField(
                    text: $messageText,
                    isFocused: $isFocused,
                    collapseProgress: progress,
                    expandedPlaceholder: expandedPlaceholder,
                    compactPlaceholder: compactPlaceholder,
                    maxHeight: currentScreenHeight < 700 ? 42 : 48
                )

                rightControls(progress: progress)
                    .padding(.leading, innerSpacing)
            }
            .padding(.horizontal, interpolate(16, 12, progress))
            .padding(.vertical, shellPadding)
            .frame(width: shellWidth)
            .background(
                LiquidGlassCapsuleBackground(
                    cornerRadius: cornerRadius,
                    glassOpacity: glassOpacity,
                    shadowOpacity: shadowOpacity,
                    highlightOpacity: interpolate(0.24, 0.16, progress)
                )
            )
            // Focus ring: brightens the capsule edge when typing
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isFocused ? 0.8 : 0.0),
                                Color.white.opacity(isFocused ? 0.22 : 0.0),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isFocused ? 1.1 : 0.8
                    )
                    .animation(reduceMotion ? .none : .easeOut(duration: 0.18), value: isFocused)
            }
            .scaleEffect(scale)
            .offset(y: verticalOffset)
            .animation(reduceMotion ? .none : .spring(response: 0.34, dampingFraction: 0.86), value: composerVM.collapseProgress)
        }
        .frame(maxWidth: .infinity)
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

    // MARK: - Derived Values

    private var effectiveCollapseProgress: CGFloat {
        if isFocused {
            return min(composerVM.collapseProgress, 0.45)
        }
        return composerVM.collapseProgress
    }

    private var currentScreenHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .screen.bounds.height ?? 844
    }

    private func interpolatedWidth(for progress: CGFloat) -> CGFloat {
        let expanded = min(availableWidth * 0.92, 560)
        let compact = max(min(availableWidth * 0.72, 460), 280)
        return interpolate(expanded, compact, progress)
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * min(max(progress, 0), 1)
    }

    // MARK: - Utility Button

    private func utilityButton(progress: CGFloat) -> some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                showActions.toggle()
                composerVM.setState(showActions ? .expandedActions : .idle)
            }
            HapticManager.impact(style: .light)
        } label: {
            Image(systemName: "plus")
                .font(.systemScaled(interpolate(19, 17, progress), weight: .semibold))
                .foregroundStyle(BereanColor.textPrimary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(interpolate(0.18, 0.22, progress))))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75))
                        .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
                )
                .rotationEffect(.degrees(showActions ? 45 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
        .accessibilityHint("Opens Bible verse, prayer, church notes, safe photo, voice note, sermon clip, reminder, and Space sharing actions")
        .overlay(alignment: .top) {
            if showActions {
                GeometryReader { geo in
                    let windowHeight = currentScreenHeight
                    let composerBottom = windowHeight - keyboardHeight
                    let availableAbove = composerBottom - geo.frame(in: .global).maxY
                    let maxOffset = -(max(min(availableAbove - 16, 300), 180))

                    actionCloud
                        .offset(y: maxOffset)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                .frame(width: 0, height: 0)
            }
        }
    }

    private var actionCloud: some View {
        VStack(spacing: 8) {
            ForEach(Array(quickActions.enumerated()), id: \.element.id) { index, action in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showActions = false
                        composerVM.setState(.idle)
                    }
                    onAction(action.action)
                    HapticManager.impact(style: .medium)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: action.icon)
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(action.color)
                            .frame(width: 20)

                        Text(action.title)
                            .font(AMENFont.medium(15))
                            .foregroundStyle(BereanColor.textPrimary)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.78))
                            .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.03), value: showActions)
            }
        }
        .padding(12)
        .background(
            LiquidGlassCapsuleBackground(
                cornerRadius: 22,
                glassOpacity: 0.14,
                shadowOpacity: 0.10,
                highlightOpacity: 0.18
            )
        )
        .frame(width: min(availableWidth * 0.72, 280))
    }

    // inputField logic extracted to ComposerTextField.swift

    // MARK: - Right Controls

    private func rightControls(progress: CGFloat) -> some View {
        HStack(spacing: interpolate(8, 6, progress)) {
            toolsButton(progress: progress)
            if composerVM.state == .streaming {
                stopButton(progress: progress)
            } else if composerVM.state == .voiceReady {
                voiceWaveform
            } else {
                micButton(progress: progress)
                sendButton(progress: progress)
            }
        }
    }

    private func toolsButton(progress: CGFloat) -> some View {
        Button {
            onTools()
            HapticManager.impact(style: .light)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.systemScaled(interpolate(16, 14, progress), weight: .semibold))
                .foregroundStyle(BereanColor.textPrimary.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.16)))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Response tools")
        .accessibilityHint("Opens Berean modes and tools")
    }

    private func micButton(progress: CGFloat) -> some View {
        Button {
            onVoice()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                composerVM.setState(.voiceReady)
            }
            HapticManager.impact(style: .light)
        } label: {
            Image(systemName: "mic.fill")
                .font(.systemScaled(interpolate(18, 16, progress), weight: .medium))
                .foregroundStyle(BereanColor.textPrimary.opacity(0.72))
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.18)))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
                )
                .opacity(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : interpolate(0.55, 0.4, progress))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice input")
        .accessibilityHint("Starts voice input for Berean")
    }

    private func sendButton(progress: CGFloat) -> some View {
        let canSend = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && composerVM.state != .streaming

        return Button {
            if canSend {
                onSend()
            } else {
                onVoice()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    composerVM.setState(.voiceReady)
                }
            }
            HapticManager.impact(style: .medium)
        } label: {
            ZStack {
                Circle()
                    .fill(
                        canSend
                        ? Color(red: 0.20, green: 0.47, blue: 0.95)
                        : Color(red: 0.20, green: 0.47, blue: 0.95).opacity(0.24)
                    )
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.34), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .frame(width: interpolate(34, 30, progress), height: interpolate(34, 30, progress))

                Image(systemName: canSend ? "arrow.up" : "sparkles")
                    .font(.systemScaled(interpolate(14, 13, progress), weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(canSend ? "Send message" : "Start Berean voice")
        .accessibilityHint(canSend ? "Sends your message to Berean" : "Starts voice input for Berean")
    }

    private func stopButton(progress: CGFloat) -> some View {
        Button {
            onStop?()
            HapticManager.impact(style: .medium)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: interpolate(38, 34, progress), height: interpolate(38, 34, progress))

                Image(systemName: "stop.fill")
                    .font(.systemScaled(interpolate(13, 12, progress), weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop generation")
        .accessibilityHint("Stops Berean's current response")
    }

    private var voiceWaveform: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                ComposerVoiceWaveformBar(index: index, isActive: composerVM.state == .voiceReady)
            }
        }
        .frame(width: 42, height: 36)
        .padding(.horizontal, 6)
    }

    // MARK: - Status Pill

    private func floatingStatusPill(_ type: BereanStatusPillType) -> some View {
        HStack(spacing: 8) {
            Image(systemName: type.icon)
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(BereanColor.textPrimary)

            Text(type.text)
                .font(AMENFont.medium(13))
                .foregroundStyle(BereanColor.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.80))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Support

private struct ComposerVoiceWaveformBar: View {
    let index: Int
    let isActive: Bool

    @State private var height: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.black.opacity(0.65))
            .frame(width: 3, height: height)
            .onChange(of: isActive) { _, active in
                if active {
                    startAnimating()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        height = 4
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
        let delay = Double(index) * 0.12
        withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true).delay(delay)) {
            height = 20 - CGFloat(index)
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @FocusState var focused: Bool
    @Previewable @StateObject var vm = BereanComposerViewModel()

    VStack {
        Spacer()

        BereanComposerBar(
            composerVM: vm,
            messageText: $text,
            isFocused: $focused,
            availableWidth: 390,
            onSend: {},
            onVoice: {},
            onAction: { _ in },
            onTools: {},
            onStop: {}
        )
    }
    .padding(.bottom, 16)
    .background(Color(.systemBackground))
}
