import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

@MainActor
@Observable
final class ProfileHeaderViewModel {
    let targetUserId: String
    let viewerUserId: String
    let isOwnProfile: Bool

    private(set) var payload: ProfileHeaderPayload?
    private(set) var isLoading = false
    private(set) var error: String?

    // Child stores — initialized after payload loads
    private(set) var linksStore: ProfileLinksStore?
    private(set) var pinnedPostsStore: PinnedPostsStore?
    private(set) var chipBarVM: ActionChipBarViewModel?
    private(set) var proSurfaceVM: ProSurfaceViewModel?

    private var loadTask: Task<Void, Never>?
    private let functions = Functions.functions()

    init(targetUserId: String, viewerUserId: String) {
        self.targetUserId = targetUserId
        self.viewerUserId = viewerUserId
        self.isOwnProfile = targetUserId == viewerUserId
    }

    func start() {
        loadTask = Task { [weak self] in
            guard let self else { return }
            await loadPayload()
        }
    }

    func stop() {
        loadTask?.cancel()
        linksStore?.stop()
        pinnedPostsStore?.stop()
    }

    private func loadPayload() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let result = try await functions
                .httpsCallable("getProfileHeaderPayload")
                .call(["userId": targetUserId, "viewerId": viewerUserId])

            guard let data = result.data as? [String: Any] else { return }

            let roleFlags = decodeRoleFlags(data["roleFlags"] as? [String: Any])
            let metrics = decodeMetrics(data["profileMetrics"] as? [String: Any])
            let links = decodeLinks(data["links"] as? [[String: Any]])
            let pinSlotIds = data["pinSlotIds"] as? [String] ?? []
            let bereanOptIn = data["bereanAboutOptIn"] as? Bool ?? false
            let hasGiving = data["hasGivingEnabled"] as? Bool ?? false
            let hasSub = data["hasSubscriptionEnabled"] as? Bool ?? false
            let visitURL = (data["visitChurchURL"] as? String).flatMap { URL(string: $0) }

            payload = ProfileHeaderPayload(
                userId: targetUserId,
                links: links,
                pinSlotIds: pinSlotIds,
                roleFlags: roleFlags,
                profileMetrics: metrics,
                bereanAboutOptIn: bereanOptIn,
                hasGivingEnabled: hasGiving,
                hasSubscriptionEnabled: hasSub,
                visitChurchURL: visitURL
            )

            // Initialize child stores
            let ls = ProfileLinksStore(userId: targetUserId)
            ls.start()
            linksStore = ls

            let ps = PinnedPostsStore(userId: targetUserId)
            ps.start()
            pinnedPostsStore = ps

            let chipVM = ActionChipBarViewModel(
                targetUserId: targetUserId,
                roleFlags: roleFlags,
                bereanAboutOptIn: bereanOptIn,
                linksStore: ls,
                viewerIsOwner: isOwnProfile
            )
            chipVM.start()
            chipBarVM = chipVM

            let proVM = ProSurfaceViewModel(userId: targetUserId, roleFlags: roleFlags)
            Task { await proVM.start() }
            proSurfaceVM = proVM

        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Decoders

    private func decodeRoleFlags(_ data: [String: Any]?) -> ProfileRoleFlags {
        guard let d = data else { return .empty }
        return ProfileRoleFlags(
            isMentor: d["isMentor"] as? Bool ?? false,
            isCreator: d["isCreator"] as? Bool ?? false,
            isMinistryLeader: d["isMinistryLeader"] as? Bool ?? false,
            isChurchAccount: d["isChurchAccount"] as? Bool ?? false,
            churchId: d["churchId"] as? String
        )
    }

    private func decodeMetrics(_ data: [String: Any]?) -> ProfileMetrics {
        guard let d = data else { return .empty }
        return ProfileMetrics(
            peopleDiscipled: d["peopleDiscipled"] as? Int ?? 0,
            versesShared: d["versesShared"] as? Int ?? 0,
            yearsWalkingWithChrist: d["yearsWalkingWithChrist"] as? Int,
            testimoniesGiven: d["testimoniesGiven"] as? Int ?? 0,
            prayersOffered: d["prayersOffered"] as? Int ?? 0
        )
    }

    private func decodeLinks(_ data: [[String: Any]]?) -> [LinkSlot] {
        guard let arr = data else { return [] }
        return arr.compactMap { LinkSlot(firestoreData: $0) }
            .sorted { $0.order < $1.order }
    }
}
