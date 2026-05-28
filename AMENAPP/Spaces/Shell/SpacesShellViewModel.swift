// SpacesShellViewModel.swift
// AMENAPP — Spaces v2 Navigation Shell (Agent C)
//
// ViewModel for the Spaces navigation shell.
// Loads and filters AmenSpaceExtended from Firestore for a given community.

import Foundation
import Combine
import FirebaseFirestore

// MARK: - SpaceListFilter

/// Filter states for the Spaces list tab row.
enum SpaceListFilter: String, CaseIterable, Identifiable {
    case all      = "All"
    case vip      = "VIP"
    case unreads  = "Unreads"
    case external = "External"

    var id: String { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .all:      return "All Spaces"
        case .vip:      return "VIP Spaces"
        case .unreads:  return "Spaces with unread messages"
        case .external: return "Spaces shared with other communities"
        }
    }
}

// MARK: - SpacesShellViewModel

@MainActor
final class SpacesShellViewModel: ObservableObject {

    // MARK: Published state

    @Published var spaces: [AmenSpaceExtended] = []
    @Published var filteredSpaces: [AmenSpaceExtended] = []
    @Published var currentFilter: SpaceListFilter = .all
    @Published var isLoading: Bool = false
    @Published var error: Error? = nil

    // MARK: Unread counts (keyed by spaceId)
    /// Populate from Firestore read-state sub-collection or local notification badges.
    /// SpacesShellViewModel does NOT own the write path; callers update this dict.
    @Published var unreadCounts: [String: Int] = [:]

    // MARK: VIP Spaces (UserDefaults-persisted Set<String>)

    private static let vipDefaultsKey = "vipSpaceIds"

    var vipSpaceIds: Set<String> {
        get {
            let arr = UserDefaults.standard.array(forKey: Self.vipDefaultsKey) as? [String] ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Self.vipDefaultsKey)
        }
    }

    func toggleVip(spaceId: String) {
        var ids = vipSpaceIds
        if ids.contains(spaceId) {
            ids.remove(spaceId)
        } else {
            ids.insert(spaceId)
        }
        vipSpaceIds = ids
        applyFilter(currentFilter)
    }

    // MARK: Private

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    // MARK: Load

    /// Attaches a real-time Firestore listener for the community's non-deleted Spaces.
    /// Ordered by title ascending. Excludes soft-deleted documents.
    func loadSpaces(communityId: String) async {
        isLoading = true
        error = nil

        listener?.remove()
        listener = db.collection("spaces")
            .whereField("communityId", isEqualTo: communityId)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "title")
            .addSnapshotListener { [weak self] snapshot, err in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    if let err {
                        self.error = err
                        return
                    }
                    guard let snapshot else { return }
                    let decoded: [AmenSpaceExtended] = snapshot.documents.compactMap { doc in
                        try? doc.data(as: AmenSpaceExtended.self)
                    }
                    self.spaces = decoded
                    self.applyFilter(self.currentFilter)
                }
            }
    }

    /// Applies the given filter to the loaded spaces array and updates filteredSpaces.
    func applyFilter(_ filter: SpaceListFilter) {
        currentFilter = filter
        switch filter {
        case .all:
            filteredSpaces = spaces
        case .vip:
            let ids = vipSpaceIds
            filteredSpaces = spaces.filter { ids.contains($0.id ?? "") }
        case .unreads:
            filteredSpaces = spaces.filter { (unreadCounts[$0.id ?? ""] ?? 0) > 0 }
        case .external:
            filteredSpaces = spaces.filter { !$0.sharedWith.isEmpty }
        }
    }

    // MARK: Lifecycle

    deinit {
        listener?.remove()
    }
}
