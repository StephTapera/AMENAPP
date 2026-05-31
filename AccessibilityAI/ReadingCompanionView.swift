// ReadingCompanionView.swift
// AMEN Universal Accessibility Engine — A4 Reading & Narration
// Floating launch button + full settings/playback sheet for reading companion.

import SwiftUI
import FirebaseAuth

// MARK: - ReadingCompanionButton

/// Floating book button that opens ReadingCompanionSheet.
/// Only renders when the `a11yReadingEnabled` flag is on.
struct ReadingCompanionButton: View {

    @StateObject private var flags = TrustAccessibilityFeatureFlags.shared
    @State private var showSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Guard: feature flag
        if flags.a11yReadingEnabled {
            Button {
                showSheet = true
            } label: {
                Image(systemName: "book.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                    .padding(14)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reading Companion")
            .sheet(isPresented: $showSheet) {
                ReadingCompanionSheet()
            }
        }
    }
}

// MARK: - ReadingCompanionSheet

/// Full settings and playback sheet for the reading companion.
struct ReadingCompanionSheet: View {

    // MARK: Observed / Environment

    @StateObject private var bridge = AccessibilityProfileBridge.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Local working copy of narration prefs

    @State private var selectedVoice: NarrationVoice = .conversational
    @State private var speed: Double = 1.0
    @State private var dyslexiaEnabled: Bool = false
    @State private var readingLevel: ReadingLevel = .standard
    @State private var didLoad = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // ── Voice Picker ────────────────────────────────────
                    sectionHeader("Voice")
                    voicePicker

                    // ── Speed Slider ────────────────────────────────────
                    sectionHeader("Speed")
                    speedSlider

                    // ── Dyslexia Toggle ─────────────────────────────────
                    dyslexiaToggle

                    // ── Reading Level ───────────────────────────────────
                    sectionHeader("Reading Level")
                    readingLevelPicker

                    // ── Start Reading ────────────────────────────────────
                    startReadingButton

                    // ── Footer disclaimer ────────────────────────────────
                    Text(A11yVoiceLibrary.disclaimer)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Reading Companion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        persistChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { loadFromProfile() }
        .onChange(of: bridge.profile) { _, _ in
            if !didLoad { loadFromProfile() }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var voicePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(A11yVoiceLibrary.voices, id: \.self) { voice in
                    voicePill(voice)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Voice selector")
    }

    private func voicePill(_ voice: NarrationVoice) -> some View {
        let isSelected = selectedVoice == voice
        return Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.7)) {
                selectedVoice = voice
            }
        } label: {
            Text(voice.displayName)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected
                              ? AmenTheme.Colors.amenPurple.opacity(0.18)
                              : Color(.systemGray5))
                )
                .foregroundStyle(isSelected ? AmenTheme.Colors.amenPurple : .primary)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? AmenTheme.Colors.amenPurple : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(voice.displayName)
    }

    private var speedSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Speed")
                    .font(.body)
                Spacer()
                Text("×\(String(format: "%.1f", speed))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                    .accessibilityLabel("Speed \(String(format: "%.1f", speed)) times")
            }
            Slider(value: $speed, in: 0.5...2.0, step: 0.1)
                .tint(AmenTheme.Colors.amenPurple)
                .accessibilityLabel("Playback speed")
                .accessibilityValue("×\(String(format: "%.1f", speed))")
        }
    }

    private var dyslexiaToggle: some View {
        Toggle(isOn: $dyslexiaEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dyslexia-friendly spacing")
                    .font(.body)
                Text("Wider word and letter spacing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(AmenTheme.Colors.amenPurple)
    }

    private var readingLevelPicker: some View {
        Picker("Reading Level", selection: $readingLevel) {
            ForEach(ReadingLevel.allCases, id: \.self) { level in
                Text(level.friendlyName).tag(level)
            }
        }
        .pickerStyle(.menu)
        .tint(AmenTheme.Colors.amenPurple)
        .accessibilityLabel("Reading level")
    }

    private var startReadingButton: some View {
        Button {
            persistChanges()
            // Caller's container wires actual TTS playback via the profile.
            dismiss()
        } label: {
            Label("Start Reading", systemImage: "play.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AmenTheme.Colors.amenPurple)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start Reading")
        .padding(.top, 8)
    }

    // MARK: - Profile Sync

    private func loadFromProfile() {
        let p = bridge.profile
        selectedVoice   = p.narration.voice
        speed           = p.narration.speed
        dyslexiaEnabled = p.fontPrefs.dyslexiaOptimized
        readingLevel    = p.readingLevel
        didLoad         = true
    }

    private func persistChanges() {
        // Build the updated profile from local working state.
        var updated = bridge.profile
        updated.narration.voice         = selectedVoice
        updated.narration.speed         = speed
        updated.fontPrefs.dyslexiaOptimized = dyslexiaEnabled
        if dyslexiaEnabled {
            updated.fontPrefs.lineHeightMultiplier = 1.5
            updated.fontPrefs.wordSpacing          = 0.1
        } else {
            updated.fontPrefs.lineHeightMultiplier = 1.0
            updated.fontPrefs.wordSpacing          = 0.0
        }
        updated.readingLevel = readingLevel

        // Persist asynchronously — fire and forget from the UI layer.
        // The userId is best injected by the host view; for now we use
        // FirebaseAuth if available so the sheet remains self-contained.
        Task {
            do {
                let uid = await resolveCurrentUserId()
                guard let uid else { return }
                try await AccessibilityProfileService.shared.saveProfile(updated, userId: uid)
            } catch {
                // Non-critical: local state already reflects the change.
            }
        }
    }

    @MainActor
    private func resolveCurrentUserId() async -> String? {
        return Auth.auth().currentUser?.uid
    }
}

// MARK: - ReadingLevel Friendly Names

private extension ReadingLevel {
    var friendlyName: String {
        switch self {
        case .elementary:   return "Elementary"
        case .middleSchool: return "Middle School"
        case .plain:        return "Plain Language"
        case .standard:     return "Standard"
        case .academic:     return "Academic"
        case .esl:          return "ESL-Friendly"
        }
    }
}
