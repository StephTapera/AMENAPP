import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Covenant Navigation View Model
// Central ObservableObject that owns the NavigationStack path and
// the current membership for the Covenant OS container view.

@MainActor
final class AmenCovenantViewModel: ObservableObject {

    // MARK: - Navigation State

    @Published var path: [CovenantRoute] = []

    // MARK: - Membership State

    @Published var currentMembership: CovenantMembership?
    @Published var currentCovenant: Covenant?
    @Published var isLoadingMembership: Bool = false
    @Published var membershipError: String?

    // MARK: - Private

    private let db = Firestore.firestore()
    private var deepLinkObserver: NSObjectProtocol?

    // MARK: - Init

    init() {
        deepLinkObserver = NotificationCenter.default.addObserver(
            forName: .amenCovenantDeepLink,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let route = notification.userInfo?["route"] as? CovenantDeepLinkRoute
            else { return }
            Task { await MainActor.run { self.handleDeepLink(route) } }
        }
    }

    deinit {
        if let observer = deepLinkObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Navigation

    func navigate(to route: CovenantRoute) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }

    // MARK: - Deep Link Handling

    func handleDeepLink(_ route: CovenantDeepLinkRoute) {
        let covenantRoute = route.covenantRoute
        // If the resolved route references a covenant, pre-load membership before pushing.
        switch covenantRoute {
        case .covenantHub(let cid), .room(let cid, _), .post(let cid, _),
             .event(let cid, _), .digest(let cid), .manage(let cid),
             .analytics(let cid), .moderation(let cid),
             .memberDirectory(let cid), .contentCalendar(let cid),
             .story(let cid, _):
            Task {
                await loadMembership(for: cid)
                navigate(to: covenantRoute)
            }
        default:
            navigate(to: covenantRoute)
        }
    }

    // MARK: - Membership Loading

    /// Loads membership from Firestore for the currently authenticated user.
    /// Sets `currentMembership` on the main actor. Idempotent — safe to call multiple times.
    func loadMembership(for covenantId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            currentMembership = nil
            return
        }
        isLoadingMembership = true
        membershipError = nil
        defer { isLoadingMembership = false }

        do {
            let snap = try await db.collection("covenantMemberships")
                .whereField("userId", isEqualTo: uid)
                .whereField("covenantId", isEqualTo: covenantId)
                .limit(to: 1)
                .getDocuments()
            currentMembership = snap.documents.first.flatMap { try? $0.data(as: CovenantMembership.self) }

            if let covenantId = snap.documents.first?.data()["covenantId"] as? String,
               currentCovenant?.id != covenantId {
                await loadCovenant(covenantId)
            }
        } catch {
            membershipError = error.localizedDescription
        }
    }

    /// Force-refreshes membership. Never trusts client-side state — always re-reads from Firestore.
    /// Use after checkout success, role changes, or tier upgrades.
    func refreshMembership(for covenantId: String) async {
        currentMembership = nil
        await loadMembership(for: covenantId)
    }

    // MARK: - Covenant Loading

    private func loadCovenant(_ covenantId: String) async {
        do {
            let doc = try await db.collection("covenants").document(covenantId).getDocument()
            currentCovenant = try? doc.data(as: Covenant.self)
        } catch {
            // Non-fatal — covenant metadata display is best-effort
        }
    }

    // MARK: - Destination Builder

    @MainActor @ViewBuilder
    func destination(for route: CovenantRoute) -> some View {
        switch route {
        case .discovery:
            AmenCovenantDiscoveryView().environmentObject(self)
        case .creatorHub(let id):
            AmenCreatorHubView(covenantId: id).environmentObject(self)
        case .covenantHub(let id):
            AmenCreatorHubView(covenantId: id).environmentObject(self)
        case .room(let cid, let rid):
            AmenCovenantRoomDetailView(covenantId: cid, roomId: rid).environmentObject(self)
        case .post(_, _):
            // Post detail view — coming soon
            placeholderDestination(title: "Post")
        case .event(let cid, _):
            AmenCovenantEventsView(covenantId: cid).environmentObject(self)
        case .digest(let cid):
            AmenCovenantDigestView(covenantId: cid).environmentObject(self)
        case .manage(let cid):
            AmenCovenantManageView(covenantId: cid).environmentObject(self)
        case .analytics(let cid):
            AmenCovenantAnalyticsView(covenantId: cid).environmentObject(self)
        case .moderation(let cid):
            AmenCovenantModerationView(covenantId: cid).environmentObject(self)
        case .memberDirectory(let cid):
            AmenCovenantMemberDirectoryView(covenantId: cid, directoryVisibility: .membersVisible).environmentObject(self)
        case .contentCalendar(let cid):
            AmenCovenantContentCalendarView(covenantId: cid).environmentObject(self)
        case .verification:
            AmenCreatorVerificationView()
        case .story(let cid, _):
            AmenCovenantStoryViewer(covenantId: cid)
        }
    }

    @ViewBuilder
    private func placeholderDestination(title: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
