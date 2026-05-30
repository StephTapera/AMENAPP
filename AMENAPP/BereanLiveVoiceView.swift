// BereanLiveVoiceView.swift
// AMENAPP
//
// Berean Live Voice — Main voice interface
// Liquid Glass, white background, black text
//
// Usage:
//   BereanLiveVoiceView(mode: .conversation)
//   BereanLiveVoiceView(mode: .prayer)
//
// Spec called for BereanVoiceView.swift, but that filename is already occupied
// by BereanWaveformBar. This file is the canonical Live Voice screen.
// No existing files are modified.

import SwiftUI

// MARK: - BereanLiveVoiceView

struct BereanLiveVoiceView: View {

    // -------------------------------------------------------------------------
    // MARK: Inputs
    // -------------------------------------------------------------------------

    let mode: BereanVoiceMode

    // -------------------------------------------------------------------------
    // MARK: State
    // -------------------------------------------------------------------------

    @StateObject private var vm = BereanVoiceViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Active mode selection — may be changed in-session via the chip row.
    @State private var selectedMode: BereanVoiceMode

    // Voice settings sheet
    @State private var showVoiceSettings = false
    @AppStorage("berean.voice.voiceIndex") private var selectedVoiceIndex = 0
    @AppStorage("berean.voice.personality") private var selectedPersonality = 1
    @AppStorage("berean.voice.speechSpeed") private var speechSpeed: Double = 1.0

    init(mode: BereanVoiceMode = .conversation) {
        self.mode = mode
        _selectedMode = State(initialValue: mode)
    }

    // -------------------------------------------------------------------------
    // MARK: Body
    // -------------------------------------------------------------------------

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()

                // Main content
                mainContent

                // Feature-flag gate: if voice is disabled, show "Coming Soon"
                if !BereanVoiceFeatureFlags.bereanVoiceEnabled {
                    comingSoonOverlay
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showVoiceSettings) {
            VoiceSettingsSheet(
                selectedVoiceIndex: $selectedVoiceIndex,
                selectedPersonality: $selectedPersonality,
                speechSpeed: $speechSpeed
            )
        }
        .onAppear {
            if BereanVoiceFeatureFlags.bereanVoiceEnabled {
                Task { await vm.startSession(mode: selectedMode) }
            }
        }
        .onDisappear {
            Task { await vm.stopSession() }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Main Content
    // -------------------------------------------------------------------------

    private var mainContent: some View {
        VStack(spacing: 0) {

            // ---- Top bar ----
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Spacer()

            // ---- Orb + state label ----
            orbSection
                .padding(.bottom, 12)

            // ---- Acknowledgment label ----
            acknowledgmentLabel
                .frame(height: 20)
                .padding(.bottom, 8)

            // ---- Rolling transcript (last 3 segments) ----
            transcriptSection
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            // ---- Streaming response ----
            currentResponseText
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            Spacer()

            // ---- Bottom action bar ----
            bottomBar
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Top Bar
    // -------------------------------------------------------------------------

    private var topBar: some View {
        HStack {
            modePill
            Spacer()
            gearButton
            dismissButton
        }
    }

    private var gearButton: some View {
        Button { showVoiceSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Voice Settings")
    }

    private var modePill: some View {
        HStack(spacing: 6) {
            Image(systemName: selectedMode.systemIconName)
                .font(.system(size: 12, weight: .medium))
            Text(selectedMode.displayName)
                .font(.custom("OpenSans-SemiBold", size: 13))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    private var dismissButton: some View {
        Button {
            Task { await vm.stopSession() }
            dismiss()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 32, height: 32)
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("Dismiss")
    }

    // -------------------------------------------------------------------------
    // MARK: Orb + State Label
    // -------------------------------------------------------------------------

    private var orbSection: some View {
        VStack(spacing: 12) {
            BereanVoiceOrb(
                state:    vm.voiceState,
                micLevel: vm.microphoneLevel,
                mode:     selectedMode
            )
            .frame(width: 80, height: 80)

            Text(vm.voiceState.displayLabel)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .animation(
                    reduceMotion ? nil : Motion.adaptive(.easeInOut(duration: 0.25)),
                    value: vm.voiceState.rawValue
                )
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Acknowledgment Label
    // -------------------------------------------------------------------------

    private var acknowledgmentLabel: some View {
        Text(vm.acknowledgmentText)
            .font(.custom("OpenSans-Regular", size: 13).italic())
            .foregroundStyle(.secondary)
            .transition(.opacity)
            .animation(
                reduceMotion ? nil : Motion.adaptive(.easeInOut(duration: 0.3)),
                value: vm.acknowledgmentText
            )
    }

    // -------------------------------------------------------------------------
    // MARK: Transcript Section
    // -------------------------------------------------------------------------

    private var transcriptSection: some View {
        let visible = Array(vm.transcript.suffix(3))
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .center, spacing: 6) {
                ForEach(visible) { seg in
                    Text(seg.text)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(seg.isPartial ? Color.secondary : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(seg.isPartial
                                      ? Color(.systemGray5)
                                      : Color(.systemGray6))
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                }
            }
            .frame(maxWidth: .infinity)
            .animation(
                reduceMotion ? nil : Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75)),
                value: vm.transcript.count
            )
        }
        .frame(height: visible.isEmpty ? 0 : min(CGFloat(visible.count) * 40, 120))
    }

    // -------------------------------------------------------------------------
    // MARK: Response Text
    // -------------------------------------------------------------------------

    private var currentResponseText: some View {
        Text(vm.currentResponse)
            .font(.custom("OpenSans-Regular", size: 15))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: vm.currentResponse
            )
    }

    // -------------------------------------------------------------------------
    // MARK: Bottom Bar
    // -------------------------------------------------------------------------

    private var bottomBar: some View {
        VStack(spacing: 14) {
            actionButtons
            modeSelectorRow
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch vm.voiceState {
        case .idle:
            // Full-width black "Start" button
            Button {
                Task { await vm.startSession(mode: selectedMode) }
            } label: {
                Text("Start")
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black)
                    )
            }
            .disabled(!BereanVoiceFeatureFlags.bereanVoiceEnabled)

        default:
            // End (black) + Pause (glass) side by side
            HStack(spacing: 12) {
                Button {
                    Task { await vm.stopSession() }
                } label: {
                    Text("End")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black)
                        )
                }

                Button {
                    // Pause: stop the current session; a dedicated pause
                    // state will be wired in a future iteration.
                    Task { await vm.stopSession() }
                } label: {
                    Text("Pause")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                                )
                        )
                }
            }
        }
    }

    private var modeSelectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BereanVoiceMode.allCases, id: \.rawValue) { m in
                    BereanVoiceModeChip(
                        mode: m,
                        isSelected: selectedMode == m
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            selectedMode = m
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Coming Soon Overlay
    // -------------------------------------------------------------------------

    private var comingSoonOverlay: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(0.92)
                .ignoresSafeArea()
                .blur(radius: 2)

            VStack(spacing: 16) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)

                Text("Berean Live Voice")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)

                Text("Coming Soon")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)

                Button {
                    dismiss()
                } label: {
                    Text("Got it")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.black))
                }
                .padding(.top, 8)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 24, y: 8)
            )
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - VoiceSettingsSheet

