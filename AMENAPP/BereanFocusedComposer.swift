//
//  BereanFocusedComposer.swift
//  AMENAPP
//
//  Enhanced Berean chat composer with scroll-aware visibility,
//  active mode indicator pill, and attachment buttons.
//

import SwiftUI

struct BereanFocusedComposer: View {
    @Binding var inputText: String
    @Binding var currentMode: BereanPersonalityMode
    let isThinking: Bool
    let isAtLimit: Bool
    let onSend: () -> Void
    let onCancel: () -> Void
    let onModeTap: () -> Void

    @FocusState.Binding var isFocused: Bool

    /// MEDIUM FIX: Device-adaptive line limit for the expanding TextField.
    /// lineLimit(1...4) allows up to 4 lines (≈ 96pt + padding). On an iPhone SE
    /// in landscape the available height above the keyboard is roughly 150pt, so
    /// a 4-line composer eats the majority of the visible area. Cap to 2 lines on
    /// any screen shorter than 700pt (SE portrait/landscape, iPod Touch).
    private var adaptiveLineLimit: ClosedRange<Int> {
        UIScreen.main.bounds.height < 700 ? 1...2 : 1...4
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top separator
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)

            VStack(spacing: 8) {
                // Active mode indicator pill
                Button(action: onModeTap) {
                    HStack(spacing: 5) {
                        Image(systemName: currentMode.icon)
                            .font(.systemScaled(10, weight: .semibold))
                        Text(currentMode.rawValue)
                            .font(AMENFont.semiBold(11))
                        Image(systemName: "chevron.up")
                            .font(.systemScaled(8, weight: .bold))
                    }
                    .foregroundStyle(.black.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)

                // Input row
                HStack(spacing: 10) {
                    // Expand text field
                    TextField("", text: $inputText, axis: .vertical)
                        .font(.systemScaled(16, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(adaptiveLineLimit)
                        .focused($isFocused)
                        .disabled(isAtLimit)
                        .overlay(alignment: .leading) {
                            if inputText.isEmpty {
                                Text("Ask Berean...")
                                    .font(.systemScaled(16, weight: .regular))
                                    .foregroundColor(.black.opacity(0.3))
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity)

                    // Send / Stop button
                    Button {
                        if isThinking {
                            onCancel()
                        } else {
                            onSend()
                        }
                    } label: {
                        Circle()
                            .fill(
                                isThinking
                                    ? Color.black
                                    : (inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                       ? Color(white: 0.88)
                                       : Color.black)
                            )
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: isThinking ? "stop.fill" : "arrow.up")
                                    .font(.systemScaled(14, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isThinking && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    // CRITICAL FIX: VoiceOver was announcing "Image, button" with no purpose.
                    // Dynamic label reflects send vs stop so the action is always clear.
                    .accessibilityLabel(isThinking ? "Stop generation" : "Send message")
                    .accessibilityHint(isThinking ? "Stops Berean's current response" : "Sends your message to Berean")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.85))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 10, y: -2)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(uiColor: .systemBackground).opacity(0.95))
        }
    }
}
