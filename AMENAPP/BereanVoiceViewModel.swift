// BereanVoiceViewModel.swift
// AMENAPP
//
// Berean Live Voice — Main orchestrating ViewModel
//
// Drives BereanVoiceView. Coordinates VoiceStreamManager, BereanVoiceSessionService,
// and Firebase Cloud Functions (whisperProxy, bereanVoiceProxy, ttsProxy).
// No existing files are modified.

import Foundation
import SwiftUI
import FirebaseFunctions
import FirebaseAuth

// MARK: - BereanVoiceViewModel

@MainActor
final class BereanVoiceViewModel: ObservableObject {

    // -------------------------------------------------------------------------
    // MARK: Published State
    // -------------------------------------------------------------------------

    @Published private(set) var voiceState:        BereanVoiceState      = .idle
    @Published private(set) var mode:              BereanVoiceMode       = .conversation
    @Published private(set) var transcript:        [BereanTranscriptSegment] = []
    @Published private(set) var currentResponse:   String                = ""
    @Published private(set) var isStreaming:        Bool                  = false
    @Published private(set) var emotionalState:    BereanEmotionalState  = .neutral
    @Published var errorMessage:                   String?               = nil
    @Published private(set) var microphoneLevel:   Float                 = 0
    @Published private(set) var acknowledgmentText: String               = ""

    // -------------------------------------------------------------------------
    // MARK: Private Dependencies
    // -------------------------------------------------------------------------

    private let streamManager   = VoiceStreamManager()
    private let sessionService  = BereanVoiceSessionService.shared
    private let functions       = Functions.functions()

    private var currentSession:  BereanVoiceSession?
    private var responseTask:    Task<Void, Never>?
    private var partialTranscript: String = ""

    // -------------------------------------------------------------------------
    // MARK: Session Lifecycle
    // -------------------------------------------------------------------------

    /// Start a new Live Voice session for the given mode.
    func startSession(mode: BereanVoiceMode) async {
        // Feature-flag gate
        guard BereanVoiceFeatureFlags.bereanVoiceEnabled else {
            dlog("BereanVoiceViewModel: voice disabled by feature flag")
            return
        }

        // Microphone permission check
        let status = AVAudioSession.sharedInstance().recordPermission
        guard status == .granted else {
            if status == .undetermined {
                AVAudioSession.sharedInstance().requestRecordPermission { _ in }
            }
            errorMessage = BereanVoiceError.micPermissionDenied.localizedDescription
            voiceState = .error
            return
        }

        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("BereanVoiceViewModel: no authenticated user")
            return
        }

        self.mode = mode
        let session = await sessionService.startSession(mode: mode, userId: uid)
        currentSession = session

        // Configure and start the audio stream
        await streamManager.configure(
            onAudioChunk: { [weak self] chunk in
                Task { await self?.handleAudioChunk(chunk) }
            },
            onBargein: { [weak self] in
                Task { await MainActor.run { self?.handleBargein() } }
            }
        )

