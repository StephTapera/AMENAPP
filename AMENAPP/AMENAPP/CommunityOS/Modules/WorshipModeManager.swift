// WorshipModeManager.swift
// AMEN App — Community Around Content OS
//
// Detects active worship music and drives the Worship Mode UI.
// Gated on CommunityOSFlag.worshipMode — all mutations are no-ops when the flag is off.

import Foundation
import SwiftUI

// MARK: - WorshipModeState

enum WorshipModeState {
    case inactive
    case activating
    case active
}

// MARK: - WorshipModeManager

@MainActor
final class WorshipModeManager: ObservableObject {

    // MARK: Shared instance

    static let shared = WorshipModeManager()

    // MARK: Published state

    @Published var state: WorshipModeState = .inactive
    @Published var currentSong: ContentObject?
    @Published var worshipPrompt: String = ""

    // MARK: Init

    private init() {}

    // MARK: Computed

    var isActive: Bool {
        state == .active
    }

    // MARK: Activation

    /// Activates Worship Mode for the given song.
    /// No-op if the `.worshipMode` feature flag is disabled.
    func activate(for song: ContentObject) {
        guard CommunityOSFlagService.shared.isEnabled(.worshipMode) else {
            dlog("[WorshipModeManager] Worship Mode flag is off — activation skipped")
            return
        }

        withAnimation(AppAnimation.stateChange) {
            state = .activating
        }

        currentSong = song
        worshipPrompt = worshipPromptFor(themes: song.themes)

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        withAnimation(AppAnimation.fade) {
            state = .active
        }

        dlog("[WorshipModeManager] Activated for song '\(song.title)' | prompt: \(worshipPrompt)")
    }

    /// Deactivates Worship Mode and resets all published state.
    func deactivate() {
        withAnimation(AppAnimation.fade) {
            state = .inactive
        }
        currentSong = nil
        worshipPrompt = ""
        dlog("[WorshipModeManager] Deactivated")
    }

    // MARK: Prompt selection

    /// Picks a contextually appropriate worship prompt from a curated list.
    func worshipPromptFor(themes: [String]) -> String {
        let lowerThemes = themes.map { $0.lowercased() }

        if lowerThemes.contains(where: { $0.contains("prayer") || $0.contains("pray") }) {
            return "Let this music draw you into prayer."
        }
        if lowerThemes.contains(where: { $0.contains("healing") || $0.contains("comfort") }) {
            return "How is God's healing presence speaking to you through this song?"
        }
        if lowerThemes.contains(where: { $0.contains("praise") || $0.contains("joy") }) {
            return "How does this song invite you to praise God today?"
        }
        if lowerThemes.contains(where: { $0.contains("trust") || $0.contains("faith") }) {
            return "How is God strengthening your trust through this music?"
        }
        if lowerThemes.contains(where: { $0.contains("worship") }) {
            return "How does this music draw you closer to God in worship?"
        }

        // Default prompts — selected from the curated list when no theme matches.
        let defaults: [String] = [
            "How is God speaking to you through this song?",
            "Take a moment to reflect on what this song means to you.",
            "Let this music draw you into prayer.",
            "What truth is God reminding you of right now?",
            "How is this song shaping your heart today?"
        ]

        // Use the title's UTF-8 hash to give a stable but varied selection.
        let index = (currentSong?.title.utf8.reduce(0) { Int($0) + Int($1) } ?? 0) % defaults.count
        return defaults[index]
    }
}

// MARK: - WorshipModeOverlayView

/// Full-screen overlay shown when Worship Mode is active.
struct WorshipModeOverlayView: View {

    @ObservedObject var manager: WorshipModeManager

    var body: some View {
        ZStack {
            // Gradient overlays at top and bottom
            VStack {
                LinearGradient(
                    colors: [Color(.systemBackground).opacity(0.85), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .ignoresSafeArea(edges: .top)

                Spacer()

                LinearGradient(
                    colors: [.clear, Color(.systemBackground).opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .ignoresSafeArea(edges: .bottom)
            }

            VStack(spacing: 0) {
                // Dismiss button
                HStack {
                    Spacer()
                    Button {
                        manager.deactivate()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color(.secondaryLabel))
                            .padding(20)
                    }
                    .glassEffect(.regular.tint(.white.opacity(0.08)).interactive(), in: Circle())
                    .accessibilityLabel("Dismiss Worship Mode")
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }

                Spacer()

                // Centered worship prompt + scripture
                VStack(spacing: 16) {
                    Text(manager.worshipPrompt)
                        .font(.body)
                        .italic()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(.label))
                        .padding(.horizontal, 32)
                        .accessibilityAddTraits(.isStaticText)

                    if let verseRef = manager.currentSong?.linkedVerseRefs.first {
                        Text(verseRef)
                            .font(.callout)
                            .foregroundStyle(Color(.secondaryLabel))
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                // Mode buttons
                HStack(spacing: 20) {
                    WorshipModeActionButton(icon: "hands.sparkles.fill", label: "Pray") {
                        dlog("[WorshipModeOverlay] Pray tapped")
                    }
                    WorshipModeActionButton(icon: "pencil.and.list.clipboard", label: "Journal") {
                        dlog("[WorshipModeOverlay] Journal tapped")
                    }
                    WorshipModeActionButton(icon: "sparkles", label: "Reflect") {
                        dlog("[WorshipModeOverlay] Reflect tapped")
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .transition(.opacity)
        .animation(AppAnimation.fade, value: manager.state)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - WorshipModeActionButton

private struct WorshipModeActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color(.label))
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(.label))
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.white.opacity(0.10)).interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(label)
    }
}
