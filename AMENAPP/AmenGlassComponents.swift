// AmenGlassComponents.swift
// AMEN App — Reusable white Liquid Glass components
// Used by Berean AI assistant and any future glass-surface views.

import SwiftUI

// ─── MARK: AmenGlassSurface ──────────────────────────────────────────────────
/// Base glass container. All elevated glass surfaces derive from this.

struct AmenGlassSurface: View {
    var cornerRadius: CGFloat = AmenRadius.card
    var fillOpacity: CGFloat  = AmenOpacity.glassFill
    var shadowRadius: CGFloat = 20
    var shadowY: CGFloat      = 6
    var shadowOpacity: CGFloat = AmenOpacity.shadowIdle

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(fillOpacity))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.80),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
    }
}

// ─── MARK: AmenGlassIconButton ───────────────────────────────────────────────
/// Small circular glass icon button used inside the composer quick-action row.

struct AmenGlassIconButton: View {
    let systemName: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            action()
        }) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.82))
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(Color.white.opacity(0.30), lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                    .frame(width: AmenSpacing.quickActionSize, height: AmenSpacing.quickActionSize)

                Image(systemName: systemName)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundColor(AmenColor.titleText)
            }
        }
        .buttonStyle(GlassPressStyle())
    }
}

// ─── MARK: BereanActionChip ──────────────────────────────────────────────────
/// Floating Liquid Glass action chip. Appears above the composer in landing state.

struct BereanActionChip: View {
    let title: String
    let icon: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.amenEaseQuick) { }
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundColor(isActive ? AmenColor.chipActiveText : AmenColor.titleText)

                Text(title)
                    .font(.systemScaled(13.5, weight: .medium))
                    .foregroundColor(isActive ? AmenColor.chipActiveText : AmenColor.titleText)
                    .lineLimit(1)
            }
            .padding(.horizontal, AmenSpacing.chipH)
            .padding(.vertical, AmenSpacing.chipV)
            .background(
                Capsule()
                    .fill(isActive ? AmenColor.chipActive : Color.white.opacity(0.84))
                    .background(
                        Capsule()
                            .fill(isActive ? AmenColor.chipActive : Color.clear)
                            .background(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                isActive
                                ? Color.clear
                                : Color.white.opacity(0.50),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
            )
        }
        .buttonStyle(GlassPressStyle())
        .animation(.amenEaseQuick, value: isActive)
    }
}

// ─── MARK: BereanModePill ────────────────────────────────────────────────────
/// Mode/context selector pill — sits in the bottom-right of the composer.

struct BereanModePill: View {
    @Binding var selectedMode: BereanQuickMode
    @State private var showPicker = false

    var body: some View {
        Button {
            withAnimation(.amenSpringBouncy) {
                showPicker.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selectedMode.icon)
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundColor(AmenColor.titleText)

                Text(selectedMode.label)
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundColor(AmenColor.titleText)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.systemScaled(8, weight: .semibold))
                    .foregroundColor(AmenColor.mutedText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.90))
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(Color.white.opacity(0.40), lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
            )
        }
        .buttonStyle(GlassPressStyle())
        .popover(isPresented: $showPicker) {
            BereanModePickerView(selectedMode: $selectedMode, isPresented: $showPicker)
        }
    }
}

// ─── Mode Model ──────────────────────────────────────────────────────────────

enum BereanQuickMode: String, CaseIterable, Identifiable {
    case berean     = "Berean"
    case prayer     = "Prayer"
    case reflection = "Reflection"
    case scripture  = "Scripture"
    case notes      = "Notes"

    var id: String { rawValue }
    var label: String { rawValue }
    var icon: String {
        switch self {
        case .berean:     return "sparkles"
        case .prayer:     return "hands.sparkles"
        case .reflection: return "moon.stars"
        case .scripture:  return "book.closed"
        case .notes:      return "note.text"
        }
    }
    var promptHint: String {
        switch self {
        case .berean:     return "Ask Berean anything..."
        case .prayer:     return "What would you like to pray about?"
        case .reflection: return "What's on your heart today?"
        case .scripture:  return "Search or ask about Scripture..."
        case .notes:      return "Capture a thought or insight..."
        }
    }
}

// ─── Mode Picker Popover ─────────────────────────────────────────────────────