        do {
            try await streamManager.startRecording()
            voiceState = .listening
            dlog("BereanVoiceViewModel: session started \(session.id) mode=\(mode.rawValue)")
        } catch {
            errorMessage = error.localizedDescription
            voiceState = .error
        }
    }

    /// End the current voice session gracefully.
    func stopSession() async {
        await streamManager.stopRecording()
        if let session = currentSession {
            await sessionService.endSession(session)
        }
        currentSession = nil
        voiceState = .idle
        transcript = []
        currentResponse = ""
        partialTranscript = ""
        dlog("BereanVoiceViewModel: session stopped")
    }

    /// Pause the microphone without ending the session.
    func pauseSession() async {
        guard voiceState == .listening || voiceState == .speaking || voiceState == .thinking else { return }
        responseTask?.cancel()
        responseTask = nil
        await streamManager.stopRecording()
        voiceState = .paused
        if let session = currentSession {
            await sessionService.updateEmotionalState(emotionalState, sessionId: session.id)
            let event = BereanVoiceEvent(sessionId: session.id, type: .pause)
            await sessionService.logEvent(event)
        }
        dlog("BereanVoiceViewModel: session paused")
    }

    /// Resume listening after a pause.
    func resumeSession() async {
        guard voiceState == .paused, currentSession != nil else { return }
        do {
            try await streamManager.startRecording()
            voiceState = .listening
            dlog("BereanVoiceViewModel: session resumed")
        } catch {
            errorMessage = error.localizedDescription
            voiceState = .error
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Barge-in
    // -------------------------------------------------------------------------

    /// Called by VoiceStreamManager when the user speaks while Berean is speaking.
    func handleBargein() {
        guard BereanVoiceFeatureFlags.bereanVoiceInterruptEnabled else { return }

        // Cancel any in-flight response
        responseTask?.cancel()
        responseTask = nil

        Task { await streamManager.stopPlayback() }

        voiceState = .interrupted
        partialTranscript = ""
        isStreaming = false

        // Log the interruption
        if let session = currentSession {
            Task {
                await sessionService.recordInterruption(sessionId: session.id)
                let event = BereanVoiceEvent(
                    sessionId: session.id,
                    type: .bargein
                )
                await sessionService.logEvent(event)
            }
        }

        // Brief "interrupted" state, then back to listening
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
            voiceState = .listening
        }

        showAcknowledgment("I'm listening…", duration: 1.5)
        dlog("BereanVoiceViewModel: barge-in handled")
    }

    // -------------------------------------------------------------------------
    // MARK: Audio Chunk Processing (ASR)
    // -------------------------------------------------------------------------

    /// Forward a captured audio chunk to the Whisper proxy Cloud Function.
    func handleAudioChunk(_ chunk: BereanAudioChunk) async {
        guard voiceState == .listening else { return }

        // Encode audio as base64 for the callable
        let base64Audio = chunk.data.base64EncodedString()

        do {
            let callable = functions.httpsCallable("whisperProxy")
            let result = try await callable.call([
                "audio":      base64Audio,
                "isPartial":  true,
                "sampleRate": 16000,
                "sessionId":  currentSession?.id ?? ""
            ])

            guard let data = result.data as? [String: Any] else { return }

            if let partial = data["partialTranscript"] as? String, !partial.isEmpty {
                partialTranscript = partial
                microphoneLevel = (data["inputLevel"] as? Float) ?? 0

                // Update transcript with isPartial segment
                let seg = BereanTranscriptSegment(
                    text: partial,
                    isPartial: true,
                    confidence: (data["confidence"] as? Double) ?? 0.8
                )
                // Replace any existing partial segment
                transcript.removeAll { $0.isPartial }
                transcript.append(seg)
            }

            if let finalText = data["finalTranscript"] as? String, !finalText.isEmpty {
                await handleFinalUtterance(text: finalText)
            }
        } catch {
            dlog("BereanVoiceViewModel: whisperProxy error — \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Final Utterance
    // -------------------------------------------------------------------------

    /// Process a confirmed, final transcription and trigger a Berean response.
    func handleFinalUtterance(text: String) async {
        // Remove partial, append final
        transcript.removeAll { $0.isPartial }
        let finalSeg = BereanTranscriptSegment(text: text, isPartial: false)
        transcript.append(finalSeg)
        partialTranscript = ""

        // Persist transcript chunk
        if let session = currentSession {
            await sessionService.appendTranscript(text, sessionId: session.id)
        }

        // Detect and update emotional state
        detectEmotionalState(from: text)

        // Choose response strategy
        let strategy = resolveResponseStrategy(for: text)
        dlog("BereanVoiceViewModel: final utterance strategy=\(strategy.rawValue)")

        switch strategy {
        case .instantAcknowledgment:
            let ack = makeAcknowledgmentText(for: emotionalState)
            showAcknowledgment(ack, duration: 1.2)
            if let session = currentSession {
                let event = BereanVoiceEvent(
                    sessionId: session.id,
                    type: .acknowledgment,
                    payload: ["text": ack]
                )
                Task { await sessionService.logEvent(event) }
            }
            // Small pause so the ack feels natural before the full response begins
            try? await Task.sleep(nanoseconds: 400_000_000)
            await streamBereanResponse(userText: text)

        case .partialStream:
            await streamBereanResponse(userText: text)

        case .clarifyFirst:
            let clarify = "Could you tell me a bit more about that?"
            currentResponse = clarify
            await streamBereanResponse(userText: text)

        case .delayedDeepResponse:
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s contemplative pause
            await streamBereanResponse(userText: text)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Response Streaming
    // -------------------------------------------------------------------------

    /// Call `bereanVoiceProxy`, stream text chunks, convert each to speech via `ttsProxy`.
    func streamBereanResponse(userText: String) async {
        guard let session = currentSession else { return }

        voiceState = .thinking
        currentResponse = ""
        isStreaming = true

        sessionService.markResponseStart(sessionId: session.id)

        // Build last-5 transcript context
        let recentTranscript = transcript
            .suffix(5)
            .map { $0.text }

        let payload: [String: Any] = [
            "userText":          userText,
            "mode":              mode.rawValue,
            "emotionalState":    emotionalState.rawValue,
            "sessionId":         session.id,
            "transcriptHistory": recentTranscript
        ]

        responseTask = Task {
            do {
                let callable = functions.httpsCallable("bereanVoiceProxy")
                let result   = try await callable.call(payload)

                sessionService.markResponseEnd(sessionId: session.id)

                guard let data = result.data as? [String: Any] else { return }
                let responseText = (data["text"] as? String) ?? ""

                // Log response event
                let event = BereanVoiceEvent(
                    sessionId: session.id,
                    type: .response,
                    payload: ["preview": String(responseText.prefix(80))]
                )
                await sessionService.logEvent(event)

                // Typewriter-style streaming of text
                voiceState = .speaking

                // Split into sentence-level chunks for natural TTS pacing
                let sentences = splitIntoSpeechChunks(responseText)
                for sentence in sentences {
                    guard !Task.isCancelled else { break }
                    await appendToCurrentResponse(sentence)

                    // TTS for each sentence chunk
                    await speakChunk(sentence, emotionalState: emotionalState)
                }

                if !Task.isCancelled {
                    isStreaming = false
                    voiceState = .listening
                    currentResponse = responseText
                }

            } catch {
                if !Task.isCancelled {
                    dlog("BereanVoiceViewModel: streamBereanResponse error — \(error)")
                    voiceState = .error
                    errorMessage = BereanVoiceError.networkError(error.localizedDescription).localizedDescription
                    isStreaming = false
                }
            }
        }

        await responseTask?.value
    }

    // -------------------------------------------------------------------------
    // MARK: TTS
    // -------------------------------------------------------------------------

    /// Convert a text chunk to speech via the `ttsProxy` Cloud Function and play it.
    private func speakChunk(_ text: String, emotionalState: BereanEmotionalState) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let callable = functions.httpsCallable("ttsProxy")
            let result   = try await callable.call([
                "text":           text,
                "emotionalState": emotionalState.rawValue
            ])

            guard let data       = result.data as? [String: Any],
                  let base64Audio = data["audio"] as? String,
                  let audioData   = Data(base64Encoded: base64Audio) else {
                dlog("BereanVoiceViewModel: ttsProxy returned no audio data")
                return
            }

            await streamManager.playAudioChunk(audioData)

        } catch {
            dlog("BereanVoiceViewModel: ttsProxy error — \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Emotional State Detection
    // -------------------------------------------------------------------------

    /// Simple keyword heuristic — sets `emotionalState` and logs a state-change event.
    func detectEmotionalState(from text: String) {
        let lower = text.lowercased()

        let distressKeywords = ["grief", "lost", "afraid", "struggling", "depressed",
                                 "hopeless", "broken", "hurt", "alone", "anxious",
                                 "worried", "scared", "pain", "suffer"]
        let joyKeywords      = ["grateful", "blessed", "thankful", "joy", "joyful",
                                 "amazing", "wonderful", "praise", "hallelujah",
                                 "excited", "happy", "celebrate"]
        let seekingKeywords  = ["how", "why", "confused", "wondering", "understand",
                                 "explain", "what does", "what is", "help me"]

        let previousState = emotionalState
        var detected: BereanEmotionalState = .neutral

        if distressKeywords.contains(where: { lower.contains($0) }) {
            detected = .distressed
        } else if joyKeywords.contains(where: { lower.contains($0) }) {
            detected = .joyful
        } else if seekingKeywords.contains(where: { lower.contains($0) }) {
            detected = .seeking
        }

        emotionalState = detected

        // Persist and log only on change
        if detected != previousState, let session = currentSession {
            Task {
                await sessionService.updateEmotionalState(detected, sessionId: session.id)
                let event = BereanVoiceEvent(
                    sessionId: session.id,
                    type: .response,
                    payload: [
                        "previousState": previousState.rawValue,
                        "newState":      detected.rawValue
                    ]
                )
                await sessionService.logEvent(event)
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Helpers
    // -------------------------------------------------------------------------

    /// Determine the best response strategy based on text length and emotional register.
    private func resolveResponseStrategy(for text: String) -> BereanResponseStrategy {
        let wordCount = text.split(separator: " ").count

        if emotionalState == .distressed {
            return .instantAcknowledgment
        }
        if wordCount < 5 {
            return .clarifyFirst
        }
        if wordCount > 40 || emotionalState == .seeking {
            return .delayedDeepResponse
        }
        return .partialStream
    }

    /// Acknowledgment phrase matched to the user's emotional state.
    private func makeAcknowledgmentText(for state: BereanEmotionalState) -> String {
        switch state {
        case .neutral:    return "Got it…"
        case .distressed: return "I'm here with you…"
        case .seeking:    return "Let me think about that…"
        case .joyful:     return "That's wonderful…"
        }
    }

    /// Briefly surface an acknowledgment string then fade it out.
    private func showAcknowledgment(_ text: String, duration: Double) {
        acknowledgmentText = text
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if acknowledgmentText == text {
                withAnimation(Motion.adaptive(.easeOut(duration: 0.4))) {
                    acknowledgmentText = ""
                }
            }
        }
    }

    /// Append a sentence to `currentResponse` with a brief per-word typewriter delay.
    private func appendToCurrentResponse(_ sentence: String) async {
        let words = sentence.split(separator: " ", omittingEmptySubsequences: false)
        for word in words {
            guard !Task.isCancelled else { return }
            currentResponse += (currentResponse.isEmpty ? "" : " ") + word
            // 40 ms per word for a natural reading pace
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    /// Split a long response into sentence-level chunks for TTS pipelining.
    private func splitIntoSpeechChunks(_ text: String) -> [String] {
        // Split on sentence boundaries; keep chunks non-empty.
        let delimiters = CharacterSet(charactersIn: ".!?")
        let parts = text.components(separatedBy: delimiters)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [text] : parts
    }
}

// MARK: - AVFoundation Import for permission check
import AVFoundation
