// VoiceStreamManager.swift
// AMENAPP
//
// Berean Live Voice — AVAudioEngine streaming, barge-in, chunk emission
//
// Actor-isolated so all audio state mutations are serialised off the main thread.
// No existing files are modified.

import Foundation
import AVFoundation

// MARK: - VoiceStreamManager

/// Manages the AVAudioEngine pipeline for Berean Live Voice:
/// - Captures microphone input in 30 ms PCM chunks
/// - Plays synthesised speech via AVAudioPlayerNode
/// - Detects barge-in from the user while Berean is speaking
@available(macOS, unavailable)
actor VoiceStreamManager {

    // -------------------------------------------------------------------------
    // MARK: Audio Graph
    // -------------------------------------------------------------------------

    private var audioEngine     = AVAudioEngine()
    private var playerNode      = AVAudioPlayerNode()

    private var inputNode: AVAudioInputNode {
        audioEngine.inputNode
    }

    // -------------------------------------------------------------------------
    // MARK: State
    // -------------------------------------------------------------------------

    private(set) var isRecording: Bool = false
    private(set) var isPlaying:   Bool = false

    // -------------------------------------------------------------------------
    // MARK: Configuration
    // -------------------------------------------------------------------------

    let chunkDurationMs: Double = 30.0          // emit one chunk every 30 ms
    private var sampleRate: Double  = 16_000.0  // 16 kHz — Whisper's preferred rate

    // Accumulate float samples until a full chunk is ready.
    private var chunkBuffer: [Float] = []

    // Callbacks set by the ViewModel.
    private var onAudioChunk: ((BereanAudioChunk) -> Void)?
    private var onBargein:    (() -> Void)?

    // -------------------------------------------------------------------------
    // MARK: Configuration Entry Point
    // -------------------------------------------------------------------------

    /// Wire up callbacks and prepare the AVAudioSession + engine tap.
    func configure(
        onAudioChunk: @escaping (BereanAudioChunk) -> Void,
        onBargein:    @escaping () -> Void
    ) {
        self.onAudioChunk = onAudioChunk
        self.onBargein    = onBargein

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setPreferredSampleRate(sampleRate)
            try session.setActive(true)
        } catch {
            dlog("VoiceStreamManager: AVAudioSession configure failed — \(error)")
        }

        // Attach player node to the engine graph.
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode,
                            to: audioEngine.mainMixerNode,
                            format: nil)

        // Install tap on the input node (16 kHz mono).
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: recordingFormat
        ) { [weak self] buffer, _ in
            guard let self else { return }
            // Bridge actor isolation: dispatch back to the actor executor.
            Task { await self.processAudioBuffer(buffer) }
        }

        dlog("VoiceStreamManager: configured (sampleRate=\(sampleRate))")
    }

    // -------------------------------------------------------------------------
    // MARK: Recording
    // -------------------------------------------------------------------------

    /// Request microphone permission, then start the engine.
    func startRecording() throws {
        guard !isRecording else { return }

        // Permission check (synchronous flag query — actual prompt shown by iOS).
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard permissionStatus == .authorized else {
            dlog("VoiceStreamManager: mic permission not granted (\(permissionStatus.rawValue))")
            throw BereanVoiceError.micPermissionDenied
        }

        do {
            try audioEngine.start()
            isRecording = true
            dlog("VoiceStreamManager: recording started")
        } catch {
            throw BereanVoiceError.audioEngineFailure(error.localizedDescription)
        }
    }

    /// Stop capturing microphone audio.
    func stopRecording() {
        guard isRecording else { return }
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
        chunkBuffer.removeAll()
        dlog("VoiceStreamManager: recording stopped")
    }

    // -------------------------------------------------------------------------
    // MARK: Playback
    // -------------------------------------------------------------------------

    /// Schedule a raw PCM audio chunk (16-bit LE, 24 kHz) on the player node.
    func playAudioChunk(_ data: Data) {
        // TTS proxy returns 24 kHz 16-bit mono PCM.
        let ttsRate: Double = 24_000
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: ttsRate,
            channels: 1,
            interleaved: false
        ) else {
            dlog("VoiceStreamManager: could not create TTS audio format")
            return
        }

        let frameCount = AVAudioFrameCount(data.count / 2) // 2 bytes per Int16 sample
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            dlog("VoiceStreamManager: could not allocate PCM buffer")
            return
        }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawPtr in
            guard let src = rawPtr.baseAddress else { return }
            let dst = UnsafeMutableRawPointer(buffer.int16ChannelData![0])
            memcpy(dst, src, data.count)
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)

        if !isPlaying {
            playerNode.play()
            isPlaying = true
            dlog("VoiceStreamManager: playback started")
        }
    }

    /// Immediately stop playback — called during barge-in.
    func stopPlayback() {
        guard isPlaying else { return }
        playerNode.stop()
        isPlaying = false
        dlog("VoiceStreamManager: playback stopped (barge-in or end)")
    }

    // -------------------------------------------------------------------------
    // MARK: Barge-in Detection
    // -------------------------------------------------------------------------

    /// Returns `true` when the incoming mic level is loud enough to count as a barge-in.
    /// Threshold: −30 dBFS (calibrated for normal conversational speech).
    func detectBargein(inputLevel: Float) -> Bool {
        return inputLevel > -30.0
    }

    // -------------------------------------------------------------------------
    // MARK: Private — Buffer Processing
    // -------------------------------------------------------------------------

    /// Accumulate samples from each AVAudioEngine tap callback.
    /// Emits a `BereanAudioChunk` every `chunkDurationMs` ms.
    /// Also checks barge-in if the player is currently active.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // Append incoming samples to the rolling accumulation buffer.
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        chunkBuffer.append(contentsOf: samples)

        // How many samples constitute one chunk?
        let samplesPerChunk = Int(sampleRate * chunkDurationMs / 1000.0)

        while chunkBuffer.count >= samplesPerChunk {
            let slice = Array(chunkBuffer.prefix(samplesPerChunk))
            chunkBuffer.removeFirst(samplesPerChunk)

            // Barge-in: compute RMS and check threshold.
            if isPlaying {
                let rms = sqrt(slice.map { $0 * $0 }.reduce(0, +) / Float(slice.count))
                let dBFS = rms > 0 ? 20 * log10(rms) : -160
                if detectBargein(inputLevel: dBFS) {
                    dlog("VoiceStreamManager: barge-in detected (dBFS=\(dBFS))")
                    onBargein?()
                }
            }

            // Emit the chunk.
            let chunk = makeAudioChunk(from: slice)
            onAudioChunk?(chunk)
        }
    }

    /// Convert float samples (−1…1) to signed 16-bit PCM `Data`.
    private func makeAudioChunk(from samples: [Float]) -> BereanAudioChunk {
        var pcmData = Data(capacity: samples.count * 2)
        for sample in samples {
            // Clamp to [−1, 1] and scale to Int16 range.
            let clamped  = max(-1.0, min(1.0, sample))
            let int16Val = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: int16Val.littleEndian) { pcmData.append(contentsOf: $0) }
        }
        let durationMs = Double(samples.count) / sampleRate * 1000.0
        return BereanAudioChunk(data: pcmData, durationMs: durationMs)
    }
}
