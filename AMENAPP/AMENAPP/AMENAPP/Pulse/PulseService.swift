//
//  PulseService.swift
//  AMEN — Amen Pulse
//
//  The client reads ONE document per day: /users/{uid}/pulse/{date}. No client-side
//  ranking, ever — selection and cap enforcement happen server-side. This service only
//  fetches, caches, observes, and writes user-owned state (prefs, bookmarks, feedback).
//
//  Mirrors the BereanPulseService pattern (provider protocol + Firestore impl + DEBUG mock
//  + on-disk JSON cache + on-demand callable refresh).
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Provider protocol

protocol PulseProviding {
    func fetchDigest(userId: String, dateKey: String) async throws -> PulseDigest?
    func observeDigest(userId: String, dateKey: String) -> AsyncStream<PulseDigest?>
    func fetchPrefs(userId: String) async throws -> PulsePrefs
    func updatePrefs(userId: String, prefs: PulsePrefs) async throws
    func fetchWhatsNew(includeAdultOnly: Bool) async throws -> [WhatsNewStory]
    func fetchStory(id: String) async throws -> WhatsNewStory?
    func fetchBookmarks(userId: String) async throws -> Set<String>
    func setBookmark(userId: String, storyId: String, bookmarked: Bool) async throws
}

enum PulseServiceError: LocalizedError, Equatable {
    case missingUser

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return String(localized: "Amen Pulse needs a signed-in user.")
        }
    }
}

// MARK: - Firestore decode helpers

enum PulseDecode {
    static func date(_ any: Any?) -> Date? {
        if let ts = any as? Timestamp { return ts.dateValue() }
        if let d = any as? Date { return d }
        return nil
    }

    static func score(_ any: Any?) -> PulseScore {
        guard let d = any as? [String: Any] else { return PulseScore() }
        return PulseScore(
            relationship: d["relationship"] as? Double ?? 0,
            spiritual: d["spiritual"] as? Double ?? 0,
            community: d["community"] as? Double ?? 0,
            urgency: d["urgency"] as? Double ?? 0,
            interest: d["interest"] as? Double ?? 0,
            composite: d["composite"] as? Double ?? 0
        )
    }

    static func hero(_ any: Any?) -> PulseHero {
        let d = any as? [String: Any] ?? [:]
        return PulseHero(
            imageUrl: d["imageUrl"] as? String,
            videoUrl: d["videoUrl"] as? String,
            scrim: PulseScrim(rawValue: d["scrim"] as? String ?? "light") ?? .light,
            style: d["style"] as? String ?? "verse"
        )
    }

    static func action(_ any: Any?) -> PulseAction {
        guard let d = any as? [String: Any] else { return .none }
        return PulseAction(
            kind: PulseActionKind(rawValue: d["kind"] as? String ?? "none") ?? .none,
            label: d["label"] as? String ?? "",
            deeplink: d["deeplink"] as? String,
            payload: d["payload"] as? [String: String] ?? [:]
        )
    }

    static func facts(_ any: Any?) -> [PulseFact]? {
        guard let arr = any as? [[String: Any]] else { return nil }
        let mapped = arr.compactMap { row -> PulseFact? in
            guard let text = row["text"] as? String else { return nil }
            return PulseFact(systemImage: row["systemImage"] as? String ?? "circle", text: text)
        }
        return mapped.isEmpty ? nil : mapped
    }

    static func briefSections(_ any: Any?) -> [PulseBriefSection]? {
        guard let arr = any as? [[String: Any]] else { return nil }
        let mapped = arr.compactMap { row -> PulseBriefSection? in
            guard let heading = row["heading"] as? String, let body = row["body"] as? String else { return nil }
            let dur = PulseBriefDuration(rawValue: row["minimumDuration"] as? String ?? "3m") ?? .threeMin
            return PulseBriefSection(heading: heading, body: body, minimumDuration: dur)
        }
        return mapped.isEmpty ? nil : mapped
    }

    static func card(_ d: [String: Any]) -> PulseCard? {
        guard let id = d["id"] as? String,
              let kind = PulseCardKind(rawValue: d["kind"] as? String ?? "") else { return nil }
        return PulseCard(
            id: id,
            kind: kind,
            score: score(d["score"]),
            hero: hero(d["hero"]),
            eyebrow: d["eyebrow"] as? String ?? "",
            title: d["title"] as? String ?? "",
            subtitle: d["subtitle"] as? String,
            action: action(d["action"]),
            minorSafe: d["minorSafe"] as? Bool ?? false,   // fail-closed: unknown ⇒ minor-unsafe
            expiresAt: date(d["expiresAt"]),
            provenanceLabel: d["provenanceLabel"] as? String,
            facts: facts(d["facts"]),
            meta: facts(d["meta"]),
            briefSections: briefSections(d["briefSections"]),
            whatsNewStoryId: d["whatsNewStoryId"] as? String
        )
    }

