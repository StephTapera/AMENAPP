//
//  AmenZeroDistractionModifier.swift
//  AMENAPP
//
//  Zero-distraction mode for media viewing. Tap or hold to hide controls;
//  tap again to restore. Fully accessible via VoiceOver toggle. Falls back
//  to an instant visibility toggle when Reduce Motion is enabled.
//

import SwiftUI

// MARK: - View Modifier

struct AmenZeroDistractionModifier: ViewModifier {
    @Binding var controlsHidden: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                toggleControls()
            }
            .overlay(alignment: .topTrailing) {
                if !controlsHidden {
                    focusButton
                        .padding(.top, 56)
                        .padding(.trailing, 16)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .accessibilityAction(named: controlsHidden ? "Show controls" : "Hide controls") {
                toggleControls()
            }
    }

    private var focusButton: some View {
        Button {
            toggleControls()
        } label: {
            Image(systemName: "eye.slash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .padding(10)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Enter focus view")
        .accessibilityHint("Hides controls. Tap anywhere to restore.")
    }

    private func toggleControls() {
        if reduceMotion {
            controlsHidden.toggle()
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                controlsHidden.toggle()
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Wraps the view in zero-distraction mode. Tap hides/shows controls.
    /// Pass the same `controlsHidden` binding to the controls overlay so they
    /// fade out when the user enters focus view.
    func amenZeroDistraction(controlsHidden: Binding<Bool>) -> some View {
        modifier(AmenZeroDistractionModifier(controlsHidden: controlsHidden))
    }
}

// MARK: - Controls Visibility Modifier

/// Apply to any control overlay that should hide during zero-distraction mode.
struct AmenControlsVisibilityModifier: ViewModifier {
    let controlsHidden: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        content
            // VoiceOver always keeps controls accessible even when visually hidden
            .opacity(controlsHidden && !voiceOverEnabled ? 0 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: controlsHidden)
            .allowsHitTesting(!controlsHidden || voiceOverEnabled)
    }
}

extension View {
    /// Hides this control view when zero-distraction mode is active.
    func hiddenDuringZeroDistraction(_ controlsHidden: Bool) -> some View {
        modifier(AmenControlsVisibilityModifier(controlsHidden: controlsHidden))
    }
}

// MARK: - Preview

#Preview("Zero Distraction Mode") {
    struct PreviewWrapper: View {
        @State private var controlsHidden = false

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                // Simulated media content
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.gray.opacity(0.3))
                    .ignoresSafeArea()

                // Controls overlay — fades out when hidden
                VStack {
                    HStack {
                        Spacer()
                        Button("Close") {}
                            .foregroundStyle(.white)
                    }
                    .padding()
                    .hiddenDuringZeroDistraction(controlsHidden)

                    Spacer()

                    HStack(spacing: 24) {
                        Image(systemName: "heart")
                        Image(systemName: "bubble.left")
                        Image(systemName: "paperplane")
                    }
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(.bottom, 48)
                    .hiddenDuringZeroDistraction(controlsHidden)
                }
            }
            .amenZeroDistraction(controlsHidden: $controlsHidden)
        }
    }

    return PreviewWrapper()
}
