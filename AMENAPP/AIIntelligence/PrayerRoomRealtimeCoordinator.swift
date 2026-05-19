import Foundation

@MainActor
final class PrayerRoomRealtimeCoordinator: ObservableObject {
    static let shared = PrayerRoomRealtimeCoordinator()

    @Published private(set) var activeSecret: BereanRealtimeClientSecret?

    private let sessionManager: BereanRealtimeSessionManager
    private let analyticsService: BereanRealtimeAnalyticsService

    init(
        sessionManager: BereanRealtimeSessionManager? = nil,
        analyticsService: BereanRealtimeAnalyticsService? = nil
    ) {
        self.sessionManager = sessionManager ?? .shared
        self.analyticsService = analyticsService ?? BereanRealtimeAnalyticsService()
    }

    func startPrayerRoom(
        sourceLanguage: BereanSupportedLanguage,
        targetLanguages: [BereanSupportedLanguage],
        churchId: String? = nil,
        prayerRoomId: String? = nil
    ) async throws -> BereanRealtimeClientSecret {
        let resolvedTargets = targetLanguages.isEmpty ? [sourceLanguage] : targetLanguages
        let secret = try await sessionManager.createSession(
            type: .livePrayerRoom,
            sourceLanguage: sourceLanguage,
            targetLanguages: resolvedTargets,
            selectedLanguage: resolvedTargets.first,
            churchId: churchId,
            prayerRoomId: prayerRoomId
        )
        activeSecret = secret
        await sessionManager.markActive(sessionId: secret.sessionId)
        await analyticsService.track(sessionId: secret.sessionId, type: "prayer_room_started", language: sourceLanguage)
        return secret
    }

    func endPrayerRoom() async {
        guard let activeSecret else { return }
        await sessionManager.endCurrentSession()
        await analyticsService.track(sessionId: activeSecret.sessionId, type: "prayer_room_ended")
        self.activeSecret = nil
    }
}
