// BereanGlassComposer.swift
// AMEN App — White Liquid Glass composer for Berean AI assistant
// Handles: text input, mic, quick-action row, mode pill, focus lift animation.

import SwiftUI

// Disambiguate: use the enum version for quick mode switching
typealias BereanComposerMode = BereanQuickMode

// ─── MARK: BereanGlassComposer ───────────────────────────────────────────────

struct BereanGlassComposer: View {
    @Binding var text: String
    @Binding var selectedMode: BereanQuickMode
    @Binding var isRecording: Bool

    var isStreaming: Bool
    var isAtLimit: Bool
    var onSend: () -> Void
    var onMicToggle: () -> Void
    var onAttach: (() -> Void)?
    var onCamera: (() -> Void)?
    var onNotes: (() -> Void)?
    var onScripture: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var composerScale: CGFloat = 1.0
    @State private var composerOffsetY: CGFloat = 0
    @State private var shadowRadius: CGFloat = 20
    @State private var shadowOpacity: Double = AmenOpacity.shadowIdle
    @State private var fillOpacity: Double = AmenOpacity.glassFill

    // Animation 1 — composer entry
    @State private var composerVisible = false

    var body: some View {
        composerBody
            .scaleEffect(composerScale)
            .offset(y: composerOffsetY)
            .shadow(
                color: .black.opacity(shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: shadowRadius * 0.35
            )
            // Animation 1 — entry transition
            .opacity(composerVisible ? 1 : 0)
            .offset(y: composerVisible ? 0 : 18)
            .scaleEffect(composerVisible ? 1 : 0.97)
            .onAppear {
                withAnimation(.amenSpringEntry) {
                    composerVisible = true
                }
            }
            // Animation 6 — glass focus lift
            .onChange(of: isFocused) { focused in
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.72))) {
                    composerScale    = focused ? 1.008 : 1.0
                    composerOffsetY  = focused ? -3 : 0
                    shadowRadius     = focused ? 40 : 20
                    shadowOpacity    = focused ? AmenOpacity.shadowFocused : AmenOpacity.shadowIdle
                    fillOpacity      = focused ? AmenOpacity.glassFillFocused : AmenOpacity.glassFill
                }
            }
    }

    // ─── Composer Body ───────────────────────────────────────────────────────

    private var composerBody: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Text Input Area ──────────────────────────────────────────────
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "",
                    text: $text,
                    prompt: Text(selectedMode.promptHint)
                        .foregroundColor(AmenColor.titleText.opacity(AmenOpacity.placeholderText)),
                    axis: .vertical
                )
                .font(.systemScaled(16))
                .foregroundColor(AmenColor.titleText)
                .lineLimit(1...6)
                .focused($isFocused)
                .disabled(isAtLimit)
                .onSubmit {
                    if !isAtLimit { onSend() }
                }
                .padding(.top, 2)

                // Mic button
                BereanMicButton(isRecording: $isRecording, action: onMicToggle)
                    .opacity(text.isEmpty ? 1 : 0)
                    .overlay(
                        // Send button — appears when text is present
                        sendButton
                            .opacity(text.isEmpty ? 0 : 1),
                        alignment: .center
                    )
            }
            .padding(.horizontal, AmenSpacing.composerH)
            .padding(.top, AmenSpacing.composerV)
            .padding(.bottom, 12)

            Divider()
                .background(AmenColor.divider)
                .padding(.horizontal, AmenSpacing.composerH)

            // ── Quick Actions Row ────────────────────────────────────────────
            HStack(spacing: 10) {
                // Quick action buttons
                if let onAttach {
                    AmenGlassIconButton(systemName: "plus", action: onAttach)
                }
                if let onCamera {
                    AmenGlassIconButton(systemName: "camera", action: onCamera)
                }
                if let onNotes {
                    AmenGlassIconButton(systemName: "note.text", action: onNotes)
                }
                if let onScripture {
                    AmenGlassIconButton(systemName: "book.closed", action: onScripture)
                }

                Spacer()

                // Mode pill — right aligned
                BereanModePill(selectedMode: $selectedMode)
            }
            .padding(.horizontal, AmenSpacing.composerH)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: AmenRadius.composer, style: .continuous)
                .fill(Color.white.opacity(fillOpacity))
                .background(
                    RoundedRectangle(cornerRadius: AmenRadius.composer, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AmenRadius.composer, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.80), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
        )
        .animation(reduceMotion ? .none : .amenEaseQuick, value: fillOpacity)
    }

    // ─── Send Button ─────────────────────────────────────────────────────────

    private var sendButton: some View {
        Button(action: onSend) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isStreaming ? Color(hex: "DC3232") : AmenColor.titleText)
                    .frame(width: 44, height: 44)

                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(GlassPressStyle())
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming)
    }
}

// ─── MARK: BereanActionChipRow ───────────────────────────────────────────────
/// Horizontal scroll row of floating action chips shown on the landing state.

struct BereanActionChipRow: View {
    @Binding var activeChip: BereanChipAction?
    var onSelect: (BereanChipAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let chips = BereanChipAction.allCases
    @State private var chipsVisible: [Bool] = Array(repeating: false, count: BereanChipAction.allCases.count)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(chips.enumerated()), id: \.element) { index, chip in
                    BereanActionChip(
                        title: chip.label,
                        icon: chip.icon,
                        isActive: activeChip == chip
                    ) {
                        withAnimation(reduceMotion ? nil : .amenEaseQuick) {
                            activeChip = activeChip == chip ? nil : chip
                        }
                        onSelect(chip)
                    }
                    // Animation 3 — chip stagger
                    .opacity(chipsVisible[index] ? 1 : 0)
                    .offset(y: chipsVisible[index] ? 0 : 12)
                    .scaleEffect(chipsVisible[index] ? 1 : 0.94)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .onAppear {
            for i in chips.indices {
                let delay = 0.70 + Double(i) * 0.09
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.64)).delay(delay)) {
                    chipsVisible[i] = true
                }
            }
        }
    }
}

// ─── Chip Action Model ───────────────────────────────────────────────────────

enum BereanChipAction: String, CaseIterable, Identifiable {
    case askBerean    = "Ask Berean"
    case searchScripture = "Search Scripture"
    case prayWithMe   = "Pray With Me"
    case reflect      = "Reflect"
    case summarize    = "Summarize"
    case analyzeNotes = "Analyze Notes"

    var id: String { rawValue }
    var label: String { rawValue }

    var icon: String {
        switch self {
        case .askBerean:       return "sparkles"
        case .searchScripture: return "book.closed"
        case .prayWithMe:      return "hands.sparkles"
        case .reflect:         return "moon.stars"
        case .summarize:       return "text.alignleft"
        case .analyzeNotes:    return "note.text"
        }
    }

    /// The prompt prefix injected into the composer when this chip is tapped
    var promptSeed: String {
        switch self {
        case .askBerean:       return ""
        case .searchScripture: return "Search Scripture for: "
        case .prayWithMe:      return "Help me pray about: "
        case .reflect:         return "Help me reflect on: "
        case .summarize:       return "Summarize: "
        case .analyzeNotes:    return "Analyze my notes: "
        }
    }
}

// Note: Color.init(hex:) extension already defined globally in the project
