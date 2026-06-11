import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

enum ShareContentType: String, Codable, CaseIterable {
    case regularPost
    case versePost
    case churchNote
    case prayerRequest
    case testimony
    case sermonClip
    case event
    case profile
    case churchProfile
    case resource
    case mediaPost

    var title: String {
        switch self {
        case .regularPost: return "Share Post"
        case .versePost: return "Share Verse"
        case .churchNote: return "Share Church Note"
        case .prayerRequest: return "Share Prayer"
        case .testimony: return "Share Testimony"
        case .sermonClip: return "Share Sermon Clip"
        case .event: return "Share Event"
        case .profile: return "Share Profile"
        case .churchProfile: return "Share Church"
        case .resource: return "Share Resource"
        case .mediaPost: return "Share Post"
        }
    }

    var subtitle: String {
        switch self {
        case .prayerRequest:
            return "Share privately, with prayer circles, or trusted people"
        case .churchNote:
            return "Share with people, groups, churches, or Selah"
        default:
            return "Share with people, groups, churches, or stories"
        }
    }
}

enum ShareDestinationType: String, Codable {
    case directMessage
    case conversation
    case group
    case church
    case externalApp
    case copyLink
    case saved
}

enum ShareContextMode: String, Codable {
    case standard
    case prayerSensitive
    case verseForward
    case churchNotePreview
}

enum ShareVisibilityMode: String, Codable {
    case defaultAudience
    case privateShare
    case churchOnly
    case groupOnly
    case externalPreviewOnly
}

enum SharePayloadType: String, Codable {
    case deepLink
    case deepLinkWithPreview
    case verseCard
    case churchNotePreview
}

enum ShareSheetState: Equatable {
    case hidden
    case presenting
    case collapsed
    case preview
    case expanded
    case searching
    case selectingRecipient(String)
    case composingShareNote
    case sending(String)
    case success(String)
    case failure(String)
}

enum ShareFilterChip: String, CaseIterable, Identifiable {
    case suggested = "Suggested"
    case recent = "Recent"
    case people = "People"
    case groups = "Groups"
    case churches = "Churches"
    case closeFriends = "Close Friends"
    case ministry = "Ministry"
    case external = "External"

    var id: String { rawValue }
}

enum ShareTargetType: String, Codable {
    case person
    case conversation
    case group
    case church
    case external
}

struct SmartShareTarget: Identifiable, Equatable {
    let id: String
    let type: ShareTargetType
    let title: String
    let subtitle: String
    let imageURL: URL?
    let badge: String?
    let score: Double
    let reasons: [String]
    let isOnline: Bool
    let conversation: ChatConversation?
    let user: FollowUserProfile?

    var primaryReason: String? {
        reasons.first ?? badge
    }

    var accessibilityLabel: String {
        let reasonText = primaryReason.map { ", \($0)" } ?? ""
        return "Share with \(title)\(reasonText)"
    }

    static func == (lhs: SmartShareTarget, rhs: SmartShareTarget) -> Bool {
        lhs.id == rhs.id
    }
}

struct ShareContextOptions: Equatable {
    var includeCaption: Bool
    var includeVerseCard: Bool
    var includeAttribution: Bool
    var includeLinkPreview: Bool
    var sharePrivately: Bool
    var notifyRecipient: Bool
    var addNoteBeforeSending: Bool

    static func `default`(for contentType: ShareContentType) -> ShareContextOptions {
        ShareContextOptions(
            includeCaption: true,
            includeVerseCard: contentType == .versePost,
            includeAttribution: true,
            includeLinkPreview: true,
            sharePrivately: contentType == .prayerRequest,
            notifyRecipient: true,
            addNoteBeforeSending: false
        )
    }
}

struct SmartShareAction: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let destination: ShareDestinationType
}

struct ShareActivityPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

@MainActor
final class ShareSheetCoordinator: ObservableObject {
    enum Modal: Identifiable {
        case messageComposer
        case noteComposer

        var id: String {
            switch self {
            case .messageComposer: return "messageComposer"
            case .noteComposer: return "noteComposer"
            }
        }
    }

    @Published var modal: Modal?
    @Published var activityPayload: ShareActivityPayload?
}

struct SmartSharePayload {
    let text: String
    let deepLink: URL
    let externalItems: [Any]
    let shareCardPayload: AMENSharePayload
}

