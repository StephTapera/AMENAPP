// BereanVoiceCompanionView.swift
// AMEN App — Context-Aware Voice Bible Companion (Agent 5)
//
// Voice-first Berean mode: speak -> transcript -> guarded proxy -> answer.
// RESTRAINT RULES (hard-wired):
//   - Short responses by default (maxTokens: 256)
//   - Always distinguish scripture vs. interpretation vs. encouragement
//   - Never pretend to be a pastor
//   - No fake certainty on disputed theology
//   - Nothing saves without user confirmation

import SwiftUI
import FirebaseFunctions

// MARK: - Companion Phase

private enum CompanionPhase {
    case idle
    case listening
    case thinking
    case speaking(BereanVoiceTurn)
    case error(String)
}

// MARK: - Main View

struct BereanVoiceCompanionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let onSaveToChurchNotes: ((String) -> Void)?
    let onSaveToJournal: ((String) -> Void)?

    @StateObject private var engine = VoicePrayerAudioEngine()
    @StateObject private var transcription = BereanTranscriptionService.shared
    @StateObject private var sessions = BereanVoiceStudySessionStore.shared

    @State private var phase: CompanionPhase = .idle
    @State private var showSelah = false
    @State private var showSaveSheet = false
    @State private var lastAnswer = ""
    @State private var pulseActive = false

    private let functions = Functions.functions()

    var body: some View {
        guard AMENFeatureFlags.shared.bereanVoiceCompanionEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    conversationArea
                    bottomControls
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await sessions.startOrResumeSession()
        }
        .onDisappear {
            engine.cancelRecording()
        }
        .sheet(isPresented: $showSelah) {
            BereanSelahModeView(onSaveToJournal: onSaveToJournal)
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveConfirmSheet(
                text: lastAnswer,
                onSaveToJournal: {
                    onSaveToJournal?(lastAnswer)
                    showSaveSheet = false
                },
                onSaveToChurchNotes: {
                    onSaveToChurchNotes?(lastAnswer)
                    showSaveSheet = false
                },
                onCancel: { showSaveSheet = false }
            )
        })
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(reduceTransparency
                            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                            : AnyShapeStyle(.thinMaterial))
                    )
            }
            .accessibilityLabel("Dismiss voice companion")

            Spacer()

            VStack(spacing: 2) {
                Text("Berean")
                    .font(.custom("OpenSans-Bold", size: 17))
                if let ref = sessions.currentSession?.lastScriptureRef {
                    Text("Studying \(ref)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                showSelah = true
            } label: {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(reduceTransparency
                            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                            : AnyShapeStyle(.thinMaterial))
                    )
            }
            .accessibilityLabel("Open Selah quiet mode")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Conversation Area

    private var conversationArea: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let session = sessions.currentSession {
                    ForEach(session.turns) { turn in
                        TurnBubble(turn: turn)
                    }
                }

                switch phase {
                case .idle:
                    EmptyView()
                case .listening:
                    listeningIndicator
                case .thinking:
                    thinkingIndicator
                case .speaking(let turn):
                    TurnBubble(turn: turn)
                case .error(let msg):
                    errorBubble(msg)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 20) {
                Button {
                    switch phase {
                    case .idle:
                        Task { await beginListening() }
                    case .listening:
                        Task { await finishListening() }
                    default: break
                    }
                } label: {
                    ZStack {
                        if case .listening = phase {
                            Circle()
                                .fill(.red.opacity(0.15))
                                .frame(width: 72, height: 72)
                                .scaleEffect(pulseActive ? 1.15 : 1.0)
                                .animation(
                                    reduceMotion ? nil
                                        : Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                    value: pulseActive
                                )
                        }

                        Circle()
                            .fill(phaseColor)
                            .frame(width: 60, height: 60)
                            .shadow(color: phaseColor.opacity(0.35), radius: 8, x: 0, y: 4)

                        Image(systemName: phaseIcon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isPhaseBlocking)
                .accessibilityLabel(accessibilityLabel)
                .onAppear { pulseActive = true }
            }
            .frame(maxWidth: .infinity)

            if !lastAnswer.isEmpty {
                Button {
                    showSaveSheet = true
                } label: {
                    Label("Save this answer", systemImage: "square.and.arrow.down")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    // MARK: - Sub-views

    private var listeningIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 14))
                .foregroundStyle(.red)
            Text("Listening…")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Group {
            if reduceTransparency {
                Capsule().fill(AmenTheme.Colors.backgroundElevated)
            } else {
                Capsule().fill(.thinMaterial)
            }
        })
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 4)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.75)
            Text("Berean is thinking…")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Berean response")
        }
        .padding(10)
        .background(Group {
            if reduceTransparency {
                Capsule().fill(AmenTheme.Colors.backgroundElevated)
            } else {
                Capsule().fill(.thinMaterial)
            }
        })
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBubble(_ msg: String) -> some View {
        Text(msg)
            .font(.custom("OpenSans-Regular", size: 14))
            .foregroundStyle(.red)
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Phase Helpers

    private var phaseColor: Color {
        switch phase {
        case .idle:      return Color(red: 0.56, green: 0.40, blue: 0.85)
        case .listening: return .red
        case .thinking:  return .orange
        default:         return Color(uiColor: .systemGray3)
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .idle:      return "mic.fill"
        case .listening: return "stop.fill"
        case .thinking:  return "ellipsis"
        default:         return "mic.fill"
        }
    }

    private var isPhaseBlocking: Bool {
        if case .thinking = phase { return true }
        return false
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle:      return "Ask Berean by voice"
        case .listening: return "Finish speaking"
        default:         return "Ask Berean by voice"
        }
    }

    // MARK: - Voice Flow

    private func beginListening() async {
        guard AmenAIConsentStore.shared.hasConsent(for: .bereanQuickAnswer) else {
            phase = .error("Microphone and AI consent is required to use the voice companion. Enable it in Settings.")
            return
        }
        phase = .listening
        pulseActive = true
        await engine.requestPermissionAndStart()
    }

    private func finishListening() async {
        engine.stopRecording()
        pulseActive = false
        guard let url = engine.recordedFileURL else {
            phase = .idle
            return
        }

        phase = .thinking

        do {
            // 1. On-device transcription (privacy-first)
            let transcript = try await BereanTranscriptionService.shared.transcribe(audioURL: url)
            guard !transcript.isEmpty else {
                phase = .idle
                return
            }

            let userTurn = BereanVoiceTurn(
                role: .user,
                text: transcript.text,
                timestamp: Date(),
                scriptureRefs: [],
                label: "user"
            )
            sessions.addTurn(userTurn)

            // 2. Route to Berean via the guarded proxy
            let context = sessions.contextSummary
            let fullPrompt = context.isEmpty
                ? transcript.text
                : "Context: \(context)\n\nQuestion: \(transcript.text)"

            // Voice companion uses bibleQA with short max tokens (restraint)
            let request = OrchestratorRequest(
                taskType: .bibleQA,
                userPrompt: fullPrompt,
                maxTokens: 256   // short responses by default in voice mode
            )
            let response = try await BereanOrchestrator.shared.route(request)

            // 3. Parse content label from citations (first citation used as label hint)
            let contentLabel = response.citations.first.flatMap { hint -> String? in
                if hint.contains("interpretation") { return "interpretation" }
                if hint.contains("encouragement")  { return "encouragement" }
                return "scripture"
            } ?? "scripture"

            let bereanTurn = BereanVoiceTurn(
                role: .berean,
                text: response.content,
                timestamp: Date(),
                scriptureRefs: response.citations,
                label: contentLabel
            )
            sessions.addTurn(bereanTurn)
            lastAnswer = response.content
            phase = .speaking(bereanTurn)

            // Return to idle so the user can ask again
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if case .speaking = phase { phase = .idle }

        } catch {
            phase = .error("Berean couldn't answer right now. Try again.")
        }
    }
}

