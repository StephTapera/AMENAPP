// MessagingChannelAdapter.swift — AMEN IntegrationOS
// Calls `revokeMessagingConsent` and `checkBroadcastChannelStatus` CFs.

import Foundation
import FirebaseFunctions
import FirebaseAuth
import FirebaseRemoteConfig

final class MessagingChannelAdapter {
    static let shared = MessagingChannelAdapter()
    private init() {}

    private let functions = Functions.functions()
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_messaging_enabled").booleanValue }

    // MARK: - Channel Status

    struct ChannelStatus {
        let channel: BroadcastChannel
        let isAvailable: Bool
        let subscriberCount: Int?
        let errorMessage: String?
    }

    func checkChannelStatus(orgId: String, channel: BroadcastChannel) async throws -> ChannelStatus {
        guard isEnabled else { return ChannelStatus(channel: channel, isAvailable: false, subscriberCount: nil, errorMessage: "Disabled") }

        let result = try await functions.httpsCallable("checkBroadcastChannelStatus").call([
            "orgId": orgId,
            "channel": channel.rawValue
        ])

        guard let data = result.data as? [String: Any] else {
            return ChannelStatus(channel: channel, isAvailable: false, subscriberCount: nil, errorMessage: "Invalid response")
        }

        return ChannelStatus(
            channel: channel,
            isAvailable: data["available"] as? Bool ?? false,
            subscriberCount: data["subscriberCount"] as? Int,
            errorMessage: data["error"] as? String
        )
    }

    // MARK: - Revoke Consent

    func revokeConsent(channel: BroadcastChannel) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }
        try await functions.httpsCallable("revokeMessagingConsent").call([
            "uid": uid,
            "channel": channel.rawValue
        ])
    }

    // MARK: - Check All Channels

    func checkAllChannels(orgId: String) async -> [ChannelStatus] {
        await withTaskGroup(of: ChannelStatus.self) { group in
            for channel in BroadcastChannel.allCases {
                group.addTask {
                    (try? await self.checkChannelStatus(orgId: orgId, channel: channel)) ??
                    ChannelStatus(channel: channel, isAvailable: false, subscriberCount: nil, errorMessage: "Error")
                }
            }
            var statuses: [ChannelStatus] = []
            for await status in group { statuses.append(status) }
            return statuses.sorted { $0.channel.rawValue < $1.channel.rawValue }
        }
    }
}
