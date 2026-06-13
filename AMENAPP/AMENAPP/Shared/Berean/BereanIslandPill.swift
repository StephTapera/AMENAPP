// BereanIslandPill.swift
// AMEN — Berean Island Wave 1
//
// GlassPill: the in-app Berean Island. One glass layer; all contents are flat.
// Rules:
//   · 44 pt compact height
//   · matchedGeometryEffect id "berean.island" drives morph between states
//   · Every animation goes through Motion.adaptive (BreathMotion.swift)
//   · No nested glass (caller must not embed in another glass surface)
//
// Feature flag: AMENFeatureFlags.bereanIslandEnabled

import SwiftUI

// MARK: - GlassPill

/// The in-app Berean Island. Drives all visual states from `IslandStateMachine`.
struct GlassPill: View {

    @Bindable var machine: IslandStateMachine
    var onAction: (IslandAction) -> Void
    var onQuery: (String) -> Void

    @Namespace private var morphNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch machine.state {
            case .hidden:
                Color.clear.frame(height: 0)

            case .compact(let whisper):
                CompactPill(whisper: whisper, morphNS: morphNS) {
                    withAnimation(morphAnimation) {
                        machine.expand(context: defaultContext)
                    }
                }
                .transition(pillTransition)

            case .expanded(let context):
                ExpandedPanel(
                    context: context,
                    morphNS: morphNS,
                    onQuery: { q in
                        onQuery(q)
                        withAnimation(morphAnimation) { machine.compact() }
                    },
                    onAction: { action in
                        onAction(action)
                        withAnimation(morphAnimation) { machine.compact() }
                    },
                    onDismiss: {
                        withAnimation(morphAnimation) { machine.compact() }
                    }
                )
                .transition(panelTransition)

            case .live(let session):
                LiveSessionBar(
                    session: session,
                    morphNS: morphNS,
                    onEnd: {
                        withAnimation(morphAnimation) { machine.endSession() }
                    }
                )
                .transition(pillTransition)

            case .actionReady(let suggestion):
                SuggestionCard(
                    suggestion: suggestion,
                    morphNS: morphNS,
                    onAccept: {
                        onAction(suggestion.action)
                        withAnimation(morphAnimation) { machine.hide() }
                    },
                    onDismiss: {
                        withAnimation(morphAnimation) { machine.hide() }
                    }
                )
                .transition(cardTransition)
            }
        }
        .animation(morphAnimation, value: machine.state)
    }

    // MARK: - Animations

    private var morphAnimation: Animation {
        Motion.adaptive(
            animation: .spring(response: 0.38, dampingFraction: 0.78),
            reduceMotion: reduceMotion
        )
    }

    private var pillTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.85).combined(with: .opacity),
            removal:   .scale(scale: 0.92).combined(with: .opacity)
        )
    }

    private var panelTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity),
            removal:   .scale(scale: 0.96).combined(with: .opacity)
        )
    }

    private var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal:   .move(edge: .bottom).combined(with: .opacity)
        )
    }

    // MARK: - Default context for tap-to-expand

    private var defaultContext: IslandContext {
        IslandContext(
            surface: .feed,
            prefill: nil,
            quickActions: Array(IslandAction.allCases.prefix(4)),
            lastAnswerID: nil
        )
    }
}

// MARK: - Compact Pill

private struct CompactPill: View {
    let whisper: String?
    let morphNS: Namespace.ID
    let onTap: () -> Void

    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "book.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)

                if let w = whisper {
                    Text(String(w.prefix(24)))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.separator, lineWidth: 0.5))
            .matchedGeometryEffect(id: "berean.island", in: morphNS)
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.96 : 1.0)
        .animation(
            Motion.adaptive(
                animation: .spring(response: 0.25, dampingFraction: 0.7),
                reduceMotion: reduceMotion
            ),
            value: pressed
        )
        .accessibilityLabel("Berean — \(whisper ?? "tap to ask")")
        .accessibilityHint("Double-tap to expand")
        ._onButtonGesture(pressing: { pressed = $0 }, perform: {})
    }
}

// MARK: - Expanded Panel