@MainActor
final class ShareAnalyticsTracker {
    static let shared = ShareAnalyticsTracker()

    private let db = Firestore.firestore()

    func track(
        actionType: String,
        destinationType: ShareDestinationType?,
        contentId: String,
        contentType: ShareContentType,
        targetId: String? = nil,
        sourceSurface: String = "feed",
        latencyMs: Int? = nil,
        result: String = "success"
    ) {
        guard let actorId = Auth.auth().currentUser?.uid else { return }

        let payload: [String: Any] = [
            "actorId": actorId,
            "sourceSurface": sourceSurface,
            "contentId": contentId,
            "contentType": contentType.rawValue,
            "actionType": actionType,
            "destinationType": destinationType?.rawValue as Any,
            "targetId": targetId as Any,
            "latencyMs": latencyMs as Any,
            "result": result,
            "createdAt": FieldValue.serverTimestamp()
        ]

        Task {
            do {
                try await db.collection("shareEvents").addDocument(data: payload)
            } catch {
                print("SmartShareSystem: failed to log shareEvent — \(error.localizedDescription)")
            }
        }
    }
}

struct ShareDeepLinkBuilder {
    func canonicalURL(for post: Post) -> URL {
        if let url = DeepLinkRouter.shared.generateURL(for: .post(id: post.firestoreId)) {
            return url
        }
        let encodedId = post.firestoreId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? post.firestoreId
        return URL(string: "amen://post/\(encodedId)") ?? URL(string: "amen://post")!
    }

    func webFallbackURL(for post: Post) -> URL {
        let encodedId = post.firestoreId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? post.firestoreId
        return URL(string: "https://amenapp.com/post/\(encodedId)") ?? URL(string: "https://amenapp.com")!
    }
}

struct SharePayloadFactory {
    private let linkBuilder = ShareDeepLinkBuilder()

    func contentType(for post: Post) -> ShareContentType {
        if post.churchNoteId != nil { return .churchNote }
        if post.category == .prayer { return .prayerRequest }
        if post.category == .testimonies { return .testimony }
        if let verseReference = post.verseReference, !verseReference.isEmpty { return .versePost }
        if post.imageURLs?.isEmpty == false { return .mediaPost }
        return .regularPost
    }

    func contextMode(for post: Post) -> ShareContextMode {
        let contentType = contentType(for: post)
        switch contentType {
        case .prayerRequest: return .prayerSensitive
        case .versePost: return .verseForward
        case .churchNote: return .churchNotePreview
        default: return .standard
        }
    }

    func makePayload(for post: Post, options: ShareContextOptions) -> SmartSharePayload {
        let deepLink = linkBuilder.canonicalURL(for: post)
        let webURL = linkBuilder.webFallbackURL(for: post)
        let shareCardPayload = makeShareCardPayload(for: post, deepLink: deepLink)

        var lines: [String] = []
        if options.includeCaption, !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(post.content)
        }
        if options.includeAttribution {
            lines.append("Shared from \(post.authorName) on AMEN")
        }
        lines.append(deepLink.absoluteString)

        let text = lines.joined(separator: "\n\n")
        let externalItems: [Any] = options.includeLinkPreview ? [text, webURL] : [text]

        return SmartSharePayload(
            text: text,
            deepLink: deepLink,
            externalItems: externalItems,
            shareCardPayload: shareCardPayload
        )
    }

    private func makeShareCardPayload(for post: Post, deepLink: URL) -> AMENSharePayload {
        let contentType = contentType(for: post)
        let postType: AMENSharePostType
        switch contentType {
        case .versePost:
            postType = .verse
        case .prayerRequest:
            postType = .prayer
        case .churchNote:
            postType = .churchNote
        case .testimony:
            postType = .testimony
        case .mediaPost:
            postType = (post.imageURLs?.count ?? 0) > 1 ? .carousel : .photo
        default:
            postType = .text
        }

        return AMENSharePayload(
            postType: postType,
            authorName: post.authorName,
            authorInitials: post.authorInitials,
            captionText: post.content,
            verseReference: post.verseReference,
            categoryLabel: post.category.displayName,
            imageData: nil,
            thumbnailData: nil,
            churchName: post.taggedChurchName ?? post.sharedChurchName,
            timestamp: post.createdAt,
            deepLinkURL: deepLink.absoluteString,
            carouselCount: max(post.imageURLs?.count ?? 1, 1),
            videoDuration: nil
        )
    }
}