private struct BereanModePickerView: View {
    @Binding var selectedMode: BereanQuickMode
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Mode")
                .font(.systemScaled(11, weight: .semibold))
                .foregroundColor(AmenColor.mutedText)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)

            ForEach(BereanQuickMode.allCases) { mode in
                Button {
                    withAnimation(.amenEaseQuick) {
                        selectedMode = mode
                        isPresented = false
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.icon)
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundColor(selectedMode == mode ? AmenColor.accent : AmenColor.bodyText)
                            .frame(width: 22)
                        Text(mode.label)
                            .font(.systemScaled(14, weight: selectedMode == mode ? .semibold : .regular))
                            .foregroundColor(AmenColor.titleText)
                        Spacer()
                        if selectedMode == mode {
                            Image(systemName: "checkmark")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundColor(AmenColor.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
        }
        .frame(width: 220)
        .background(AmenColor.background)
        .presentationCompactAdaptation(.popover)
    }
}

// ─── MARK: BereanMicButton ───────────────────────────────────────────────────
/// Microphone button with recording pulse animation (Animation 5).

struct BereanMicButton: View {
    @Binding var isRecording: Bool
    let action: () -> Void

    @State private var ring1Scale: CGFloat = 0.6
    @State private var ring1Opacity: Double = 0.5
    @State private var ring2Scale: CGFloat = 0.6
    @State private var ring2Opacity: Double = 0.5
    @State private var coreScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Pulse rings — only active during recording
            if isRecording {
                Circle()
                    .stroke(Color.black.opacity(0.12), lineWidth: 1.5)
                    .scaleEffect(ring1Scale)
                    .opacity(ring1Opacity)
                    .frame(width: 44, height: 44)

                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1.5)
                    .scaleEffect(ring2Scale)
                    .opacity(ring2Opacity)
                    .frame(width: 44, height: 44)
            }

            // Core button
            Button(action: action) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isRecording ? Color(hex: "DC3232") : Color.white.opacity(0.90))
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.40), lineWidth: 0.75)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                        .frame(width: 44, height: 44)

                    Image(systemName: isRecording ? "stop.fill" : "mic")
                        .font(.systemScaled(16, weight: .medium))
                        .foregroundColor(isRecording ? .white : AmenColor.titleText)
                }
            }
            .buttonStyle(GlassPressStyle())
            .scaleEffect(coreScale)
        }
        .onChange(of: isRecording) { recording in
            if recording {
                startPulse()
            } else {
                stopPulse()
            }
        }
    }

    private func startPulse() {
        // Ring 1
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            ring1Scale = 1.6
            ring1Opacity = 0
        }
        // Ring 2 — delayed 0.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard isRecording else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                ring2Scale = 1.6
                ring2Opacity = 0
            }
        }
        // Core pulse
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            coreScale = 1.06
        }
    }

    private func stopPulse() {
        withAnimation(.none) {
            ring1Scale = 0.6
            ring1Opacity = 0.5
            ring2Scale = 0.6
            ring2Opacity = 0.5
            coreScale = 1.0
        }
    }
}

// ─── MARK: BereanTypingDots ──────────────────────────────────────────────────
/// Three-dot typing indicator for Berean's response (Animation 4 — typing indicator).

struct BereanTypingDots: View {
    @State private var dot1Y: CGFloat = 0
    @State private var dot2Y: CGFloat = 0
    @State private var dot3Y: CGFloat = 0
    @State private var dot1Opacity: Double = 0.3
    @State private var dot2Opacity: Double = 0.3
    @State private var dot3Opacity: Double = 0.3

    var body: some View {
        HStack(spacing: 4) {
            dot(yOffset: $dot1Y, opacity: $dot1Opacity)
            dot(yOffset: $dot2Y, opacity: $dot2Opacity)
            dot(yOffset: $dot3Y, opacity: $dot3Opacity)
        }
        .onAppear { animateDots() }
    }

    private func dot(yOffset: Binding<CGFloat>, opacity: Binding<Double>) -> some View {
        Circle()
            .fill(AmenColor.mutedText)
            .frame(width: 6, height: 6)
            .offset(y: yOffset.wrappedValue)
            .opacity(opacity.wrappedValue)
    }

    private func animateDots() {
        // Dot 1 — no delay
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false).delay(0)) {
            dot1Y = -3; dot1Opacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                dot1Y = 0; dot1Opacity = 0.3
            }
        }
        // Dot 2 — 0.2s delay
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false).delay(0.2)) {
            dot2Y = -3; dot2Opacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                dot2Y = 0; dot2Opacity = 0.3
            }
        }
        // Dot 3 — 0.4s delay
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false).delay(0.4)) {
            dot3Y = -3; dot3Opacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                dot3Y = 0; dot3Opacity = 0.3
            }
        }
    }
}

// ─── MARK: GlassPressStyle ───────────────────────────────────────────────────
/// Reusable button press style that applies a quick scale-down on press.

struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.amenSpringBouncy, value: configuration.isPressed)
    }
}

// ─── MARK: HeroTextLine ──────────────────────────────────────────────────────
/// A single line of staggered hero text (Animation 2 — hero text stagger).
/// Wraps text in a clipped frame and animates offset Y upward on appear.

struct HeroTextLine: View {
    let text: String
    let font: Font
    let color: Color
    let delay: Double
    let lineHeight: CGFloat

    @State private var appeared = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .frame(height: lineHeight, alignment: .bottom)
            .clipped()
            .offset(y: appeared ? 0 : lineHeight)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(delay)) {
                    appeared = true
                }
            }
    }
}

// ─── MARK: Color Extension ───────────────────────────────────────────────────
// (Deduplicating — only add if not already defined elsewhere in project)
// If Color(hex:) already exists in your project, remove this extension.

// Note: Color.init(hex:) extension already defined globally in the project
