import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class SupportGroupService: ObservableObject {
    @Published var recommendedGroups: [SupportGroup] = []
    @Published var myGroups: [SupportGroup] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var myGroupsListener: ListenerRegistration?

    var userId: String? { Auth.auth().currentUser?.uid }

    func loadRecommended() async {
        guard let uid = userId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await functions.httpsCallable("recommendSupportGroups").call(["userId": uid])
            if let data = result.data as? [[String: Any]] {
                recommendedGroups = data.compactMap { parseGroup(from: $0) }
            }
        } catch {
            let snap = try? await db.collection("supportGroups")
                .whereField("visibility", isEqualTo: "public")
                .order(by: "memberCount", descending: true)
                .limit(to: 10)
                .getDocuments()
            recommendedGroups = (snap?.documents ?? []).compactMap { try? $0.data(as: SupportGroup.self) }
        }
    }

    func startListeningMyGroups() {
        guard let uid = userId else { return }
        myGroupsListener = db.collection("supportGroups")
            .whereField("leaderUserId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                self?.myGroups = (snapshot?.documents ?? []).compactMap { try? $0.data(as: SupportGroup.self) }
            }
    }

    func joinGroup(groupId: String, inviteCode: String? = nil) async throws {
        guard let uid = userId else { return }
        var params: [String: Any] = ["groupId": groupId, "userId": uid]
        if let code = inviteCode { params["inviteCode"] = code }
        _ = try await functions.httpsCallable("joinSupportGroup").call(params)
    }

    func createGroup(name: String, description: String, category: SupportGroupCategory, tags: [String], guidelines: [String], visibility: SupportGroupVisibility) async throws -> String? {
        guard let uid = userId else { return nil }
        let result = try await functions.httpsCallable("createSupportGroup").call([
            "userId": uid, "name": name, "description": description,
            "category": category.rawValue, "focusTags": tags,
            "guidelines": guidelines, "visibility": visibility.rawValue
        ])
        return (result.data as? [String: Any])?["groupId"] as? String
    }

    private func parseGroup(from dict: [String: Any]) -> SupportGroup? {
        guard let id = dict["groupId"] as? String, let name = dict["name"] as? String else { return nil }
        return SupportGroup(id: id, name: name, description: dict["description"] as? String ?? "", category: SupportGroupCategory(rawValue: dict["category"] as? String ?? "other") ?? .other, focusTags: dict["focusTags"] as? [String] ?? [], leaderUserId: "", leaderName: dict["leader"] as? String ?? "", leaderVerified: false, createdAt: nil, visibility: .public, churchId: nil, memberCount: dict["memberCount"] as? Int ?? 0, guidelines: [], guardianModerated: true, postsLastWeek: 0, activeMembers: 0)
    }

    deinit { myGroupsListener?.remove() }
}