struct ShareRankingEngine {
    func rank(
        targets: [SmartShareTarget],
        filter: ShareFilterChip,
        query: String,
        contentType: ShareContentType
    ) -> [SmartShareTarget] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return targets
            .filter { target in
                switch filter {
                case .suggested:
                    return true
                case .recent:
                    return target.reasons.contains("Recent conversation") || target.reasons.contains("Recent share")
                case .people, .closeFriends:
                    return target.type == .person || target.type == .conversation
                case .groups:
                    return target.type == .group
                case .churches, .ministry:
                    return target.type == .church
                case .external:
                    return target.type == .external
                }
            }
            .filter { target in
                guard !normalizedQuery.isEmpty else { return true }
                let haystack = "\(target.title) \(target.subtitle) \(target.reasons.joined(separator: " "))".lowercased()
                return haystack.contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                let contentBoostL = affinityBoost(for: lhs, contentType: contentType)
                let contentBoostR = affinityBoost(for: rhs, contentType: contentType)
                return lhs.score + contentBoostL > rhs.score + contentBoostR
            }
    }

    private func affinityBoost(for target: SmartShareTarget, contentType: ShareContentType) -> Double {
        switch contentType {
        case .prayerRequest:
            return target.reasons.contains("Prayer circle") ? 12 : 0
        case .versePost:
            return target.reasons.contains("Often sends verses") ? 10 : 0
        case .churchNote:
            return target.reasons.contains("Same church") ? 8 : 0
        default:
            return 0
        }
    }
}

@MainActor
final class ShareTargetSearchService {
    static let shared = ShareTargetSearchService()

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private let rankingEngine = ShareRankingEngine()

    func rankedTargets(
        for post: Post,
        query: String,
        filter: ShareFilterChip,
        currentTargets: [SmartShareTarget] = []
    ) async -> [SmartShareTarget] {
        let contentType = SharePayloadFactory().contentType(for: post)
        var targets = currentTargets

        if targets.isEmpty {
            targets = await localTargets(for: post)
        }

        if query.count >= 2 || filter == .groups || filter == .churches || filter == .ministry {
            let remoteTargets = await remoteTargets(query: query, filter: filter)
            targets = merge(targets, with: remoteTargets)
        }

        return rankingEngine.rank(targets: targets, filter: filter, query: query, contentType: contentType)
    }

    private func localTargets(for post: Post) async -> [SmartShareTarget] {
        var targets: [SmartShareTarget] = []

        if FirebaseMessagingService.shared.conversations.isEmpty {
            FirebaseMessagingService.shared.startListeningToConversations()
        }

        let conversations = FirebaseMessagingService.shared.conversations
            .filter { $0.status == "accepted" }
            .prefix(10)

        targets.append(contentsOf: conversations.enumerated().map { index, conversation in
            SmartShareTarget(
                id: "conversation-\(conversation.id)",
                type: .conversation,
                title: conversation.name,
                subtitle: conversation.lastMessage,
                imageURL: nil,
                badge: index < 2 ? "Recent" : nil,
                score: 100 - Double(index * 5),
                reasons: index == 0 ? ["Recent conversation"] : ["Recent share"],
                isOnline: false,
                conversation: conversation,
                user: nil
            )
        })

        let followingUsers: [FollowUserProfile]
        if !FollowService.shared.followingList.isEmpty {
            followingUsers = Array(FollowService.shared.followingList.prefix(12))
        } else if let currentUserId = Auth.auth().currentUser?.uid {
            followingUsers = Array((try? await FollowService.shared.fetchFollowing(userId: currentUserId))?.prefix(12) ?? [])
        } else {
            followingUsers = []
        }

        targets.append(contentsOf: followingUsers.enumerated().map { index, user in
            let reasons: [String]
            if user.bio?.lowercased().contains("prayer") == true {
                reasons = ["Prayer circle"]
            } else if index < 3 {
                reasons = ["Likely to engage"]
            } else {
                reasons = ["Shared similar posts before"]
            }

            return SmartShareTarget(
                id: "user-\(user.id)",
                type: .person,
                title: user.displayName,
                subtitle: "@\(user.username)",
                imageURL: URL(string: user.profileImageURL ?? ""),
                badge: reasons.first,
                score: 88 - Double(index * 3),
                reasons: reasons,
                isOnline: false,
                conversation: nil,
                user: user
            )
        })

        return dedupe(targets)
    }

