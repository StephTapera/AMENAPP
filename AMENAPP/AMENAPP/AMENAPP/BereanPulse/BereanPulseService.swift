import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

protocol BereanPulseProviding {
    func fetchCards(userId: String, dateKey: String) async throws -> [BereanPulseCard]
    func observeCards(userId: String, dateKey: String) -> AsyncStream<[BereanPulseCard]>
    func fetchPreferences(userId: String) async throws -> BereanPulsePreference
    func fetchSavedCards(userId: String) async throws -> Set<String>
    func updatePreferences(userId: String, preference: BereanPulsePreference) async throws
    func saveCard(userId: String, card: BereanPulseCard) async throws
    func unsaveCard(userId: String, cardId: String) async throws
    func hideCard(userId: String, cardId: String) async throws
    func trackEvent(userId: String, event: BereanPulseEvent) async throws
}

enum BereanPulseServiceError: LocalizedError {
    case missingUser

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return String(localized: "Berean Pulse needs a signed-in user.")
        }
    }
}

struct FirestoreBereanPulseProvider: BereanPulseProviding {
    private let db = Firestore.firestore()

    func fetchCards(userId: String, dateKey: String) async throws -> [BereanPulseCard] {
        let snapshot = try await cardsCollection(userId: userId, dateKey: dateKey).getDocuments()
        return snapshot.documents.compactMap(Self.decodeCard)
    }