    static func digest(_ data: [String: Any], fallbackDateKey: String) -> PulseDigest {
        let cardDicts = data["cards"] as? [[String: Any]] ?? []
        let cards = cardDicts.compactMap(card)
        let durations = (data["briefDurations"] as? [String] ?? [])
            .compactMap(PulseBriefDuration.init(rawValue:))
        return PulseDigest(
            date: data["date"] as? String ?? fallbackDateKey,
            cards: cards,
            generatedAt: date(data["generatedAt"]),
            sabbath: data["sabbath"] as? Bool ?? false,
            briefDurations: durations.isEmpty ? [.thirtySec, .threeMin, .tenMin] : durations
        )
    }

    static func story(_ data: [String: Any], id: String) -> WhatsNewStory? {
        let pageDicts = data["pages"] as? [[String: Any]] ?? []
        let pages = pageDicts.compactMap { row -> WhatsNewPage? in
            guard let headline = row["headline"] as? String else { return nil }
            return WhatsNewPage(
                heroImageUrl: row["heroImageUrl"] as? String,
                style: row["style"] as? String,
                headline: headline,
                body: row["body"] as? String ?? "",
                layout: WhatsNewLayout(rawValue: row["layout"] as? String ?? "full_bleed") ?? .fullBleed
            )
        }
        var tryAction: WhatsNewTryAction?
        if let ta = data["tryAction"] as? [String: Any],
           let link = ta["deeplink"] as? String, let label = ta["label"] as? String {
            tryAction = WhatsNewTryAction(deeplink: link, label: label)
        }
        return WhatsNewStory(
            id: id,
            version: data["version"] as? String ?? "",
            title: data["title"] as? String ?? "",
            tagline: data["tagline"] as? String ?? "",
            pages: pages,
            tryAction: tryAction,
            videoUrl: data["videoUrl"] as? String,
            audience: WhatsNewAudience(rawValue: data["audience"] as? String ?? "all") ?? .all,
            publishedAt: date(data["publishedAt"]),
            bookmarkable: data["bookmarkable"] as? Bool ?? true
        )
    }
}

// MARK: - Firestore provider

struct FirestorePulseProvider: PulseProviding {
    private let db = Firestore.firestore()

    private func pulseCollection(_ userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("pulse")
    }
    private func prefsDoc(_ userId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("pulsePrefs").document("main")
    }
    private func bookmarksCollection(_ userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("bookmarks")
    }

    func fetchDigest(userId: String, dateKey: String) async throws -> PulseDigest? {
        let snap = try await pulseCollection(userId).document(dateKey).getDocument()
        guard let data = snap.data() else { return nil }
        return PulseDecode.digest(data, fallbackDateKey: dateKey)
    }

    func observeDigest(userId: String, dateKey: String) -> AsyncStream<PulseDigest?> {
        AsyncStream { continuation in
            let listener = pulseCollection(userId).document(dateKey).addSnapshotListener { snap, _ in
                guard let data = snap?.data() else { continuation.yield(nil); return }
                continuation.yield(PulseDecode.digest(data, fallbackDateKey: dateKey))
            }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    func fetchPrefs(userId: String) async throws -> PulsePrefs {
        let snap = try await prefsDoc(userId).getDocument()
        guard let d = snap.data() else { return .default }
        let sourcesDict = d["sources"] as? [String: Any] ?? [:]
        let sources = PulseSources(
            friends: sourcesDict["friends"] as? Bool ?? true,
            church: sourcesDict["church"] as? Bool ?? true,
            spaces: sourcesDict["spaces"] as? Bool ?? true,
            following: sourcesDict["following"] as? Bool ?? true,
            local: sourcesDict["local"] as? Bool ?? false,
            global: sourcesDict["global"] as? Bool ?? true
        )
        return PulsePrefs(
            interests: d["interests"] as? [String] ?? [],
            sources: sources,
            style: PulseStyle(rawValue: d["style"] as? String ?? "spiritual_first") ?? .spiritualFirst,
            maxCards: d["maxCards"] as? Int
        )
    }

    func updatePrefs(userId: String, prefs: PulsePrefs) async throws {
        var payload: [String: Any] = [
            "interests": prefs.interests,
            "style": prefs.style.rawValue,
            "sources": [
                "friends": prefs.sources.friends,
                "church": prefs.sources.church,
                "spaces": prefs.sources.spaces,
                "following": prefs.sources.following,
                "local": prefs.sources.local,
                "global": prefs.sources.global
            ],
            "updatedAt": Timestamp(date: Date())
        ]
        if let cap = prefs.maxCards { payload["maxCards"] = cap }
        try await prefsDoc(userId).setData(payload, merge: true)
    }

    func fetchWhatsNew(includeAdultOnly: Bool) async throws -> [WhatsNewStory] {
        // Global editorial collection. Minor-safety is ALSO enforced server-side in the
        // digest; client filtering here is defense-in-depth for the standalone archive.
        let snap = try await db.collection("whatsNewStories")
            .order(by: "publishedAt", descending: true)
            .limit(to: 50)
            .getDocuments()
        return snap.documents
            .compactMap { PulseDecode.story($0.data(), id: $0.documentID) }
            .filter { includeAdultOnly || $0.audience == .all }
    }

    func fetchStory(id: String) async throws -> WhatsNewStory? {
        let snap = try await db.collection("whatsNewStories").document(id).getDocument()
        guard let data = snap.data() else { return nil }
        return PulseDecode.story(data, id: id)
    }

    func fetchBookmarks(userId: String) async throws -> Set<String> {
        let snap = try await bookmarksCollection(userId).getDocuments()
        return Set(snap.documents.map(\.documentID))
    }

    func setBookmark(userId: String, storyId: String, bookmarked: Bool) async throws {
        let ref = bookmarksCollection(userId).document(storyId)
        if bookmarked {
            try await ref.setData(["storyId": storyId, "kind": "whatsNew", "createdAt": Timestamp(date: Date())], merge: true)
        } else {
            try await ref.delete()
        }
    }
}

// MARK: - Service façade

final class PulseService {
    static let shared = PulseService()

    private let provider: PulseProviding
    private let cacheDirectoryURL: URL
    private let functions = Functions.functions()

    init(provider: PulseProviding? = nil) {
        #if DEBUG
        self.provider = provider ?? FirestorePulseProvider()
        #else
        self.provider = provider ?? FirestorePulseProvider()
        #endif
        self.cacheDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("amenPulse", isDirectory: true)
    }

    func currentUserId() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw PulseServiceError.missingUser
        }
        return uid
    }

