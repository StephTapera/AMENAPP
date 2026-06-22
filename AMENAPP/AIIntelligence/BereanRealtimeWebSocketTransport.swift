import Foundation
import FirebaseFunctions

@MainActor
final class BereanRealtimeWebSocketTransport: ObservableObject {
    enum TransportState: Equatable {
        case idle
        case connecting
        case connected
        case reconnecting(Int)
        case disconnected
        case failed(String)
    }

    @Published private(set) var state: TransportState = .idle
    @Published private(set) var receivedEvents: [[String: Any]] = []
    @Published private(set) var bufferedAudioBytes = 0

    // MARK: - Translation bar helpers
    // These computed properties map internal transport state to the two
    // parameters consumed by BereanLiveTranslationBar, keeping call sites
    // free of transport-state switch statements.

    /// Non-nil when the transport has failed permanently (max retries exhausted).
    /// Pass as `translationError` on `BereanLiveTranslationBar`.
    var translationBarError: String? {
        if case .failed(let reason) = state { return reason }
        return nil
    }

    /// True while the transport is in a retry back-off loop.
    /// Pass as `isReconnecting` on `BereanLiveTranslationBar`.
    var translationBarIsReconnecting: Bool {
        if case .reconnecting = state { return true }
        return false
    }

    private let functions = Functions.functions()
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var tokenRefreshTask: Task<Void, Never>?
    private var refreshClientSecret: (() async throws -> BereanRealtimeClientSecret)?
    private var activeSecret: BereanRealtimeClientSecret?
    private var activeModel: String?
    private var retryCount = 0
    private let maxRetries = 4
    private let maxBufferedAudioBytes = 384_000
    private let openAIRealtimeFallbackEndpoint = "wss://api.openai.com/v1/realtime"

    func connect(
        clientSecret: BereanRealtimeClientSecret,
        model: String? = nil,
        refreshClientSecret: (() async throws -> BereanRealtimeClientSecret)? = nil
    ) async throws {
        disconnect(shouldMarkDisconnected: false)
        self.refreshClientSecret = refreshClientSecret
        activeSecret = clientSecret
        activeModel = model
        retryCount = 0
        try await openSocket(clientSecret: clientSecret, model: model)
        scheduleTokenRefresh(for: clientSecret)
    }

    func sendJSON(_ payload: [String: Any]) async throws {
        guard let task else { throw BereanRealtimeTransportError.notConnected }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await task.send(.string(text))
    }

    func appendInputAudio(_ audio: Data) async throws {
        guard bufferedAudioBytes + audio.count <= maxBufferedAudioBytes else {
            throw BereanRealtimeTransportError.backpressureLimitReached
        }
        bufferedAudioBytes += audio.count
        try await sendJSON([
            "type": "input_audio_buffer.append",
            "audio": audio.base64EncodedString(),
        ])
    }

    func commitInputAudio() async throws {
        try await sendJSON(["type": "input_audio_buffer.commit"])
        bufferedAudioBytes = 0
    }

    func requestResponse(instructions: String? = nil) async throws {
        var response: [String: Any] = ["modalities": ["text", "audio"]]
        if let instructions, !instructions.isEmpty {
            response["instructions"] = instructions
        }
        try await sendJSON(["type": "response.create", "response": response])
    }

    func persistTranscriptChunk(
        sessionId: String,
        text: String,
        kind: String,
        language: BereanSupportedLanguage,
        targetLanguage: BereanSupportedLanguage? = nil,
        isFinal: Bool = true,
        startsAtMs: Int = 0,
        durationMs: Int = 0
    ) async throws {
        // AUDIT A5-011: transcript should be sanitized via BereanContextCoordinator before persistence
        _ = try await functions.httpsCallable("persistRealtimeTranscriptChunk").call([
            "sessionId": sessionId,
            "text": text,
            "kind": kind,
            "language": language.rawValue,
            "targetLanguage": (targetLanguage ?? language).rawValue,
            "isFinal": isFinal,
            "startsAtMs": startsAtMs,
            "durationMs": durationMs,
        ])
    }

