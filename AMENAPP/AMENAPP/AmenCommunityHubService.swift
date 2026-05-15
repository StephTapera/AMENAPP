import Foundation
import FirebaseFunctions

/// Wires the post-publish community hub indexing path.
///
/// After a post is published with a smart attachment, the iOS app calls
/// `attachHubPreview(postId:url:objectType:title:)`. The backend callable
/// resolves or creates the canonical object and hub, increments post counts,
/// and writes `communityHubPreview` back to the post via Admin SDK
/// (bypassing client security rules). The returned preview can be applied
/// immediately to the local Post model so PostCard shows the inline hub pill
/// without waiting for a Firestore listener round-trip.
@MainActor
final class AmenCommunityHubService {
    static let shared = AmenCommunityHubService()
    private let functions = Functions.functions()

    // MARK: - Post-publish hub attachment

    /// Called after publishing a post that has a smart attachment.
    /// Returns the newly written `AmenPostCommunityHubPreview` on success, nil on failure.
    /// Never throws — failures are logged and silently swallowed so posting is never blocked.
    func attachHubPreview(
        postId: String,
        url: String?,
        canonicalObjectId: String? = nil,
        objectType: String? = nil,
        title: String? = nil
    ) async -> AmenPostCommunityHubPreview? {
        guard AMENFeatureFlags.shared.communityHubsEnabled else { return nil }
        guard !postId.isEmpty, url != nil || canonicalObjectId != nil else { return nil }

        var payload: [String: Any] = ["postId": postId]
        if let canonicalObjectId { payload["canonicalObjectId"] = canonicalObjectId }
        if let url { payload["url"] = url }
        if let objectType { payload["objectType"] = objectType }
        if let title { payload["title"] = title }

        do {
            let result = try await functions.httpsCallable("attachCommunityHubPreviewToPost").call(payload)
            guard let data = result.data as? [String: Any],
                  let previewRaw = data["communityHubPreview"] as? [String: Any] else { return nil }
            return parsePreview(previewRaw)
        } catch {
            // Non-fatal: hub preview is best-effort
            return nil
        }
    }

    // MARK: - Hub discovery / navigation

    func resolveCommunityObject(
        url: String? = nil,
        provider: String? = nil,
        providerId: String? = nil
    ) async throws -> String? {
        var payload: [String: Any] = [:]
        if let url { payload["url"] = url }
        if let provider { payload["provider"] = provider }
        if let providerId { payload["providerId"] = providerId }

        let result = try await functions.httpsCallable("resolveCommunityObject").call(payload)
        let data = result.data as? [String: Any]
        return data?["canonicalObjectId"] as? String
    }

    // MARK: - Private helpers

    private func parsePreview(_ raw: [String: Any]) -> AmenPostCommunityHubPreview? {
        guard let hubId = raw["hubId"] as? String, !hubId.isEmpty,
              let canonicalObjectId = raw["canonicalObjectId"] as? String, !canonicalObjectId.isEmpty,
              let objectType = raw["objectType"] as? String,
              let title = raw["title"] as? String,
              let aggregateText = raw["aggregateText"] as? String,
              let actionText = raw["actionText"] as? String else {
            return nil
        }

        return AmenPostCommunityHubPreview(
            hubId: hubId,
            canonicalObjectId: canonicalObjectId,
            objectTypeRaw: objectType,
            title: title,
            aggregateText: aggregateText,
            actionText: actionText,
            safetyStateRaw: raw["safetyState"] as? String ?? "needsReview",
            explicitContentStateRaw: raw["explicitContentState"] as? String ?? "unknown",
            privacyStateRaw: raw["privacyState"] as? String ?? "public",
            iconKind: raw["iconKind"] as? String,
            canonicalUrl: raw["canonicalUrl"] as? String
        )
    }
}
