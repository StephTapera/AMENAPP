import Foundation

@MainActor
final class BereanVoiceSessionManager: ObservableObject {
    static let shared = BereanVoiceSessionManager()

    @Published private(set) var activeSecret: BereanRealtimeClientSecret?
    @Published private(set) var transportState: BereanRealtimeWebSocketTransport.TransportState = .idle

    private let sessionManager: BereanRealtimeSessionManager
    private let analyticsService: BereanRealtimeAnalyticsService
    private let transport: BereanRealtimeWebSocketTransport

    init(
        sessionManager: BereanRealtimeSessionManager? = nil,
        analyticsService: BereanRealtimeAnalyticsService? = nil,
        transport: BereanRealtimeWebSocketTransport? = nil
    ) {
        self.sessionManager = sessionManager ?? .shared
        self.analyticsService = analyticsService ?? BereanRealtimeAnalyticsService()
        self.transport = transport ?? BereanRealtimeWebSocketTransport()
    }

    func startAssistantSession(
        sourceLanguage: BereanSupportedLanguage,
        targetLanguage: BereanSupportedLanguage? = nil,
        churchId: String? = nil,
        conversationId: String? = nil
    ) async throws -> BereanRealtimeClientSecret {
        let targets = [targetLanguage ?? sourceLanguage]
        let secret = try await sessionManager.createSession(
            type: .voiceAssistant,
            sourceLanguage: sourceLanguage,
            targetLanguages: targets,
            selectedLanguage: targetLanguage ?? sourceLanguage,
            churchId: churchId,
            conversationId: conversationId
        )
        activeSecret = secret
        try await transport.connect(clientSecret: secret, model: secret.model)
        transportState = .connected
        await sessionManager.markActive(sessionId: secret.sessionId)
        await analyticsService.track(sessionId: secret.sessionId, type: "voice_assistant_started", language: sourceLanguage)
        return secret
    }

    func sendAudio(_ data: Data) async throws {
        try await transport.appendInputAudio(data)
    }

    func commitAudioAndRequestResponse() async throws {
        try await transport.commitInputAudio()
        try await transport.requestResponse()
    }

    func interrupt() async {
        guard let activeSecret else { return }
        await analyticsService.track(sessionId: activeSecret.sessionId, type: "voice_assistant_interrupted")
        transport.disconnect()
        transportState = .disconnected
    }

    func endSession() async {
        guard let activeSecret else { return }
        transport.disconnect()
        await sessionManager.endCurrentSession()
        await analyticsService.track(sessionId: activeSecret.sessionId, type: "voice_assistant_ended")
        self.activeSecret = nil
        transportState = .idle
    }
}
