// BereanTranslationView.swift
// AMEN App — Berean live translation session view
//
// Starts a sermonTranslation realtime session and streams translated chunks.
// Gated by bereanTranslationEnabled feature flag.

import SwiftUI

struct BereanTranslationView: View {
    var sourceLanguage: BereanSupportedLanguage = .english

    @StateObject private var manager = BereanRealtimeSessionManager.shared
    @StateObject private var transcriptService = BereanLiveTranscriptService()
    @StateObject private var coordinator = BereanTranslationCoordinator()
    @ObservedObject private var flags = AMENFeatureFlags.shared

    @State private var selectedLanguage: BereanSupportedLanguage = .english
    @State private var isStarted = false
    @State private var translationChunks: [BereanTranslationResult] = []
    @State private var errorMessage: String?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if !flags.bereanTranslationEnabled {
            ContentUnavailableView("Translation not available", systemImage: "globe.slash")
        } else {
            content
        }
    }

    // MARK: - Main content

    private var content: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Language picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Translate to")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Target language", selection: $selectedLanguage) {
                        ForEach(BereanSupportedLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isStarted)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

                Divider().padding(.horizontal, 18)

                // Translation output
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if translationChunks.isEmpty && isStarted {
                                HStack {
                                    Spacer()
                                    Text("Listening…")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.top, 32)
                            }
                            ForEach(Array(translationChunks.enumerated()), id: \.offset) { index, chunk in
                                translationRow(chunk, index: index)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }
                    .onChange(of: translationChunks.count) { _, _ in
                        if let last = translationChunks.indices.last {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                // Controls
                VStack(spacing: 12) {
                    if manager.isConnecting {
                        ProgressView("Connecting…")
                            .font(.subheadline)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    startStopButton
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .navigationTitle("Live Translation")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { coordinator.preferredLanguage = sourceLanguage }
        }
    }

    // MARK: - Translation row

    private func translationRow(_ chunk: BereanTranslationResult, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(chunk.translatedText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(chunk.targetLanguage.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    if chunk.confidence > 0 {
                        Text(String(format: "%.0f%%", chunk.confidence * 100))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(reduceTransparency
                      ? Color(.secondarySystemBackground)
                      : Color(.secondarySystemBackground).opacity(0.85))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chunk.targetLanguage.displayName): \(chunk.translatedText)")
    }

    // MARK: - Start / Stop button

    private var startStopButton: some View {
        Button(action: toggleSession) {
            Label(
                isStarted ? "Stop Translation" : "Start Translation",
                systemImage: isStarted ? "stop.fill" : "play.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Capsule().fill(isStarted ? Color.red : Color.accentColor))
        }
        .buttonStyle(.plain)
        .disabled(manager.isConnecting)
        .accessibilityLabel(isStarted ? "Stop live translation" : "Start live translation")
    }

    // MARK: - Toggle session

    private func toggleSession() {
        if isStarted {
            Task {
                if let sessionId = manager.currentSession?.id {
                    await manager.pause(sessionId: sessionId)
                }
                transcriptService.stop()
                isStarted = false
            }
        } else {
            errorMessage = nil
            Task {
                do {
                    let secret = try await manager.createSession(
                        type: .sermonTranslation,
                        sourceLanguage: sourceLanguage,
                        targetLanguages: [selectedLanguage]
                    )
                    transcriptService.start(sessionId: secret.sessionId, language: selectedLanguage)
                    isStarted = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
