// AmenHubViewModel.swift
// Amen Hub — Unified Inbox ViewModel (Agent B, Spiritual OS)
//
// Responsibilities:
//   • Owns HubItem model and HubItemType taxonomy
//   • Loads, paginates, pins, and marks items read via Firebase callables
//   • All @Published mutations occur on the main actor
//   • Feature-flag gating is enforced in AmenHubSectionView, not here
//
// Cloud Functions consumed:
//   • getHubItems   — paginated fetch, returns {items:[...], nextCursor?:String}
//   • pinHubItem    — toggles pin state server-side
// Firestore write:
//   • spiritualOS_hub/{userId}/items/{itemId}  →  isRead: true

import Foundation
import Firebase
import FirebaseFirestore
import FirebaseFunctions

// MARK: - HubItemType

enum HubItemType: String, Codable, CaseIterable, Identifiable {
    case message             = "message"
    case prayerRequest       = "prayerRequest"
    case churchNoteMention   = "churchNoteMention"
    case bereanAnswer        = "bereanAnswer"
    case groupInvite         = "groupInvite"
    case eventInvite         = "eventInvite"
    case mentorResponse      = "mentorResponse"
    case testimony           = "testimony"

    var id: String { rawValue }

    /// Human-readable filter label shown in the chip rail.
    var filterLabel: String {
        switch self {
        case .message:           return "Messages"
        case .prayerRequest:     return "Prayer"
        case .churchNoteMention: return "Mentions"
        case .bereanAnswer:      return "Berean"
        case .groupInvite:       return "Groups"
        case .eventInvite:       return "Events"
        case .mentorResponse:    return "Mentor"
        case .testimony:         return "Testimony"
        }
    }

    /// Default faith-tag label surfaced in the card badge.
    var defaultTag: String {
        switch self {
        case .message:           return "Message"
        case .prayerRequest:     return "Prayer"
        case .churchNoteMention: return "Mention"
        case .bereanAnswer:      return "Berean"
        case .groupInvite:       return "Community"
        case .eventInvite:       return "Event"
        case .mentorResponse:    return "Mentor"
        case .testimony:         return "Testimony"
        }
    }

    /// SF Symbol used when no sender avatar is available.
    var fallbackIcon: String {
        switch self {
        case .message:           return "bubble.left.and.bubble.right"
        case .prayerRequest:     return "hands.sparkles"
        case .churchNoteMention: return "doc.text"
        case .bereanAnswer:      return "sparkles"
        case .groupInvite:       return "person.3"
        case .eventInvite:       return "calendar"
        case .mentorResponse:    return "person.badge.plus"
        case .testimony:         return "star"
        }
    }
}

// MARK: - HubItem

struct HubItem: Identifiable, Codable {
    let id: String
    let type: HubItemType
    /// Faith-native tag displayed as the badge chip (e.g. "Prayer", "Church").
    let tag: String
    let title: String
    let preview: String?
    let senderUid: String?
    let senderName: String?
    let senderAvatar: String?
    /// Deep-link or internal reference used to navigate to the source (post ID, thread ID, etc.)
    let sourceRef: String
    var isPinned: Bool
    var isRead: Bool
    let createdAt: Date

    // MARK: Firestore-to-model mapping

    init(
        id: String,
        type: HubItemType,
        tag: String,
        title: String,
        preview: String?,
        senderUid: String?,
        senderName: String?,
        senderAvatar: String?,
        sourceRef: String,
        isPinned: Bool,
        isRead: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.type = type
        self.tag = tag
        self.title = title
        self.preview = preview
        self.senderUid = senderUid
        self.senderName = senderName
        self.senderAvatar = senderAvatar
        self.sourceRef = sourceRef
        self.isPinned = isPinned
        self.isRead = isRead
        self.createdAt = createdAt
    }

    /// Failable initializer from a raw Firestore/callable dictionary.
    init?(raw: [String: Any]) {
        guard
            let id       = raw["id"]       as? String,
            let typeRaw  = raw["type"]     as? String,
            let type     = HubItemType(rawValue: typeRaw),
            let title    = raw["title"]    as? String,
            let sourceRef = raw["sourceRef"] as? String
        else { return nil }

        let createdAtMs = raw["createdAt"] as? Double ?? 0
        let createdAt   = Date(timeIntervalSince1970: createdAtMs / 1000)

        self.id           = id
        self.type         = type
        self.tag          = (raw["tag"] as? String) ?? type.defaultTag
        self.title        = title
        self.preview      = raw["preview"]      as? String
        self.senderUid    = raw["senderUid"]    as? String
        self.senderName   = raw["senderName"]   as? String
        self.senderAvatar = raw["senderAvatar"] as? String
        self.sourceRef    = sourceRef
        self.isPinned     = (raw["isPinned"]    as? Bool) ?? false
        self.isRead       = (raw["isRead"]      as? Bool) ?? false
        self.createdAt    = createdAt
    }
}