    func observeCards(userId: String, dateKey: String) -> AsyncStream<[BereanPulseCard]> {
        AsyncStream { continuation in
            let listener = cardsCollection(userId: userId, dateKey: dateKey)
                .addSnapshotListener { snapshot, _ in
                    let cards = snapshot?.documents.compactMap(Self.decodeCard) ?? []
                    continuation.yield(cards)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func fetchPreferences(userId: String) async throws -> BereanPulsePreference {
        let document = try await preferencesDocument(userId: userId).getDocument()
        guard let data = document.data() else {
            return .default
        }
        return Self.decodePreference(data) ?? .default
    }

    func fetchSavedCards(userId: String) async throws -> Set<String> {
        let snapshot = try await savedCardsCollection(userId: userId).getDocuments()
        return Set(snapshot.documents.map(\.documentID))
    }

    func updatePreferences(userId: String, preference: BereanPulsePreference) async throws {
        try await preferencesDocument(userId: userId)
            .setData(Self.encodePreference(preference), merge: true)
    }

    func saveCard(userId: String, card: BereanPulseCard) async throws {
        try await savedCardsCollection(userId: userId)
            .document(card.id)
            .setData([
                "cardId": card.id,
                "mode": card.mode.rawValue,
                "title": card.title,
                "savedAt": Timestamp(date: Date())
            ], merge: true)
    }

    func unsaveCard(userId: String, cardId: String) async throws {
        try await savedCardsCollection(userId: userId)
            .document(cardId)
            .delete()
    }

    func hideCard(userId: String, cardId: String) async throws {
        let todayKey = BereanPulseService.dateKey(for: Date())
        try await cardsCollection(userId: userId, dateKey: todayKey)
            .document(cardId)
            .setData(["isHidden": true, "updatedAt": Timestamp(date: Date())], merge: true)
    }

    func trackEvent(userId: String, event: BereanPulseEvent) async throws {
        try await eventsCollection(userId: userId)
            .document(event.id)
            .setData([
                "cardId": event.cardId,
                "eventType": event.eventType.rawValue,
                "mode": event.mode.rawValue,
                "timestamp": Timestamp(date: event.timestamp),
                "metadata": event.metadata
            ], merge: true)
    }

    private func cardsCollection(userId: String, dateKey: String) -> CollectionReference {
        db.collection("users")
            .document(userId)
            .collection("bereanPulse")
            .document("main")
            .collection("days")
            .document(dateKey)
            .collection("cards")
    }

    private func preferencesDocument(userId: String) -> DocumentReference {
        db.collection("users")
            .document(userId)
            .collection("bereanPulse")
            .document("main")
            .collection("preferences")
            .document("main")
    }

    private func eventsCollection(userId: String) -> CollectionReference {
        db.collection("users")
            .document(userId)
            .collection("bereanPulse")
            .document("main")
            .collection("events")
    }

    private func savedCardsCollection(userId: String) -> CollectionReference {
        db.collection("users")
            .document(userId)
            .collection("bereanPulse")
            .document("main")
            .collection("savedCards")
    }

    nonisolated private static func decodeCard(document: QueryDocumentSnapshot) -> BereanPulseCard? {
        let data = document.data()
        let signals = (data["sourceSignals"] as? [[String: Any]] ?? []).compactMap(decodeSignal)
        return BereanPulseCard(
            id: document.documentID,
            userId: data["userId"] as? String ?? "",
            dateKey: data["dateKey"] as? String ?? "",
            mode: BereanPulseMode(rawValue: data["mode"] as? String ?? "") ?? .all,
            secondaryModes: (data["secondaryModes"] as? [String] ?? []).compactMap(BereanPulseMode.init(rawValue:)),
            title: data["title"] as? String ?? "",
            subtitle: data["subtitle"] as? String ?? "",
            whyNow: data["whyNow"] as? String ?? "",
            whyNowEvidence: data["whyNowEvidence"] as? [String] ?? [],
            insight: data["insight"] as? String ?? "",
            expandedBody: data["expandedBody"] as? String ?? "",
            recommendedActionTitle: data["recommendedActionTitle"] as? String ?? "",
            actionType: BereanPulseActionType(rawValue: data["actionType"] as? String ?? "") ?? .askBerean,
            actionPayload: data["actionPayload"] as? [String: String] ?? [:],
            primaryIntent: data["primaryIntent"] as? String ?? "",
            sourceSignalIds: data["sourceSignalIds"] as? [String] ?? [],
            confidenceScore: data["confidenceScore"] as? Double ?? 0,
            urgencyScore: data["urgencyScore"] as? Double ?? 0,
            relevanceScore: data["relevanceScore"] as? Double ?? 0,
            matchScore: data["matchScore"] as? Double ?? 0,
            sourceSignals: signals,
            permissionRequirements: (data["permissionRequirements"] as? [String] ?? []).compactMap(BereanPulsePermissionSource.init(rawValue:)),
            privacyLevel: BereanPulsePrivacyLevel(rawValue: data["privacyLevel"] as? String ?? "") ?? .low,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue(),
            isSaved: data["isSaved"] as? Bool ?? false,
            isHidden: data["isHidden"] as? Bool ?? false,
            feedbackState: BereanPulseFeedbackState(rawValue: data["feedbackState"] as? String ?? "") ?? .neutral
        )
    }

    nonisolated private static func decodeSignal(data: [String: Any]) -> BereanPulseSignal? {
        guard let id = data["id"] as? String else { return nil }
        let granted = data["permissionGranted"] as? Bool ?? false
        return BereanPulseSignal(
            id: id,
            source: BereanPulsePermissionSource(rawValue: data["source"] as? String ?? "") ?? .amenActivity,
            sourceRecordId: data["sourceRecordId"] as? String ?? "",
            title: data["title"] as? String ?? "",
            summary: data["summary"] as? String ?? "",
            timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
            sensitivity: BereanPulseSignalSensitivity(rawValue: data["sensitivity"] as? String ?? "") ?? .low,
            permissionRequired: data["permissionRequired"] as? Bool ?? false,
            permissionGranted: granted,
            permissionStatus: BereanPulsePermissionStatus(rawValue: data["permissionStatus"] as? String ?? "") ?? (granted ? .granted : .notRequested),
            hashForDeduplication: data["hashForDeduplication"] as? String ?? id,
            isUserVisible: data["isUserVisible"] as? Bool ?? true,
            entityType: data["entityType"] as? String,
            entityId: data["entityId"] as? String,
            metadata: data["metadata"] as? [String: String] ?? [:]
        )
    }

    nonisolated private static func decodePreference(_ data: [String: Any]) -> BereanPulsePreference? {
        BereanPulsePreference(
            enabled: data["enabled"] as? Bool ?? true,
            preferredModes: (data["preferredModes"] as? [String] ?? []).compactMap(BereanPulseMode.init(rawValue:)),
            suppressedModes: (data["suppressedModes"] as? [String] ?? []).compactMap(BereanPulseMode.init(rawValue:)),
            preferredTone: BereanPulsePreferredTone(rawValue: data["preferredTone"] as? String ?? "") ?? .strategic,
            preferredLength: BereanPulsePreferredLength(rawValue: data["preferredLength"] as? String ?? "") ?? .balanced,
            morningDeliveryEnabled: data["morningDeliveryEnabled"] as? Bool ?? false,
            notificationsEnabled: data["notificationsEnabled"] as? Bool ?? false,
            appContextAccess: data["appContextAccess"] as? Bool ?? true,
            calendarAccess: data["calendarAccess"] as? Bool ?? false,
            locationAccess: data["locationAccess"] as? Bool ?? false,
            healthAccess: data["healthAccess"] as? Bool ?? false,
            contactsAccess: data["contactsAccess"] as? Bool ?? false,
            churchActivityAccess: data["churchActivityAccess"] as? Bool ?? true,
            prayerJournalAccess: data["prayerJournalAccess"] as? Bool ?? false,
            savedPostsAccess: data["savedPostsAccess"] as? Bool ?? true,
            workModeEnabled: data["workModeEnabled"] as? Bool ?? true
        )
    }

    nonisolated private static func encodePreference(_ preference: BereanPulsePreference) -> [String: Any] {
        [
            "enabled": preference.enabled,
            "preferredModes": preference.preferredModes.map(\.rawValue),
            "suppressedModes": preference.suppressedModes.map(\.rawValue),
            "preferredTone": preference.preferredTone.rawValue,
            "preferredLength": preference.preferredLength.rawValue,
            "morningDeliveryEnabled": preference.morningDeliveryEnabled,
            "notificationsEnabled": preference.notificationsEnabled,
            "appContextAccess": preference.appContextAccess,
            "calendarAccess": preference.calendarAccess,
            "locationAccess": preference.locationAccess,
            "healthAccess": preference.healthAccess,
            "contactsAccess": preference.contactsAccess,
            "churchActivityAccess": preference.churchActivityAccess,
            "prayerJournalAccess": preference.prayerJournalAccess,
            "savedPostsAccess": preference.savedPostsAccess,
            "workModeEnabled": preference.workModeEnabled
        ]
    }
}

#if DEBUG
struct MockBereanPulseProvider: BereanPulseProviding {
    func fetchCards(userId: String, dateKey: String) async throws -> [BereanPulseCard] {
        Self.seedCards(userId: userId, dateKey: dateKey)
    }

    func observeCards(userId: String, dateKey: String) -> AsyncStream<[BereanPulseCard]> {
        AsyncStream { continuation in
            continuation.yield(Self.seedCards(userId: userId, dateKey: dateKey))
            continuation.finish()
        }
    }

    func fetchPreferences(userId: String) async throws -> BereanPulsePreference {
        .default
    }

    func fetchSavedCards(userId: String) async throws -> Set<String> {
        []
    }

    func updatePreferences(userId: String, preference: BereanPulsePreference) async throws {}
    func saveCard(userId: String, card: BereanPulseCard) async throws {}
    func unsaveCard(userId: String, cardId: String) async throws {}
    func hideCard(userId: String, cardId: String) async throws {}
    func trackEvent(userId: String, event: BereanPulseEvent) async throws {}

    static func seedCards(userId: String, dateKey: String) -> [BereanPulseCard] {
        let now = Date()
        let signals: [BereanPulseSignal] = [
            .init(id: "signal_founder", source: .amenActivity, sourceRecordId: "founder", title: String(localized: "AMEN product momentum"), summary: String(localized: "You have been refining discovery, church flows, and Berean surfaces this week."), timestamp: now.addingTimeInterval(-3600), sensitivity: .low, permissionRequired: false, permissionGranted: true, permissionStatus: .granted, hashForDeduplication: "founder", isUserVisible: true, entityType: "project", entityId: "preview_project", metadata: [:]),
            .init(id: "signal_scripture", source: .bereanChatHistory, sourceRecordId: "scripture", title: String(localized: "Scripture continuity"), summary: String(localized: "Recent Berean sessions leaned toward wisdom, discernment, and practical application."), timestamp: now.addingTimeInterval(-7200), sensitivity: .personal, permissionRequired: true, permissionGranted: false, permissionStatus: .notRequested, hashForDeduplication: "scripture", isUserVisible: true, entityType: "conversation", entityId: "preview_conversation", metadata: [:]),
            .init(id: "signal_open_loop", source: .appUsageBehavior, sourceRecordId: "open_loop", title: String(localized: "Open loops"), summary: String(localized: "You have unresolved product and follow-up threads that can be continued in one tap."), timestamp: now.addingTimeInterval(-1800), sensitivity: .low, permissionRequired: false, permissionGranted: true, permissionStatus: .granted, hashForDeduplication: "open_loop", isUserVisible: true, entityType: "project", entityId: "preview_project", metadata: ["openLoop": "true"]),
            .init(id: "signal_church", source: .location, sourceRecordId: "church", title: String(localized: "Nearby church help"), summary: String(localized: "Location can help Berean prepare nearby church and Sunday prompts when you allow it."), timestamp: now.addingTimeInterval(-5400), sensitivity: .personal, permissionRequired: true, permissionGranted: false, permissionStatus: .notRequested, hashForDeduplication: "church", isUserVisible: true, entityType: "church", entityId: "preview_church", metadata: [:])
        ]

        func card(
            id: String,
            mode: BereanPulseMode,
            secondary: [BereanPulseMode],
            title: String,
            subtitle: String,
            whyNow: String,
            insight: String,
            expandedBody: String,
            action: String,
            actionType: BereanPulseActionType,
            payload: [String: String],
            match: Double,
            urgency: Double,
            relevance: Double,
            permissions: [BereanPulsePermissionSource],
            privacy: BereanPulsePrivacyLevel,
            sourceSignals: [BereanPulseSignal]
        ) -> BereanPulseCard {
            BereanPulseCard(
                id: id,
                userId: userId,
                dateKey: dateKey,
                mode: mode,
                secondaryModes: secondary,
                title: title,
                subtitle: subtitle,
                whyNow: whyNow,
                whyNowEvidence: sourceSignals.map(\.summary),
                insight: insight,
                expandedBody: expandedBody,
                recommendedActionTitle: action,
                actionType: actionType,
                actionPayload: payload,
                primaryIntent: mode.rawValue,
                sourceSignalIds: sourceSignals.map(\.id),
                confidenceScore: 0.82,
                urgencyScore: urgency,
                relevanceScore: relevance,
                matchScore: match,
                sourceSignals: sourceSignals,
                permissionRequirements: permissions,
                privacyLevel: privacy,
                createdAt: now,
                updatedAt: now,
                expiresAt: Calendar.current.date(byAdding: .day, value: 1, to: now),
                isSaved: false,
                isHidden: false,
                feedbackState: .neutral
            )
        }

        return [
            card(
                id: "pulse_founder",
                mode: .founder,
                secondary: [.creative, .work],
                title: String(localized: "AMEN Product Priority"),
                subtitle: String(localized: "Founder brief"),
                whyNow: String(localized: "You have been refining discovery, church intelligence, and Berean surfaces. The next leverage point is shipping stronger production wiring before more polish."),
                insight: String(localized: "Berean Pulse should help you close the gap between design direction and trustworthy product execution."),
                expandedBody: String(localized: "Focus on the unglamorous layer first: routing, permissions, telemetry, saved state, and explainable intelligence. That is where trust compounds."),
                action: String(localized: "Continue in chat"),
                actionType: .continueChat,
                payload: ["prompt": "Continue the founder brief and turn it into a concrete AMEN execution plan.", "mode": "strategist"],
                match: 0.94,
                urgency: 0.88,
                relevance: 0.92,
                permissions: [.amenActivity],
                privacy: .low,
                sourceSignals: [signals[0], signals[2]]
            ),
            card(
                id: "pulse_spiritual",
                mode: .spiritual,
                secondary: [.prayer, .learning],
                title: String(localized: "Wisdom Into One Decision"),
                subtitle: String(localized: "Spiritual next step"),
                whyNow: String(localized: "Recent scripture questions have been practical, not abstract. Today’s next step is one applied act of wisdom."),
                insight: String(localized: "Berean can turn study into a concrete response instead of another passive reading session."),
                expandedBody: String(localized: "Review one decision you are moving through too quickly. Ask Berean to connect Proverbs, motive, pace, and obedience in a way you can apply before noon."),
                action: String(localized: "Ask Berean"),
                actionType: .askBerean,
                payload: ["prompt": "Help me apply recent wisdom themes to one concrete decision today.", "mode": "shepherd"],
                match: 0.91,
                urgency: 0.76,
                relevance: 0.89,
                permissions: [.bereanChatHistory],
                privacy: .personal,
                sourceSignals: [signals[1]]
            ),
            card(
                id: "pulse_open_loops",
                mode: .openLoops,
                secondary: [.work, .business],
                title: String(localized: "Unfinished AMEN Threads"),
                subtitle: String(localized: "Open-loop continuation"),
                whyNow: String(localized: "Several product threads are partially designed but not fully operational. Pulse can pull the next concrete continuation forward."),
                insight: String(localized: "Open-loop detection is where Berean starts feeling proactive instead of reactive."),
                expandedBody: String(localized: "Use this card when you need the next implementation block, owner question, or follow-up message without digging through old sessions manually."),
                action: String(localized: "Review open loops"),
                actionType: .askBerean,
                payload: ["prompt": "Review my open product and work loops and help me prioritize what to close first.", "mode": "strategist"],
                match: 0.95,
                urgency: 0.9,
                relevance: 0.93,
                permissions: [.appUsageBehavior],
                privacy: .low,
                sourceSignals: [signals[2]]
            ),
            card(
                id: "pulse_church",
                mode: .church,
                secondary: [.relationships, .prayer],
                title: String(localized: "Prepare for Sunday Near You"),
                subtitle: String(localized: "Church discovery prompt"),
                whyNow: String(localized: "Berean can connect church discovery with your next likely Sunday step, but only after you allow location."),
                insight: String(localized: "Pulse should not guess with private location data. It should ask at the moment of value and still offer a limited version if you decline."),
                expandedBody: String(localized: "Without location, you can still search manually. With location, Berean can rank nearby churches, travel friction, and service timing more intelligently."),
                action: String(localized: "Allow location for nearby churches"),
                actionType: .openFindChurch,
                payload: [:],
                match: 0.84,
                urgency: 0.7,
                relevance: 0.81,
                permissions: [.location],
                privacy: .personal,
                sourceSignals: [signals[3]]
            )
        ]
    }
}
#endif

final class BereanPulseService {
    private let provider: BereanPulseProviding
    private let cacheDirectoryURL: URL
    private let functions = Functions.functions()

    init(provider: BereanPulseProviding? = nil) {
        self.provider = provider ?? FirestoreBereanPulseProvider()
        self.cacheDirectoryURL = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("bereanPulse", isDirectory: true)
    }

    func currentUserId() throws -> String {
        guard let userId = Auth.auth().currentUser?.uid, !userId.isEmpty else {
            throw BereanPulseServiceError.missingUser
        }
        return userId
    }

    func loadToday(date: Date = Date()) async throws -> BereanPulseDaySnapshot {
        let userId = try currentUserId()
        let dateKey = Self.dateKey(for: date)

        do {
            async let cardsTask = provider.fetchCards(userId: userId, dateKey: dateKey)
            async let preferencesTask = provider.fetchPreferences(userId: userId)
            async let savedTask = provider.fetchSavedCards(userId: userId)

            var cards = try await cardsTask
            let preferences = try await preferencesTask
            let saved = try await savedTask
            cards = cards.map {
                var mutable = $0
                mutable.isSaved = saved.contains(mutable.id) || mutable.isSaved
                return mutable
            }
            let signals = Array(Set(cards.flatMap(\.sourceSignals))).sorted { $0.timestamp > $1.timestamp }
            let snapshot = BereanPulseDaySnapshot(cards: cards, signals: signals, preferences: preferences, fetchedAt: Date(), source: .live, userId: userId, dateKey: dateKey)
            try cache(snapshot: snapshot)
            return snapshot
        } catch {
            if let cached = cachedSnapshot(userId: userId, dateKey: dateKey) {
                return cached
            }
            throw error
        }
    }

    func observeToday(date: Date = Date()) async throws -> AsyncStream<[BereanPulseCard]> {
        let userId = try currentUserId()
        return provider.observeCards(userId: userId, dateKey: Self.dateKey(for: date))
    }

    func save(card: BereanPulseCard) async throws {
        let userId = try currentUserId()
        try await provider.saveCard(userId: userId, card: card)
    }

    func unsave(cardId: String) async throws {
        let userId = try currentUserId()
        try await provider.unsaveCard(userId: userId, cardId: cardId)
    }

    func hide(cardId: String) async throws {
        let userId = try currentUserId()
        try await provider.hideCard(userId: userId, cardId: cardId)
    }

    func updatePreferences(_ preference: BereanPulsePreference) async throws {
        let userId = try currentUserId()
        try await provider.updatePreferences(userId: userId, preference: preference)
    }

    func triggerOnDemandRefresh(dateKey: String? = nil) async throws {
        let key = dateKey ?? Self.dateKey(for: Date())
        _ = try await functions.httpsCallable("refreshBereanPulseForCurrentUser").call(["dateKey": key])
    }

    func track(_ event: BereanPulseEvent) async {
        do {
            let userId = try currentUserId()
            try await provider.trackEvent(userId: userId, event: event)
        } catch {
            // Keep event tracking non-blocking on the UI path.
        }
    }

    func cachedSnapshot(userId: String, dateKey: String) -> BereanPulseDaySnapshot? {
        let cacheURL = cacheURL(for: userId, dateKey: dateKey)
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(BereanPulseDaySnapshot.self, from: data)
    }

    private func cache(snapshot: BereanPulseDaySnapshot) throws {
        try FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        let cacheURL = self.cacheURL(for: snapshot.userId, dateKey: snapshot.dateKey)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: cacheURL, options: .atomic)
    }

    private func cacheURL(for userId: String, dateKey: String) -> URL {
        cacheDirectoryURL.appendingPathComponent("pulse_\(userId)_\(dateKey).json")
    }

    static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