// MARK: - Turn Bubble

private struct TurnBubble: View {
    let turn: BereanVoiceTurn

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if turn.role == .berean {
                Image(systemName: "brain")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.56, green: 0.40, blue: 0.85))
                    .padding(.top, 2)
            }

            VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 4) {
                Text(turn.text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(turn.role == .user ? .white : .primary)
                    .padding(12)
                    .background(
                        turn.role == .user
                            ? AnyShapeStyle(Color(red: 0.56, green: 0.40, blue: 0.85))
                            : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .fixedSize(horizontal: false, vertical: true)

                if turn.role == .berean && !turn.label.isEmpty && turn.label != "user" {
                    Text(turn.label.capitalized)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
            }
            .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)

            if turn.role == .user {
                Image(systemName: "person.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Save Confirm Sheet

private struct SaveConfirmSheet: View {
    let text: String
    let onSaveToJournal: () -> Void
    let onSaveToChurchNotes: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color(uiColor: .systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            Text("Save This Answer")
                .font(.custom("OpenSans-Bold", size: 20))

            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Button(action: onSaveToJournal) {
                    Label("Save to Journal", systemImage: "book.closed.fill")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.56, green: 0.40, blue: 0.85), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button(action: onSaveToChurchNotes) {
                    Label("Add to Church Notes", systemImage: "note.text.badge.plus")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.16, green: 0.40, blue: 0.76), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(24)
    }
}