// MARK: - AmenHubViewModel

@MainActor
final class AmenHubViewModel: ObservableObject {

    // MARK: - Published state

    @Published var items: [HubItem] = []
    @Published var isLoading: Bool = false
    @Published var hasMore: Bool = false
    @Published var filterType: HubItemType? = nil

    // MARK: - Private state

    private var allItems: [HubItem] = []
    private var nextCursor: String? = nil
    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    // MARK: - Computed

    var unreadCount: Int {
        allItems.filter { !$0.isRead }.count
    }

    // MARK: - Load (initial)

    /// Fetches the first page of hub items for the given user.
    /// Clears any existing data before populating.
    func load(userId: String) async {
        guard !isLoading else { return }
        isLoading = true
        nextCursor = nil

        do {
            let callable = functions.httpsCallable("getHubItems")
            let payload: [String: Any] = ["userId": userId, "pageSize": 20]
            let result   = try await callable.call(payload)
            let response = result.data as? [String: Any] ?? [:]
            let rawItems = response["items"] as? [[String: Any]] ?? []

            let fetched  = rawItems.compactMap { HubItem(raw: $0) }
            let cursor    = response["nextCursor"] as? String

            allItems   = fetched
            nextCursor = cursor
            hasMore    = (cursor != nil)
            applyFilter()
        } catch {
            // Surface non-crashing: leave existing items intact, just stop loading.
            // The view handles the empty / error state via the items array.
        }

        isLoading = false
    }

    // MARK: - Load more (pagination)

    /// Appends the next page. Safe to call while a load is already in flight — no-ops.
    func loadMore(userId: String) async {
        guard !isLoading, hasMore, let cursor = nextCursor else { return }
        isLoading = true

        do {
            let callable = functions.httpsCallable("getHubItems")
            let payload: [String: Any] = [
                "userId":   userId,
                "pageSize": 20,
                "cursor":   cursor
            ]
            let result   = try await callable.call(payload)
            let response = result.data as? [String: Any] ?? [:]
            let rawItems = response["items"] as? [[String: Any]] ?? []

            let fetched   = rawItems.compactMap { HubItem(raw: $0) }
            let newCursor = response["nextCursor"] as? String

            allItems.append(contentsOf: fetched)
            nextCursor = newCursor
            hasMore    = (newCursor != nil)
            applyFilter()
        } catch {
            // Pagination failure — leave existing items; hasMore stays true so the
            // user can retry by tapping "Show more in Hub" again.
        }

        isLoading = false
    }

    // MARK: - Pin

    /// Toggles the pin state for an item, updating both local state and the server.
    func pin(itemId: String, userId: String) async {
        // Optimistic local update
        guard let idx = allItems.firstIndex(where: { $0.id == itemId }) else { return }
        allItems[idx].isPinned.toggle()
        applyFilter()

        do {
            let callable = functions.httpsCallable("pinHubItem")
            let payload: [String: Any] = [
                "userId": userId,
                "itemId": itemId,
                "pinned": allItems[idx].isPinned
            ]
            _ = try await callable.call(payload)
        } catch {
            // Revert optimistic update on failure
            if let revertIdx = allItems.firstIndex(where: { $0.id == itemId }) {
                allItems[revertIdx].isPinned.toggle()
                applyFilter()
            }
        }
    }

    // MARK: - Mark read

    /// Marks a single item as read in Firestore and updates local state immediately.
    func markRead(itemId: String, userId: String) {
        guard let idx = allItems.firstIndex(where: { $0.id == itemId }),
              !allItems[idx].isRead else { return }

        allItems[idx].isRead = true
        applyFilter()

        let docRef = db
            .collection("spiritualOS_hub")
            .document(userId)
            .collection("items")
            .document(itemId)

        docRef.updateData(["isRead": true]) { _ in
            // No-op on error: mark-read is a best-effort UX signal, not safety-critical.
        }
    }

    // MARK: - Filter

    /// Sets the active filter and recomputes the displayed items list.
    func setFilter(_ type: HubItemType?) {
        filterType = type
        applyFilter()
    }

    // MARK: - Private

    private func applyFilter() {
        if let filterType {
            items = allItems.filter { $0.type == filterType }
        } else {
            items = allItems
        }
    }
}

// MARK: - AmenHubRealtimeViewModel
// Real-time Firestore snapshot listener inbox.
// Collection path: notifications/{uid}/items  ordered by timestamp desc, limit 50.
// Senders with 3+ items are collapsed into a single summary row.

@MainActor
final class AmenHubRealtimeViewModel: ObservableObject {

    // MARK: - Published

    @Published var items: [AmenHubItem] = []
    @Published var isLoading: Bool = false

    // MARK: - Private

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    /// UID stored when startListening(uid:) is called; reused by markAsRead(itemId:).
    private var currentUID: String = ""