private struct VoiceSettingsSheet: View {
    @Binding var selectedVoiceIndex: Int
    @Binding var selectedPersonality: Int
    @Binding var speechSpeed: Double
    @Environment(\.dismiss) private var dismiss

    private let voices = [
        ("Aria", "Warm & Clear"),
        ("Samuel", "Resonant Male"),
        ("Grace", "Gentle Female"),
    ]
    private let personalities = [
        ("plus", "Custom"),
        ("face.smiling", "Assistant"),
        ("cross", "Pastoral"),
        ("heart", "Counselor"),
        ("book", "Teacher"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    voiceSection
                    Divider()
                    personalitySection
                    Divider()
                    speedSection
                }
                .padding(20)
            }
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.ultraThinMaterial)
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(voices.indices, id: \.self) { i in
                        let isSelected = selectedVoiceIndex == i
                        Button { selectedVoiceIndex = i } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(voices[i].0)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                Text(voices[i].1)
                                    .font(.caption)
                                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(Color.secondary))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(isSelected ? AnyShapeStyle(AmenTheme.Colors.amenPurple) : AnyShapeStyle(.ultraThinMaterial))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.white.opacity(isSelected ? 0 : 0.12))
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6)
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                    }
                }
            }
        }
    }

    private var personalitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Personality")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(personalities.indices, id: \.self) { i in
                        let isSelected = selectedPersonality == i
                        Button { selectedPersonality = i } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(isSelected ? AnyShapeStyle(AmenTheme.Colors.amenPurple) : AnyShapeStyle(Material.ultraThinMaterial))
                                        .overlay {
                                            Circle()
                                                .fill(Color.white.opacity(isSelected ? 0 : 0.12))
                                        }
                                        .overlay {
                                            Circle()
                                                .strokeBorder(Color.black.opacity(isSelected ? 0.16 : 0.08),
                                                              lineWidth: isSelected ? 0.0 : 0.6)
                                        }
                                        .frame(width: 60, height: 60)
                                        .shadow(color: isSelected
                                                    ? AmenTheme.Colors.amenPurple.opacity(0.3)
                                                    : Color.black.opacity(0.06),
                                                radius: 8, y: 4)
                                    Image(systemName: personalities[i].0)
                                        .font(.system(size: i == 0 ? 18 : 20, weight: .medium))
                                        .foregroundStyle(isSelected ? .white : .primary)
                                }
                                Text(personalities[i].1)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                    }
                }
            }
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Speed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text("\(speechSpeed, specifier: "%.1f")×")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36)
                Slider(value: $speechSpeed, in: 0.5...2.0, step: 0.1)
                    .tint(AmenTheme.Colors.amenPurple)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6)
                    }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Live Voice — Coming Soon") {
    BereanLiveVoiceView(mode: .conversation)
}

#Preview("Live Voice — Prayer Mode") {
    BereanLiveVoiceView(mode: .prayer)
}
#endif