    /// Loads today's digest. On failure, falls back to the cached digest if present.
    func loadToday(date: Date = Date()) async throws -> PulseDigest {
        let userId = try currentUserId()
        let dateKey = Self.dateKey(for: date)
        do {
            if let digest = try await provider.fetchDigest(userId: userId, dateKey: dateKey) {
                try? cache(digest, userId: userId)
                return digest
            }
            // No doc yet — ask the backend to generate, then return a cached/empty shell.
            try? await triggerRefresh(dateKey: dateKey)
            if let cached = cachedDigest(userId: userId, dateKey: dateKey) { return cached }
            return PulseDigest(date: dateKey, cards: [])
        } catch {
            if let cached = cachedDigest(userId: userId, dateKey: dateKey) { return cached }
            throw error
        }
    }

    func observeToday(date: Date = Date()) throws -> AsyncStream<PulseDigest?> {
        let userId = try currentUserId()
        return provider.observeDigest(userId: userId, dateKey: Self.dateKey(for: date))
    }

    func loadPrefs() async throws -> PulsePrefs {
        try await provider.fetchPrefs(userId: try currentUserId())
    }

    func savePrefs(_ prefs: PulsePrefs) async throws {
        try await provider.updatePrefs(userId: try currentUserId(), prefs: prefs)
    }

    func loadWhatsNew(includeAdultOnly: Bool) async throws -> [WhatsNewStory] {
        try await provider.fetchWhatsNew(includeAdultOnly: includeAdultOnly)
    }

    func loadStory(id: String) async throws -> WhatsNewStory? {
        try await provider.fetchStory(id: id)
    }

    func loadBookmarks() async throws -> Set<String> {
        try await provider.fetchBookmarks(userId: try currentUserId())
    }

    func setBookmark(storyId: String, bookmarked: Bool) async throws {
        try await provider.setBookmark(userId: try currentUserId(), storyId: storyId, bookmarked: bookmarked)
    }

    func triggerRefresh(dateKey: String? = nil) async throws {
        let key = dateKey ?? Self.dateKey(for: Date())
        _ = try await functions.httpsCallable("refreshAmenPulseForCurrentUser").call(["dateKey": key])
    }

    // MARK: Cache

    func cachedDigest(userId: String, dateKey: String) -> PulseDigest? {
        guard let data = try? Data(contentsOf: cacheURL(userId, dateKey)) else { return nil }
        return try? JSONDecoder.pulse.decode(PulseDigest.self, from: data)
    }

    private func cache(_ digest: PulseDigest, userId: String) throws {
        try FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.pulse.encode(digest)
        // NG-3: per-user spiritual digest is sensitive — protect at rest.
        try data.write(to: cacheURL(userId, digest.date), options: [.atomic, .completeFileProtection])
    }

    private func cacheURL(_ userId: String, _ dateKey: String) -> URL {
        cacheDirectoryURL.appendingPathComponent("pulse_\(userId)_\(dateKey).json")
    }

    static func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

private extension JSONEncoder {
    static let pulse: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let pulse: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