    private func remoteTargets(query: String, filter: ShareFilterChip) async -> [SmartShareTarget] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return []
        }

        do {
            let callableResult = try await functions.httpsCallable("getSmartShareTargets").call([
                "query": trimmed,
                "filter": filter.rawValue
            ])
            if let data = callableResult.data as? [String: Any],
               let rawTargets = data["targets"] as? [[String: Any]] {
                return rawTargets.compactMap(Self.mapCallableTarget)
            }
        } catch {
            // Fallback to direct Firestore prefix search.
        }

        async let userDocs = prefixQuery(
            collection: "users",
            field: "displayNameLowercase",
            query: trimmed
        )
        async let groupDocs = prefixQuery(
            collection: "groups",
            field: "nameLowercase",
            query: trimmed
        )
        async let churchDocs = prefixQuery(
            collection: "churches",
            field: "nameLowercase",
            query: trimmed
        )

        let (users, groups, churches) = await (userDocs, groupDocs, churchDocs)

        return dedupe(
            users.compactMap(Self.mapUserDocument)
            + groups.compactMap(Self.mapGroupDocument)
            + churches.compactMap(Self.mapChurchDocument)
        )
    }

    private func prefixQuery(collection: String, field: String, query: String) async -> [QueryDocumentSnapshot] {
        do {
            let snapshot = try await db.collection(collection)
                .whereField(field, isGreaterThanOrEqualTo: query)
                .whereField(field, isLessThan: query + "\u{f8ff}")
                .limit(to: 12)
                .getDocuments()
            return snapshot.documents
        } catch {
            return []
        }
    }

    private func merge(_ lhs: [SmartShareTarget], with rhs: [SmartShareTarget]) -> [SmartShareTarget] {
        dedupe(lhs + rhs)
    }

    private func dedupe(_ targets: [SmartShareTarget]) -> [SmartShareTarget] {
        var seen = Set<String>()
        return targets.filter { target in
            seen.insert(target.id).inserted
        }
    }

    private static func mapCallableTarget(_ data: [String: Any]) -> SmartShareTarget? {
        guard
            let id = data["id"] as? String,
            let rawType = data["type"] as? String,
            let type = ShareTargetType(rawValue: rawType),
            let title = data["title"] as? String
        else {
            return nil
        }

        return SmartShareTarget(
            id: id,
            type: type,
            title: title,
            subtitle: data["subtitle"] as? String ?? "",
            imageURL: URL(string: data["imageURL"] as? String ?? ""),
            badge: data["badge"] as? String,
            score: data["score"] as? Double ?? 50,
            reasons: data["reasons"] as? [String] ?? [],
            isOnline: data["isOnline"] as? Bool ?? false,
            conversation: nil,
            user: nil
        )
    }

    private static func mapUserDocument(_ doc: QueryDocumentSnapshot) -> SmartShareTarget? {
        let data = doc.data()
        let displayName = (data["displayName"] as? String) ?? (data["username"] as? String) ?? "User"
        let username = (data["username"] as? String) ?? ""
        let profile = FollowUserProfile(
            id: doc.documentID,
            displayName: displayName,
            username: username,
            bio: data["bio"] as? String,
            profileImageURL: (data["profileImageURL"] as? String) ?? (data["photoURL"] as? String),
            followersCount: (data["followersCount"] as? Int) ?? 0,
            followingCount: (data["followingCount"] as? Int) ?? 0
        )

        return SmartShareTarget(
            id: "user-\(doc.documentID)",
            type: .person,
            title: displayName,
            subtitle: "@\(username)",
            imageURL: URL(string: profile.profileImageURL ?? ""),
            badge: "Suggested",
            score: 64,
            reasons: ["Likely to engage"],
            isOnline: false,
            conversation: nil,
            user: profile
        )
    }

    private static func mapGroupDocument(_ doc: QueryDocumentSnapshot) -> SmartShareTarget? {
        let data = doc.data()
        let title = (data["name"] as? String) ?? "Group"
        let subtitle = (data["type"] as? String) ?? "Group"
        return SmartShareTarget(
            id: "group-\(doc.documentID)",
            type: .group,
            title: title,
            subtitle: subtitle,
            imageURL: URL(string: data["imageURL"] as? String ?? ""),
            badge: "Group",
            score: 58,
            reasons: ["Small group"],
            isOnline: false,
            conversation: nil,
            user: nil
        )
    }

    private static func mapChurchDocument(_ doc: QueryDocumentSnapshot) -> SmartShareTarget? {
        let data = doc.data()
        let title = (data["name"] as? String) ?? "Church"
        let subtitle = (data["handle"] as? String) ?? ((data["denomination"] as? String) ?? "Church")
        return SmartShareTarget(
            id: "church-\(doc.documentID)",
            type: .church,
            title: title,
            subtitle: subtitle,
            imageURL: URL(string: data["imageURL"] as? String ?? ""),
            badge: "Your church",
            score: 56,
            reasons: ["Same church"],
            isOnline: false,
            conversation: nil,
            user: nil
        )
    }
}

