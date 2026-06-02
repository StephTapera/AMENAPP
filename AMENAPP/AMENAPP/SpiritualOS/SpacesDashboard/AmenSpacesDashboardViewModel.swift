// AmenSpacesDashboardViewModel.swift
// AMEN Spiritual OS — Agent D: Spaces Dashboard HeroCard
// ViewModel for the Space detail hero card surface.
// Built 2026-06-02 — do not copy types; import SharedComponents instead.

import Foundation
import FirebaseFirestore
import SwiftUI

// MARK: - SpaceDashboardEvent

struct SpaceDashboardEvent: Identifiable {
    let id: String
    let title: String
    let date: Date
}

// MARK: - AmenSpacesDashboardViewModel

@MainActor
final class AmenSpacesDashboardViewModel: ObservableObject {

    // MARK: Published state

    @Published var spaceTitle: String = ""
    @Published var spaceSubtitle: String = ""
    @Published var coverImageURL: URL? = nil
    @Published var memberAvatarURLs: [URL] = []
    @Published var memberCount: Int = 0
    @Published var nextEvent: SpaceDashboardEvent? = nil
    @Published var activePrayerCount: Int = 0
    @Published var currentStudySeries: String? = nil
    @Published var heroCardEnabled: Bool = false
    @Published var isLoading: Bool = false

    // MARK: Private

    private let spaceId: String
    private let db = Firestore.firestore()

    // MARK: Init

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    // MARK: Load

    /// Reads space data from Firestore `spaces/{spaceId}` and its `members` subcollection.
    /// All errors are swallowed gracefully — missing fields leave published defaults intact.
    func load() async {
        guard !spaceId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        await loadSpaceDocument()
        await loadMemberAvatars()
    }

    // MARK: - Private helpers

    private func loadSpaceDocument() async {
        do {
            let doc = try await db
                .collection("spaces")
                .document(spaceId)
                .getDocument()

            guard let data = doc.data() else { return }

            // Feature gate: per-space hero card toggle
            heroCardEnabled = data["heroCardEnabled"] as? Bool ?? false

            // Space identity
            if let name = data["name"] as? String {
                spaceTitle = name
            }

            // Cover image
            if let coverString = data["coverImageURL"] as? String,
               let url = URL(string: coverString) {
                coverImageURL = url
            }

            // Member count → subtitle
            if let count = data["memberCount"] as? Int {
                memberCount = count
                let noun = count == 1 ? "member" : "members"
                spaceSubtitle = "\(count) \(noun)"
            }

            // Pastoral signal: active prayer count (private — NOT shown as social metric)
            activePrayerCount = data["activePrayerCount"] as? Int ?? 0

            // Current study series label
            if let series = data["currentStudySeries"] as? String, !series.isEmpty {
                currentStudySeries = series
            }

            // Next event
            nextEvent = extractNextEvent(from: data)

        } catch {
            // Firestore read failure — leave defaults; hero card stays hidden via heroCardEnabled=false
        }
    }

    private func loadMemberAvatars() async {
        do {
            let snapshot = try await db
                .collection("spaces")
                .document(spaceId)
                .collection("members")
                .limit(to: 5)
                .getDocuments()

            memberAvatarURLs = snapshot.documents.compactMap { doc in
                guard let photoString = doc.data()["photoURL"] as? String else { return nil }
                return URL(string: photoString)
            }
        } catch {
            // Avatars are decorative — failure is silent
        }
    }

    /// Extracts the soonest upcoming event from the Firestore document.
    /// Supports both an embedded `nextEvent` map and a top-level `nextEventTimestamp` field.
    private func extractNextEvent(from data: [String: Any]) -> SpaceDashboardEvent? {
        // Preferred shape: nextEvent: { id, title, timestamp }
        if let map = data["nextEvent"] as? [String: Any] {
            let id = map["id"] as? String ?? UUID().uuidString
            let title = map["title"] as? String ?? ""
            let timestamp = (map["timestamp"] as? Timestamp)?.dateValue() ?? Date()
            guard !title.isEmpty else { return nil }
            return SpaceDashboardEvent(id: id, title: title, date: timestamp)
        }

        // Fallback shape: separate nextEventTitle + nextEventTimestamp fields
        if let title = data["nextEventTitle"] as? String,
           !title.isEmpty,
           let timestamp = (data["nextEventTimestamp"] as? Timestamp)?.dateValue() {
            return SpaceDashboardEvent(id: UUID().uuidString, title: title, date: timestamp)
        }

        return nil
    }

    // MARK: - Actions builder

    /// Returns the 4 standard HeroCard actions for the Spaces Dashboard surface.
    /// Callers supply closures so navigation ownership stays in the view layer.
    func buildActions(
        onPrayTogether: @escaping () -> Void,
        onSchedule: @escaping () -> Void,
        onOpenNotes: @escaping () -> Void,
        onAskBerean: @escaping () -> Void
    ) -> [HeroCardAction] {
        [
            HeroCardAction(label: "Pray Together", icon: "hands.sparkles", action: onPrayTogether),
            HeroCardAction(label: "Schedule",      icon: "calendar.badge.plus", action: onSchedule),
            HeroCardAction(label: "Open Notes",    icon: "doc.text",        action: onOpenNotes),
            HeroCardAction(label: "Ask Berean",    icon: "sparkles",        action: onAskBerean)
        ]
    }
}
