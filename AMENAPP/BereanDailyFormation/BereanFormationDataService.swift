// BereanFormationDataService.swift
// Loads BereanDailyFormation data from Firestore, gated on user consent.
// Mock data is only returned in DEBUG builds.

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class BereanFormationDataService: ObservableObject {

    static let shared = BereanFormationDataService()

    @Published var prefs: BereanFormationPrefs = BereanFormationDataService.loadPersistedPrefs()
    @Published var prayerList: [BereanPrayerItem] = []
    @Published var highlights: [BereanHighlight] = []
    @Published var memoryVerses: [BereanMemoryVerse] = []
    @Published var sanctuaries: [BereanSanctuary] = []
    @Published var isLoading: Bool = false

    private let db = Firestore.firestore()
    private init() {}

    // MARK: - Prefs persistence

    func savePrefs(_ newPrefs: BereanFormationPrefs) {
        prefs = newPrefs
        if let data = try? JSONEncoder().encode(PersistedPrefs(from: newPrefs)) {
            UserDefaults.standard.set(data, forKey: "bereanFormationPrefs_v1")
        }
    }

    static func loadPersistedPrefs() -> BereanFormationPrefs {
        guard let data = UserDefaults.standard.data(forKey: "bereanFormationPrefs_v1"),
              let stored = try? JSONDecoder().decode(PersistedPrefs.self, from: data) else {
            return BereanFormationPrefs(selectedTopics: ["verse", "prayer"], consents: [:])
        }
        return stored.toPrefs()
    }

    // MARK: - Load all user data

    func loadData() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        async let prayers   = loadPrayerItems(uid: uid)
        async let hiList    = loadHighlights(uid: uid)
        async let mvList    = loadMemoryVerses(uid: uid)
        async let sancList  = loadSanctuaries(uid: uid)
        let (p, h, mv, s) = await (prayers, hiList, mvList, sancList)
        prayerList   = p
        highlights   = h
        memoryVerses = mv
        sanctuaries  = s
    }

    // MARK: - Prayer items  (users/{uid}/prayers)

    private func loadPrayerItems(uid: String) async -> [BereanPrayerItem] {
        guard prefs.consents["prayerlist"] == true else {
#if DEBUG
            return BereanMockData.prayerList
#else
            return []
#endif
        }
        do {
            let snap = try await db
                .collection("users").document(uid)
                .collection("prayers")
                .whereField("status", in: ["active", "answered"])
                .limit(to: 20)
                .getDocuments()
            let items = snap.documents.compactMap { BereanPrayerItem(firestoreDoc: $0) }
            return items.isEmpty ? [] : items
        } catch { return [] }
    }

    // MARK: - Highlights  (users/{uid}/highlights)

    private func loadHighlights(uid: String) async -> [BereanHighlight] {
        guard prefs.consents["youversion"] == true else {
#if DEBUG
            return BereanMockData.highlights
#else
            return []
#endif
        }
        do {
            let snap = try await db
                .collection("users").document(uid)
                .collection("highlights")
                .order(by: "savedOn", descending: true)
                .limit(to: 10)
                .getDocuments()
            return snap.documents.compactMap { BereanHighlight(firestoreDoc: $0) }
        } catch { return [] }
    }

    // MARK: - Memory verses  (users/{uid}/memoryVerses)

    private func loadMemoryVerses(uid: String) async -> [BereanMemoryVerse] {
        do {
            let snap = try await db
                .collection("users").document(uid)
                .collection("memoryVerses")
                .limit(to: 20)
                .getDocuments()
            return snap.documents.compactMap { BereanMemoryVerse(firestoreDoc: $0) }
        } catch { return [] }
    }

    // MARK: - Sanctuaries  (sanctuaries where memberUIDs contains uid)

    private func loadSanctuaries(uid: String) async -> [BereanSanctuary] {
        guard prefs.consents["sanctuary"] == true else {
#if DEBUG
            return BereanMockData.sanctuaries
#else
            return []
#endif
        }
        do {
            let snap = try await db
                .collection("sanctuaries")
                .whereField("memberUIDs", arrayContains: uid)
                .limit(to: 5)
                .getDocuments()
            return snap.documents.compactMap { BereanSanctuary(firestoreDoc: $0) }
        } catch { return [] }
    }

    // MARK: - Codable storage

    private struct PersistedPrefs: Codable {
        let selectedTopics: [String]
        let consents: [String: Bool]

        init(from prefs: BereanFormationPrefs) {
            selectedTopics = Array(prefs.selectedTopics)
            consents = prefs.consents
        }

        func toPrefs() -> BereanFormationPrefs {
            BereanFormationPrefs(selectedTopics: Set(selectedTopics), consents: consents)
        }
    }
}

// MARK: - Firestore document initialisers

extension BereanPrayerItem {
    init?(firestoreDoc doc: DocumentSnapshot) {
        guard let d = doc.data(),
              let subject  = d["subject"]  as? String,
              let forWhom  = d["forWhom"]  as? String,
              let prayedOn = d["prayedOn"] as? String,
              let status   = d["status"]   as? String else { return nil }
        let sens = BereanPrayerSensitivity(rawValue: d["sensitivity"] as? String ?? "normal") ?? .normal
        self.init(id: doc.documentID, subject: subject, forWhom: forWhom,
                  prayedOn: prayedOn, status: status, sensitivity: sens)
    }
}

extension BereanHighlight {
    init?(firestoreDoc doc: DocumentSnapshot) {
        guard let d       = doc.data(),
              let verseRef = d["verseRef"] as? String,
              let note     = d["note"]     as? String,
              let savedOn  = d["savedOn"]  as? String else { return nil }
        self.init(id: doc.documentID, verseRef: verseRef, note: note, savedOn: savedOn)
    }
}

extension BereanMemoryVerse {
    init?(firestoreDoc doc: DocumentSnapshot) {
        guard let d         = doc.data(),
              let verseRef  = d["verseRef"]   as? String,
              let srsDate   = d["srsDueDate"] as? String,
              let strength  = d["strength"]   as? Double,
              let streak    = d["streak"]     as? Int else { return nil }
        self.init(id: doc.documentID, verseRef: verseRef, srsDueDate: srsDate,
                  strength: strength, streak: streak)
    }
}

extension BereanSanctuary {
    init?(firestoreDoc doc: DocumentSnapshot) {
        guard let d    = doc.data(),
              let name = d["name"] as? String else { return nil }
        self.init(
            id: doc.documentID, name: name,
            openPrayerRequests: d["openPrayerRequests"] as? Int ?? 0,
            activeThreads:      d["activeThreads"]      as? Int ?? 0,
            recentActivity:     d["recentActivity"]     as? String ?? "Active community"
        )
    }
}