@MainActor
final class SmartShareSheetViewModel: ObservableObject {
    @Published var state: ShareSheetState = .hidden
    @Published var selectedFilter: ShareFilterChip = .suggested
    @Published var searchText = ""
    @Published var targets: [SmartShareTarget] = []
    @Published var selectedTarget: SmartShareTarget?
    @Published var options: ShareContextOptions
    @Published var noteText = ""
    @Published var isSaved = false

    let post: Post
    let contentType: ShareContentType
    let contextMode: ShareContextMode

    private let searchService: ShareTargetSearchService
    private let payloadFactory = SharePayloadFactory()
    private var searchTask: Task<Void, Never>?
    private var hasLoaded = false

    init(post: Post, searchService: ShareTargetSearchService = .shared) {
        self.post = post
        self.searchService = searchService
        self.contentType = payloadFactory.contentType(for: post)
        self.contextMode = payloadFactory.contextMode(for: post)
        self.options = .default(for: payloadFactory.contentType(for: post))
    }

    var title: String { contentType.title }
    var subtitle: String { contentType.subtitle }

    var quickActions: [SmartShareAction] {
        var actions: [SmartShareAction] = [
            .init(id: "copy", title: "Copy Link", icon: "link", destination: .copyLink),
            .init(id: "external", title: "Share To…", icon: "square.and.arrow.up", destination: .externalApp),
            .init(id: "message", title: "Send in Message", icon: "paperplane", destination: .directMessage),
            .init(id: "save", title: isSaved ? "Saved" : "Save Post", icon: isSaved ? "bookmark.fill" : "bookmark", destination: .saved)
        ]

        switch contentType {
        case .versePost:
            break
        case .churchNote:
            actions.append(.init(id: "selah", title: "Open in Selah", icon: "sparkles.rectangle.stack", destination: .externalApp))
        case .prayerRequest:
            actions.append(.init(id: "prayer", title: "Prayer Share", icon: "hands.sparkles", destination: .directMessage))
        default:
            actions.append(.init(id: "church", title: "Church Group", icon: "building.columns", destination: .group))
        }

        return actions
    }

    var contextSummaryTitle: String {
        switch contextMode {
        case .prayerSensitive:
            return "Private prayer share is on"
        case .verseForward:
            return "Verse card context is on"
        case .churchNotePreview:
            return "Church note preview is on"
        case .standard:
            return "Smart share context is on"
        }
    }

    var contextSummarySubtitle: String {
        switch contextMode {
        case .prayerSensitive:
            return "Defaults to private sharing, attribution, and safe deep links."
        case .verseForward:
            return "Includes scripture attribution and a deep link back into AMEN."
        case .churchNotePreview:
            return "Includes a note preview, attribution, and Selah open route."
        case .standard:
            return "Adds attribution, relevant preview context, and a safe AMEN deep link."
        }
    }

