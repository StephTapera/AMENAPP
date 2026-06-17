// LiquidGlassInputBar.swift
// AMEN — Berean Reading Surface: BereanStudyInputBar component (W1)
//
// Single text input bar used app-wide on the Berean reading surface.
// Mode indicator dot, optional mic, optional scripture lookup, send button.
// ReduceTransparency: solid bereanIvory background.

import SwiftUI

/// Text input bar for the Berean reading surface.
/// Keyboard-adjacent — caller places via .safeAreaInset(edge: .bottom).
struct BereanStudyInputBar: View {

    @Binding var text: String
    let placeholder: String
    let showMic: Bool
    let showScriptureLookup: Bool
    let modeIndicator: BereanBackendMode?
    let onSend: () -> Void
    let onMic: (() -> Void)?
    let onScriptureLookup: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        text: Binding<String>,
        placeholder: String = "Ask Berean…",
        showMic: Bool = true,
        showScriptureLookup: Bool = false,
        modeIndicator: BereanBackendMode? = nil,
        onSend: @escaping () -> Void,
        onMic: (() -> Void)? = nil,
        onScriptureLookup: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.showMic = showMic
        self.showScriptureLookup = showScriptureLookup
        self.modeIndicator = modeIndicator
        self.onSend = onSend
        self.onMic = onMic
        self.onScriptureLookup = onScriptureLookup
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let mode = modeIndicator {
                Circle()
                    .fill(modeColor(mode))
                    .frame(width: 8, height: 8)
                    .padding(.bottom, 14)
                    .accessibilityLabel("\(mode.rawValue) mode active")
            }

            TextField(placeholder, text: $text, axis: .vertical)
                .font(BereanType.body())
                .foregroundStyle(Color.bereanInk)
                .focused($isFocused)
                .lineLimit(1...5)
                .padding(.vertical, 10)
                .accessibilityLabel(placeholder)

            HStack(spacing: 2) {
                if showScriptureLookup, let lookup = onScriptureLookup {
                    Button(action: lookup) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.bereanInk.opacity(0.55))
                    }
                    .frame(width: BereanMetrics.minTapTarget, height: BereanMetrics.minTapTarget)
                    .accessibilityLabel("Look up scripture")
                }

                if showMic, let mic = onMic {
                    Button(action: mic) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.bereanInk.opacity(0.55))
                    }
                    .frame(width: BereanMetrics.minTapTarget, height: BereanMetrics.minTapTarget)
                    .accessibilityLabel("Voice input")
                }

                Button {
                    onSend()
                    text = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? Color.bereanInk : Color.bereanTan)
                        .animation(.easeInOut(duration: 0.15), value: canSend)
                }
                .frame(width: BereanMetrics.minTapTarget, height: BereanMetrics.minTapTarget)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 14)
        .background(barBackground)
        .clipShape(RoundedRectangle(cornerRadius: BereanMetrics.inputBarRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BereanMetrics.inputBarRadius, style: .continuous)
                .strokeBorder(Color.bereanTan.opacity(isFocused ? 0.6 : 0.35), lineWidth: BereanMetrics.strokeWidth)
        )
        .shadow(
            color: Color.bereanInk.opacity(BereanMetrics.shadowOpacity),
            radius: BereanMetrics.shadowRadius, y: 2
        )
        .animation(.easeInOut(duration: 0.12), value: isFocused)
    }

    @ViewBuilder
    private var barBackground: some View {
        if reduceTransparency {
            Color.bereanIvory
        } else {
            Color.bereanIvory.opacity(0.88)
                .background(.ultraThinMaterial)
        }
    }

    private func modeColor(_ mode: BereanBackendMode) -> Color {
        switch mode {
        case .ask:     return Color.bereanInk.opacity(0.5)
        case .discern: return Color.bereanWine.opacity(0.8)
        case .build:   return Color.bereanInk.opacity(0.4)
        case .reflect: return Color.bereanTan
        case .guard_:  return Color.bereanWine
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    VStack {
        Spacer()
        BereanStudyInputBar(
            text: $text,
            showMic: true,
            modeIndicator: .ask,
            onSend: {},
            onMic: {}
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    .background(Color.bereanIvory)
}
