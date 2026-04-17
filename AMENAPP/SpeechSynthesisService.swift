// SpeechSynthesisService.swift
// AMEN App — Accessibility Intelligence Layer (Phase 3)
//
// AVSpeechSynthesizer wrapper for "Listen to post" feature.
// Queue management, sentence-range callbacks, play/pause/stop/skip/setRate.
// Fully on-device — zero API cost.
//
// Published state: isPlaying, currentItemId, currentSentenceRange, progress, playbackRate.

import Foundation
import AVFoundation

@MainActor
final class SpeechSynthesisService: NSObject, ObservableObject {

    static let shared = SpeechSynthesisService()

    // MARK: - Published State

    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentItemId: String?
    @Published private(set) var currentItemTitle: String?
    @Published private(set) var currentSentenceRange: Range<String.Index>?
    @Published private(set) var progress: Double = 0.0
    @Published var playbackRate: Float = 1.0

    // MARK: - Queue

    private var queue: [SpeechQueueItem] = []
    private var currentIndex = 0

    // MARK: - AVSpeech

    private let synthesizer = AVSpeechSynthesizer()
    private var currentText: String = ""
    private var currentUtterance: AVSpeechUtterance?

    // MARK: - Init

    private override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - Public API

    /// Play a single item immediately (clears queue)
    func play(text: String, id: String, title: String? = nil, language: String? = nil) {
        let item = SpeechQueueItem(
            id: id,
            text: text,
            title: title,
            language: language
        )
        queue = [item]
        currentIndex = 0
        startSpeaking(item: item)
    }

    /// Add an item to the end of the queue
    func enqueue(text: String, id: String, title: String? = nil, language: String? = nil) {
        let item = SpeechQueueItem(
            id: id,
            text: text,
            title: title,
            language: language
        )
        queue.append(item)

        // Start playing if nothing is currently playing
        if !isPlaying && !isPaused {
            currentIndex = queue.count - 1
            startSpeaking(item: item)
        }
    }

    func pause() {
        guard isPlaying else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPlaying = false
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPlaying = true
        isPaused = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        resetState()
    }

    func skip() {
        synthesizer.stopSpeaking(at: .immediate)
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            startSpeaking(item: queue[currentIndex])
        } else {
            resetState()
        }
    }

    func updateRate(_ rate: Float) {
        playbackRate = max(0.5, min(2.0, rate))
        // Rate change takes effect on next utterance
    }

    // MARK: - Private

    private func startSpeaking(item: SpeechQueueItem) {
        synthesizer.stopSpeaking(at: .immediate)

        currentText = item.text
        currentItemId = item.id
        currentItemTitle = item.title ?? "Post"
        currentSentenceRange = nil
        progress = 0.0

        let utterance = AVSpeechUtterance(string: item.text)
        utterance.rate = playbackRate * AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.3

        // Set voice based on language
        let voiceLang = item.language ?? Locale.current.language.languageCode?.identifier ?? "en"
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLang)

        currentUtterance = utterance
        isPlaying = true
        isPaused = false

        synthesizer.speak(utterance)
    }

    private func resetState() {
        isPlaying = false
        isPaused = false
        currentItemId = nil
        currentItemTitle = nil
        currentSentenceRange = nil
        progress = 0.0
        queue.removeAll()
        currentIndex = 0
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        } catch {
            dlog("[SpeechSynthesis] Audio session config failed: \(error)")
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesisService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let text = self.currentText
            guard let range = Range(characterRange, in: text) else { return }
            self.currentSentenceRange = range
            self.progress = Double(characterRange.location + characterRange.length) / Double(text.count)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Move to next item in queue
            if self.currentIndex + 1 < self.queue.count {
                self.currentIndex += 1
                self.startSpeaking(item: self.queue[self.currentIndex])
            } else {
                self.resetState()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Cancellation is handled by stop()/skip() — no action needed
    }
}