    var searchPlaceholder: String {
        switch contentType {
        case .churchNote, .prayerRequest:
            return "Search people, groups, churches"
        default:
            return "Search recipients"
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        state = .presenting
        isSaved = RealtimeSavedPostsService.shared.isPostSavedSync(postId: post.firestoreId)
        targets = await searchService.rankedTargets(for: post, query: "", filter: selectedFilter)
        state = .expanded
        ShareAnalyticsTracker.shared.track(
            actionType: "sheet_opened",
            destinationType: nil,
            contentId: post.firestoreId,
            contentType: contentType
        )
    }

    func updateFilter(_ filter: ShareFilterChip) {
        selectedFilter = filter
        ShareAnalyticsTracker.shared.track(
            actionType: "chip_selected",
            destinationType: nil,
            contentId: post.firestoreId,
            contentType: contentType,
            targetId: filter.rawValue,
            result: "success"
        )
        queueSearch()
    }

    func queueSearch() {
        searchTask?.cancel()
        state = searchText.isEmpty ? .expanded : .searching
        let query = searchText
        let filter = selectedFilter
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            let results = await self.searchService.rankedTargets(
                for: self.post,
                query: query,
                filter: filter,
                currentTargets: self.targets
            )
            self.targets = results
            self.state = .expanded
            if !query.isEmpty {
                ShareAnalyticsTracker.shared.track(
                    actionType: "search_started",
                    destinationType: nil,
                    contentId: self.post.firestoreId,
                    contentType: self.contentType,
                    targetId: query,
                    result: "success"
                )
            }
        }
    }

    func payload() -> SmartSharePayload {
        payloadFactory.makePayload(for: post, options: options)
    }

    func send(to target: SmartShareTarget) async {
        selectedTarget = target
        state = .sending(target.id)
        let started = Date()

        do {
            switch target.type {
            case .conversation:
                try await sendToConversation(target)
            case .person:
                try await sendToPerson(target)
            case .group, .church, .external:
                throw NSError(
                    domain: "SmartShare",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "This target uses link-based sharing today."]
                )
            }

            let latency = Int(Date().timeIntervalSince(started) * 1_000)
            state = .success(target.title)
            ShareAnalyticsTracker.shared.track(
                actionType: "share_completed",
                destinationType: .directMessage,
                contentId: post.firestoreId,
                contentType: contentType,
                targetId: target.id,
                latencyMs: latency
            )
        } catch {
            state = .failure(error.localizedDescription)
            ShareAnalyticsTracker.shared.track(
                actionType: "share_failed",
                destinationType: .directMessage,
                contentId: post.firestoreId,
                contentType: contentType,
                targetId: target.id,
                result: error.localizedDescription
            )
        }
    }

    func toggleSave() async {
        do {
            isSaved = try await RealtimeSavedPostsService.shared.toggleSavePost(postId: post.firestoreId)
        } catch {
            state = .failure(error.localizedDescription)
        }
    }

    private func sendToConversation(_ target: SmartShareTarget) async throws {
        guard let conversation = target.conversation else {
            throw NSError(domain: "SmartShare", code: 404, userInfo: [NSLocalizedDescriptionKey: "Conversation unavailable"])
        }

        let messageId = UUID().uuidString
        let messageText = payload().text + noteSuffix()
        try await FirebaseMessagingService.shared.sendMessage(
            conversationId: conversation.id,
            text: messageText,
            clientMessageId: messageId
        )
        do {
            try await Firestore.firestore()
                .collection("conversations")
                .document(conversation.id)
                .collection("messages")
                .document(messageId)
                .updateData([
                    "postId": post.firestoreId,
                    "messageType": "postShare",
                    "deepLink": payload().deepLink.absoluteString,
                    "shareContextMode": contextMode.rawValue
                ])
        } catch {
            print("SmartShareSystem: failed to tag message metadata (conversation share) — \(error.localizedDescription)")
        }
    }

    private func sendToPerson(_ target: SmartShareTarget) async throws {
        guard let user = target.user else {
            throw NSError(domain: "SmartShare", code: 404, userInfo: [NSLocalizedDescriptionKey: "Recipient unavailable"])
        }

        let conversationId = try await FirebaseMessagingService.shared.getOrCreateConversation(
            with: user.id,
            participantName: user.displayName
        )
        let messageId = UUID().uuidString
        let messageText = payload().text + noteSuffix()
        try await FirebaseMessagingService.shared.sendMessage(
            conversationId: conversationId,
            text: messageText,
            clientMessageId: messageId
        )
        do {
            try await Firestore.firestore()
                .collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(messageId)
                .updateData([
                    "postId": post.firestoreId,
                    "messageType": "postShare",
                    "deepLink": payload().deepLink.absoluteString,
                    "shareContextMode": contextMode.rawValue
                ])
        } catch {
            print("SmartShareSystem: failed to tag message metadata (user share) — \(error.localizedDescription)")
        }
    }

    private func noteSuffix() -> String {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\n\n\(trimmed)"
    }
}
