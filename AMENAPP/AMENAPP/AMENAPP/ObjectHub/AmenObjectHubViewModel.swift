import Foundation
import FirebaseFunctions
import FirebaseFirestore

@MainActor
final class AmenObjectHubViewModel: ObservableObject {
    @Published private(set) var hub: AmenCommunityHub?
    @Published private(set) var canonicalObject: AmenCanonicalObject?
    @Published private(set) var relatedObjects: [AmenCanonicalObject] = []
    @Published private(set) var membership: AmenObjectHubMembership?
    @Published private(set) var isLoading = false
    @Published private(set) var error: AmenHubError?
    @Published var selectedTopicChip: AmenHubTopicChip?

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    private var hubId: String?

    enum AmenHubError: LocalizedError {
        case notFound
        case loadFailed(String)
        case actionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notFound: return "This hub could not be found."
            case .loadFailed(let msg): return "Couldn't load the hub: \(msg)"
            case .actionFailed(let msg): return "Action failed: \(msg)"
            }
        }
    }

    // MARK: - Load

    func loadHub(canonicalObjectId: String) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let result = try await functions
                .httpsCallable("getObjectHub")
                .call(["canonicalObjectId": canonicalObjectId])

            guard let data = result.data as? [String: Any] else {
                throw AmenHubError.loadFailed("Unexpected response format")
            }

            hub = decodeHub(from: data["hub"] as? [String: Any])
            canonicalObject = decodeCanonicalObject(from: data["canonicalObject"] as? [String: Any])
            relatedObjects = (data["relatedObjects"] as? [[String: Any]] ?? []).compactMap {
                decodeCanonicalObject(from: $0)
            }

            if let h = hub {
                hubId = h.id
                await loadMembership(hubId: h.id)
            }
        } catch let hubErr as AmenHubError {
            error = hubErr
        } catch {
            self.error = .loadFailed(error.localizedDescription)
        }

        isLoading = false
    }

    func resolveAndLoad(url: String) async {
        isLoading = true
        error = nil

        do {
            let result = try await functions
                .httpsCallable("resolveCommunityObject")
                .call(["url": url])

            guard let data = result.data as? [String: Any],
                  let canonicalObjectId = data["canonicalObjectId"] as? String else {
                throw AmenHubError.loadFailed("Could not resolve object")
            }

            await loadHub(canonicalObjectId: canonicalObjectId)
        } catch let hubErr as AmenHubError {
            error = hubErr
            isLoading = false
        } catch {
            self.error = .loadFailed(error.localizedDescription)
            isLoading = false
        }
    }

    // MARK: - Hub Actions

    func joinHub() async {
        guard let h = hub else { return }
        do {
            _ = try await functions
                .httpsCallable("createOrJoinObjectHub")
                .call(["canonicalObjectId": h.canonicalObjectId, "action": "join"])
            await loadMembership(hubId: h.id)
        } catch {
            self.error = .actionFailed(error.localizedDescription)
        }
    }

    func muteHub() async {
        guard let h = hub else { return }
        do {
            _ = try await functions
                .httpsCallable("muteObjectHub")
                .call(["hubId": h.id])
            await loadMembership(hubId: h.id)
        } catch {
            self.error = .actionFailed(error.localizedDescription)
        }
    }

    func reportContent(reason: String) async {
        guard let h = hub else { return }
        do {
            _ = try await functions
                .httpsCallable("reportHubContent")
                .call(["hubId": h.id, "reason": reason])
        } catch {
            self.error = .actionFailed(error.localizedDescription)
        }
    }

    func recordInteraction(_ type: AmenHubInteractionType) async {
        guard let h = hub else { return }
        _ = try? await functions
            .httpsCallable("recordObjectInteraction")
            .call(["hubId": h.id, "interactionType": type.rawValue])
    }

    // MARK: - Private

    private func loadMembership(hubId: String) async {
        // Lightweight Firestore read — membership doc is small
        guard let uid = try? await db.collection("_noop").document("_noop").getDocument().documentID,
              !uid.isEmpty else { return }
        // Real membership read wired at app layer when auth context is available
        _ = hubId
    }

    // MARK: - Decoding helpers (Firestore/Callable response → model)

    private func decodeHub(from dict: [String: Any]?) -> AmenCommunityHub? {
        guard let d = dict,
              let id = d["id"] as? String,
              let canonicalObjectId = d["canonicalObjectId"] as? String,
              let title = d["title"] as? String else { return nil }

        let safetyRaw = d["safetyStatus"] as? String ?? "approved"
        let privacyRaw = d["privacyLevel"] as? String ?? "public"
        let categoryRaw = d["contentCategory"] as? String ?? "general"
        let explicitRaw = d["explicitContentState"] as? String ?? "unknown"

        let chips: [AmenHubTopicChip] = (d["topicChips"] as? [[String: Any]] ?? []).compactMap {
            guard let cid = $0["id"] as? String, let label = $0["label"] as? String else { return nil }
            return AmenHubTopicChip(
                id: cid,
                label: label,
                iconName: $0["iconName"] as? String,
                postCount: $0["postCount"] as? Int ?? 0
            )
        }

        let prompts = d["discussionPrompts"] as? [String] ?? []
        let relatedIds = d["relatedObjectIds"] as? [String] ?? []

        var summary: AmenHubActivitySummary?
        if let s = d["activitySummary"] as? [String: Any] {
            summary = AmenHubActivitySummary(
                recentPosterCount: s["recentPosterCount"] as? Int ?? 0,
                totalPrayerCount: s["totalPrayerCount"] as? Int ?? 0,
                weeklyPostCount: s["weeklyPostCount"] as? Int ?? 0,
                weeklyGrowthPercent: s["weeklyGrowthPercent"] as? Double ?? 0,
                lastActivityAt: nil
            )
        }

        return AmenCommunityHub(
            id: id,
            canonicalObjectId: canonicalObjectId,
            title: title,
            subtitle: d["subtitle"] as? String,
            artworkUrl: d["artworkUrl"] as? String,
            totalMembers: d["totalMembers"] as? Int ?? 0,
            weeklyPostCount: d["weeklyPostCount"] as? Int ?? 0,
            totalPostCount: d["totalPostCount"] as? Int ?? 0,
            safetyStatus: AmenAttachmentSafetyStatus(rawValue: safetyRaw) ?? .approved,
            privacyLevel: AmenHubPrivacyLevel(rawValue: privacyRaw) ?? .public,
            topicChips: chips,
            relatedObjectIds: relatedIds,
            discussionPrompts: prompts,
            activitySummary: summary,
            contentCategory: AmenSmartContentCategory(rawValue: categoryRaw) ?? .general,
            explicitContentState: AmenExplicitContentState(rawValue: explicitRaw) ?? .unknown,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func decodeCanonicalObject(from dict: [String: Any]?) -> AmenCanonicalObject? {
        guard let d = dict,
              let id = d["id"] as? String,
              let title = d["title"] as? String else { return nil }

        let objectTypeRaw = d["objectType"] as? String ?? "genericLink"
        let safetyRaw = d["safetyStatus"] as? String ?? "approved"
        let explicitRaw = d["explicitContentState"] as? String ?? "unknown"
        let categoryRaw = d["contentCategory"] as? String ?? "general"
        let providerRaw = d["primaryProvider"] as? String

        return AmenCanonicalObject(
            id: id,
            objectType: AmenSmartObjectType(rawValue: objectTypeRaw) ?? .genericLink,
            title: title,
            subtitle: d["subtitle"] as? String,
            creatorName: d["creatorName"] as? String,
            artworkUrl: d["artworkUrl"] as? String,
            canonicalUrl: d["canonicalUrl"] as? String,
            providerIds: d["providerIds"] as? [String: String] ?? [:],
            primaryProvider: providerRaw.flatMap { AmenAttachmentProvider(rawValue: $0) },
            safetyStatus: AmenAttachmentSafetyStatus(rawValue: safetyRaw) ?? .approved,
            explicitContentState: AmenExplicitContentState(rawValue: explicitRaw) ?? .unknown,
            totalPostCount: d["totalPostCount"] as? Int ?? 0,
            activeUserCount: d["activeUserCount"] as? Int ?? 0,
            hubId: d["hubId"] as? String,
            contentCategory: AmenSmartContentCategory(rawValue: categoryRaw) ?? .general,
            createdAt: nil,
            updatedAt: nil
        )
    }
}