private struct ExpandedPanel: View {
    let context: IslandContext
    let morphNS: Namespace.ID
    let onQuery: (String) -> Void
    let onAction: (IslandAction) -> Void
    let onDismiss: () -> Void

    @State private var queryText = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "book.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                Text("Ask Berean")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close Berean")
            }

            // Optional pre-fill label
            if let pre = context.prefill {
                Text("\"\(pre)\"")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
            }

            // Query field
            HStack(spacing: 8) {
                TextField("Ask a question…", text: $queryText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .submitLabel(.send)
                    .focused($fieldFocused)
                    .onSubmit { submitQuery() }

                Button(action: submitQuery) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(queryText.isEmpty ? Color.secondary : Color.accentColor)
                }
                .disabled(queryText.isEmpty)
                .accessibilityLabel("Send")
            }
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Quick actions
            if !context.quickActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(context.quickActions, id: \.self) { action in
                            QuickActionChip(action: action) { onAction(action) }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.separator, lineWidth: 0.5))
        .matchedGeometryEffect(id: "berean.island", in: morphNS)
        .onAppear { fieldFocused = true }
    }

    private func submitQuery() {
        let q = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        onQuery(q)
        queryText = ""
    }
}

private struct QuickActionChip: View {
    let action: IslandAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label(action.displayLabel, systemImage: action.systemImage)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.displayLabel)
    }
}

// MARK: - Live Session Bar

private struct LiveSessionBar: View {
    let session: IslandLiveSession
    let morphNS: Namespace.ID
    let onEnd: () -> Void

    @State private var pulseOn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .scaleEffect(pulseOn ? 1.4 : 1.0)
                .animation(
                    Motion.adaptive(
                        animation: .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                        reduceMotion: reduceMotion,
                        isAmbient: true
                    ),
                    value: pulseOn
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.statusLine)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                if let progress = session.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                        .accessibilityLabel("\(Int(progress * 100))% complete")
                }
            }

            Spacer()

            Button(action: onEnd) {
                Text("End")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.10))
                    .clipShape(Capsule())
            }
            .accessibilityLabel("End \(session.statusLine)")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.separator, lineWidth: 0.5))
        .matchedGeometryEffect(id: "berean.island", in: morphNS)
        .onAppear { pulseOn = true }
    }
}

// MARK: - Suggestion Card

private struct SuggestionCard: View {
    let suggestion: IslandSuggestion
    let morphNS: Namespace.ID
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Action icon
            Image(systemName: suggestion.action.systemImage)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            // Message + context chips
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.message)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)

                if !suggestion.contextChips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(suggestion.contextChips.prefix(2), id: \.label) { chip in
                            Text(chip.label)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Accept / Dismiss buttons
            VStack(spacing: 6) {
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Accept: \(suggestion.message)")

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .frame(width: 34, height: 34)
                        .background(Color(.secondarySystemFill))
                        .foregroundStyle(.secondary)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Dismiss suggestion")
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.separator, lineWidth: 0.5))
        .matchedGeometryEffect(id: "berean.island", in: morphNS)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - IslandAction display helpers

extension IslandAction {
    var displayLabel: String {
        switch self {
        case .askBerean:           return "Ask Berean"
        case .saveNote:            return "Save Note"
        case .openBible:           return "Open Bible"
        case .prayNow:             return "Pray Now"
        case .shareToAmen:         return "Share"
        case .messageGroup:        return "Message Group"
        case .createReminder:      return "Remind Me"
        case .planVisit:           return "Plan Visit"
        case .startStudy:          return "Start Study"
        case .compareTranslations: return "Compare"
        }
    }

    var systemImage: String {
        switch self {
        case .askBerean:           return "bubble.left.and.bubble.right"
        case .saveNote:            return "note.text.badge.plus"
        case .openBible:           return "book"
        case .prayNow:             return "hands.sparkles"
        case .shareToAmen:         return "square.and.arrow.up"
        case .messageGroup:        return "person.3"
        case .createReminder:      return "bell"
        case .planVisit:           return "mappin"
        case .startStudy:          return "graduationcap"
        case .compareTranslations: return "arrow.left.and.right"
        }
    }
}
