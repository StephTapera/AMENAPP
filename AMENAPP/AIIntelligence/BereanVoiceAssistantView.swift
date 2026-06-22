// BereanVoiceAssistantView.swift
// AMEN App — Berean voice assistant view
//
// Tap-to-talk interface for the Berean AI voice assistant.
// Gated by bereanVoiceAssistantEnabled feature flag.

import SwiftUI

struct BereanVoiceAssistantView: View {
    @StateObject private var manager = BereanRealtimeSessionManager.shared
    @StateObject private var transcriptService = BereanLiveTranscriptService()
    @ObservedObject private var flags = AMENFeatureFlags.shared

    @State private var isListening = false
    @State private var lastTranscript = ""
    @State private var lastResponse = ""
    @State private var errorMessage: String?
    @State private var showTextFallbackAlert = false
    @State private var pulseScale: CGFloat = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if !flags.bereanVoiceAssistantEnabled {
            ContentUnavailableView("Voice Assistant not available", systemImage: "mic.slash")
        } else {
            content
        }
    }

    // MARK: - Main content

    private var content: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Mic orb
                micOrb

                // Status label
                Text(statusLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isListening)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Transcript + response cards
                VStack(spacing: 12) {
                    if !lastTranscript.isEmpty {
                        transcriptCard
                    }
                    if !lastResponse.isEmpty {
                        responseCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .navigationTitle("Voice Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear { stopSession() }
        .alert("Voice Not Available", isPresented: $showTextFallbackAlert) {
            Button("Use Text Chat") { /* user can navigate to BereanChatView manually */ }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Real-time voice is unavailable right now. You can continue with text chat instead.")
        }
    }

    // MARK: - Mic orb

    private var micOrb: some View {
        Button(action: toggleListening) {
            ZStack {
                // Pulse ring (only when listening)
                if isListening {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 96, height: 96)
                        .scaleEffect(pulseScale)
                }

                Circle()
                    .fill(isListening ? Color.accentColor : Color(.secondarySystemBackground))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isListening ? Color.accentColor : Color.black.opacity(0.08),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(
                        color: isListening ? Color.accentColor.opacity(0.30) : Color.black.opacity(0.10),
                        radius: 16,
                        y: 4
                    )

                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isListening ? .white : .primary)
            }
        }
        .buttonStyle(.plain)
        .disabled(manager.isConnecting)
        .accessibilityLabel(isListening ? "End Session" : "Start listening")
        .accessibilityHint(isListening ? "Double tap to end the voice assistant session" : "Double tap to start the voice assistant")
        .onChange(of: isListening) { _, newValue in
            guard !reduceMotion else { return }
            if newValue {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.28
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    pulseScale = 1.0
                }
            }
        }
        .onChange(of: transcriptService.captions) { _, chunks in
            if let latest = chunks.last {
                lastTranscript = latest.text
            }
        }
    }

    // MARK: - Transcript card

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("You said", systemImage: "person.wave.2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(lastTranscript)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(reduceTransparency
                      ? Color(.secondarySystemBackground)
                      : Color(.secondarySystemBackground).opacity(0.85))
        )
        .accessibilityLabel("Your speech: \(lastTranscript)")
    }

    // MARK: - Response card

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Berean", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(lastResponse)
                .font(.body)
                .italic()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(reduceTransparency ? 0.10 : 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.7)
                )
        )
        .accessibilityLabel("Berean response: \(lastResponse)")
    }

    // MARK: - Status label

    private var statusLabel: String {
        if manager.isConnecting { return "Connecting…" }
        if isListening { return "Listening…" }
        return "Tap to speak"
    }

    // MARK: - Session control

    private func toggleListening() {
        if isListening {
            stopSession()
        } else {
            startSession()
        }
    }

    private func startSession() {
        errorMessage = nil
        Task {
            do {
                let secret = try await manager.createSession(type: .voiceAssistant)
                transcriptService.start(sessionId: secret.sessionId, language: .english)
                isListening = true
            } catch {
                errorMessage = error.localizedDescription
                showTextFallbackAlert = true
            }
        }
    }

    private func stopSession() {
        guard isListening else { return }
        Task {
            if let sessionId = manager.currentSession?.id {
                await manager.pause(sessionId: sessionId)
            }
            transcriptService.stop()
            isListening = false
        }
    }
}