    // MARK: - Computed

    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    // MARK: - Filter by AmenHubItemType? (used by SpiritualInboxView)

    func filteredItems(for type: AmenHubItemType?) -> [AmenHubItem] {
        guard let type else { return items }
        return items.filter { $0.type == type }
    }

    // MARK: - Filter by HubFilter (used by AmenHubSectionView)

    func filteredItems(for filter: HubFilter) -> [AmenHubItem] {
        guard filter != .all else { return items }
        return items.filter { filter.matches($0.type) }
    }

    // MARK: - Listener lifecycle

    func startListening(uid: String) {
        guard !uid.isEmpty else { return }
        currentUID = uid
        stopListening()
        isLoading = true

        listener = db
            .collection("notifications")
            .document(uid)
            .collection("items")
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    self.isLoading = false
                    guard error == nil, let docs = snapshot?.documents else { return }
                    let raw = docs.compactMap { AmenHubRealtimeViewModel.decode(doc: $0) }
                    self.items = AmenHubRealtimeViewModel.grouped(raw)
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Mark as read (itemId only — uses stored UID)

    func markAsRead(itemId: String) {
        guard !currentUID.isEmpty,
              let idx = items.firstIndex(where: { $0.id == itemId }),
              !items[idx].isRead else { return }

        items[idx].isRead = true

        db.collection("notifications")
            .document(currentUID)
            .collection("items")
            .document(itemId)
            .updateData(["isRead": true]) { _ in }
    }

    // MARK: - Pray for item

    /// Records a "prayed for" action under notifications/{uid}/prayedFor/{itemId}.
    /// Write is best-effort — failures are silently discarded (not safety-critical).
    func prayForItem(itemId: String, title: String) {
        guard !currentUID.isEmpty else { return }
        db.collection("notifications")
            .document(currentUID)
            .collection("prayedFor")
            .document(itemId)
            .setData([
                "title":    title,
                "prayedAt": Timestamp(date: Date())
            ], merge: true) { _ in }
    }

    // MARK: - Mark read (item + uid — used by AmenHubSectionView)

    func markRead(item: AmenHubItem, uid: String) {
        guard !item.isRead else { return }
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isRead = true
        }
        db.collection("notifications")
            .document(uid)
            .collection("items")
            .document(item.id)
            .updateData(["isRead": true]) { _ in }
    }

    // MARK: - Archive

    func archive(item: AmenHubItem, uid: String) {
        items.removeAll { $0.id == item.id }
        db.collection("notifications")
            .document(uid)
            .collection("items")
            .document(item.id)
            .updateData(["isArchived": true]) { _ in }
    }

    // MARK: - Grouping
    // Senders with 3+ items are collapsed into a single summary item.

    private static func grouped(_ source: [AmenHubItem]) -> [AmenHubItem] {
        var buckets: [String: [AmenHubItem]] = [:]
        for item in source {
            buckets[item.senderName, default: []].append(item)
        }

        var result: [AmenHubItem] = []
        for item in source {
            let bucket = buckets[item.senderName] ?? []
            let count  = bucket.count

            if count >= 3 {
                if result.contains(where: { $0.id == "\(item.senderName)_group" }) { continue }
                guard let newest = bucket.first else { continue }
                let summary = AmenHubItem(
                    id:             "\(item.senderName)_group",
                    type:           newest.type,
                    title:          "\(item.senderName) sent \(count) updates",
                    body:           "",
                    senderName:     item.senderName,
                    senderPhotoURL: newest.senderPhotoURL,
                    timestamp:      newest.timestamp,
                    isRead:         bucket.allSatisfy(\.isRead),
                    deepLink:       newest.deepLink
                )
                result.append(summary)
            } else {
                result.append(item)
            }
        }
        return result
    }

    // MARK: - Decoding

    private static func decode(doc: QueryDocumentSnapshot) -> AmenHubItem? {
        let data = doc.data()
        guard
            let typeRaw  = data["type"]       as? String,
            let type     = AmenHubItemType(rawValue: typeRaw),
            let title    = data["title"]       as? String,
            let body     = data["body"]        as? String,
            let sender   = data["senderName"]  as? String,
            let deepLink = data["deepLink"]    as? String
        else { return nil }

        let timestamp: Date
        if let ts = data["timestamp"] as? Timestamp {
            timestamp = ts.dateValue()
        } else if let ms = data["timestamp"] as? Double {
            timestamp = Date(timeIntervalSince1970: ms / 1000)
        } else {
            timestamp = Date()
        }

        return AmenHubItem(
            id:             doc.documentID,
            type:           type,
            title:          title,
            body:           body,
            senderName:     sender,
            senderPhotoURL: data["senderPhotoURL"] as? String,
            timestamp:      timestamp,
            isRead:         (data["isRead"] as? Bool) ?? false,
            deepLink:       deepLink
        )
    }
}