    func disconnect() {
        disconnect(shouldMarkDisconnected: true)
    }

    private func openSocket(clientSecret: BereanRealtimeClientSecret, model: String?) async throws {
        state = retryCount == 0 ? .connecting : .reconnecting(retryCount)

        guard let baseEndpoint = clientSecret.endpoint else {
            state = .failed("No realtime endpoint in session secret.")
            throw BereanRealtimeTransportError.invalidURL
        }

        var components = URLComponents(url: baseEndpoint, resolvingAgainstBaseURL: false)
        if let resolvedModel = model ?? clientSecret.model {
            var queryItems = components?.queryItems ?? []
            queryItems.append(URLQueryItem(name: "model", value: resolvedModel))
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            state = .failed("Could not construct realtime URL from endpoint.")
            throw BereanRealtimeTransportError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(clientSecret.value)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let webSocketTask = URLSession.shared.webSocketTask(with: request)
        task = webSocketTask
        webSocketTask.resume()
        state = .connected
        receiveLoop()
    }

    private func receiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    guard let task = await MainActor.run(body: { self.task }) else { return }
                    let message = try await task.receive()
                    await self.handle(message)
                } catch {
                    await self.reconnect(after: error)
                    return
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data?
        switch message {
        case .data(let value): data = value
        case .string(let value): data = value.data(using: .utf8)
        @unknown default: data = nil
        }
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        receivedEvents.append(object)
        if receivedEvents.count > 200 {
            receivedEvents.removeFirst(receivedEvents.count - 200)
        }
    }

    private func reconnect(after error: Error) async {
        guard !Task.isCancelled else { return }
        guard retryCount < maxRetries else {
            state = .failed(error.localizedDescription)
            return
        }
        retryCount += 1
        state = .reconnecting(retryCount)
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        let jitter = Double.random(in: 0.5...1.5)
        let delayNs = UInt64(min(pow(2.0, Double(retryCount)) * 0.35 * jitter, 4.0) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: delayNs)

        do {
            let secret = try await validSecretForReconnect()
            try await openSocket(clientSecret: secret, model: activeModel)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func validSecretForReconnect() async throws -> BereanRealtimeClientSecret {
        if let activeSecret, activeSecret.expiresAt.timeIntervalSinceNow > 15 {
            return activeSecret
        }
        guard let refreshClientSecret else { throw BereanRealtimeTransportError.expiredToken }
        let next = try await refreshClientSecret()
        activeSecret = next
        scheduleTokenRefresh(for: next)
        return next
    }

    private func scheduleTokenRefresh(for secret: BereanRealtimeClientSecret) {
        tokenRefreshTask?.cancel()
        guard refreshClientSecret != nil else { return }
        let refreshAfter = max(secret.expiresAt.timeIntervalSinceNow - 15, 5)
        tokenRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(refreshAfter * 1_000_000_000))
            guard let self else { return }
            do {
                let next = try await self.refreshClientSecret?()
                if let next {
                    await MainActor.run {
                        self.activeSecret = next
                        self.scheduleTokenRefresh(for: next)
                    }
                }
            } catch {
                await MainActor.run { self.state = .failed(error.localizedDescription) }
            }
        }
    }

    private func disconnect(shouldMarkDisconnected: Bool) {
        receiveTask?.cancel()
        tokenRefreshTask?.cancel()
        receiveTask = nil
        tokenRefreshTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        bufferedAudioBytes = 0
        if shouldMarkDisconnected { state = .disconnected }
    }
}

enum BereanRealtimeTransportError: LocalizedError {
    case invalidURL
    case notConnected
    case expiredToken
    case backpressureLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Realtime transport URL is invalid."
        case .notConnected: return "Realtime transport is not connected."
        case .expiredToken: return "Realtime token expired and could not be refreshed."
        case .backpressureLimitReached: return "Realtime audio buffer is full."
        }
    }
}
