// AmenDiscoveryRailsViewModel.swift
// AMEN App — Spiritual OS / Community Discovery
//
// @Observable view model that loads all discovery rails in parallel from Firestore.
// Each rail fails independently — a single broken query never blocks the rest.
//
// Feature flag: amen_discovery_rails_enabled (AppStorage, default OFF).
//   false → load() exits immediately; rails stays empty; zero Firestore reads.

import Foundation
import Observation
import FirebaseFirestore
import SwiftUI

// MARK: - AmenDiscoveryRailsViewModel

@Observable
@MainActor
final class AmenDiscoveryRailsViewModel {

    // MARK: Published state

    var rails: [DiscoveryRail] = []
    var isLoading = false
    var error: String? = nil

    // MARK: Private

    @ObservationIgnored private let db = Firestore.firestore()
    private var currentUserId: String = ""

    // MARK: Load
    // Feature flag `amen_discovery_rails_enabled` is checked by the view before calling load().

    func load(userId: String) async {
        guard !userId.isEmpty else { return }
        currentUserId = userId
        isLoading = true
        error = nil

        // Fetch all rails in parallel; each returns an optional DiscoveryRail.
        async let journey      = fetchContinueJourney(userId: userId)
        async let mentors      = fetchRecommendedMentors()
        async let spaces       = fetchActiveSpaces()
        async let churches     = fetchChurchesNearYou()
        async let events       = fetchUpcomingEvents()
        async let studies      = fetchFeaturedStudies()
        async let people       = fetchPeopleYouShouldMeet(userId: userId)
        async let prayerSpaces = fetchPrayerCommunities()
        async let newSpaces    = fetchNewCommunities()
        async let notes        = fetchChurchNotes()

        let results = await [
            journey,
            mentors,
            spaces,
            churches,
            events,
            studies,
            people,
            prayerSpaces,
            newSpaces,
            notes
        ]

        rails = results.compactMap { $0 }.filter { !$0.items.isEmpty }
        isLoading = false
    }

    // MARK: - Rail fetchers

    private func fetchContinueJourney(userId: String) async -> DiscoveryRail? {
        do {
            let snapshot = try await db
                .collection("journeyProgress")
                .document(userId)
                .collection("items")
                .order(by: "lastAccessedAt", descending: true)
                .limit(to: 8)
                .getDocuments()

            let items = snapshot.documents.compactMap { doc -> DiscoveryRailItem? in
                let data = doc.data()
                let title = data["title"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                let progress = data["progressFraction"] as? Double
                let imageURLString = data["imageURL"] as? String
                return DiscoveryRailItem(
                    id: doc.documentID,
                    type: .study,
                    title: title,
                    subtitle: data["subtitle"] as? String,
                    imageURL: imageURLString.flatMap { URL(string: $0) },
                    badgeText: nil,
                    progressFraction: progress,
                    metadata: [:]
                )
            }

            return DiscoveryRail(
                id: DiscoveryRailType.continueJourney.rawValue,
                type: .continueJourney,
                items: items,
                loadedAt: .now
            )
        } catch {
            return nil
        }
    }

    private func fetchRecommendedMentors() async -> DiscoveryRail? {
        do {
            let snapshot = try await db
                .collection("mentors")
                .whereField("active", isEqualTo: true)
                .limit(to: 8)
                .getDocuments()

            let items = snapshot.documents.compactMap { doc -> DiscoveryRailItem? in
                let data = doc.data()
                let title = data["displayName"] as? String ?? data["name"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                let imageURLString = data["photoURL"] as? String ?? data["imageURL"] as? String
                let specialty = data["specialty"] as? String
                return DiscoveryRailItem(
                    id: doc.documentID,
                    type: .mentor,
                    title: title,
                    subtitle: specialty,
                    imageURL: imageURLString.flatMap { URL(string: $0) },
                    badgeText: data["isLive"] as? Bool == true ? "Live" : nil,
                    progressFraction: nil,
                    metadata: ["mentorId": doc.documentID]
                )
            }

            return DiscoveryRail(
                id: DiscoveryRailType.recommendedMentors.rawValue,
                type: .recommendedMentors,
                items: items,
                loadedAt: .now
            )
        } catch {
            return nil
        }
    }

    private func fetchActiveSpaces() async -> DiscoveryRail? {
        do {
            let snapshot = try await db
                .collection("spaces")
                .whereField("memberCount", isGreaterThan: 10)
                .order(by: "lastActivityAt", descending: true)
                .limit(to: 10)
                .getDocuments()

            let items = snapshot.documents.compactMap { doc -> DiscoveryRailItem? in
                let data = doc.data()
                let title = data["name"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                let imageURLString = data["imageURL"] as? String ?? data["coverImageURL"] as? String
                return DiscoveryRailItem(
                    id: doc.documentID,
                    type: .space,
                    title: title,
                    subtitle: data["description"] as? String,
                    imageURL: imageURLString.flatMap { URL(string: $0) },
                    badgeText: nil,
                    progressFraction: nil,
                    metadata: ["spaceId": doc.documentID]
                )
            }

            return DiscoveryRail(
                id: DiscoveryRailType.activeSpaces.rawValue,
                type: .activeSpaces,
                items: items,
                loadedAt: .now
            )
        } catch {
            return nil
        }
    }

    private func fetchChurchesNearYou() async -> DiscoveryRail? {
        do {
            let snapshot = try await db
                .collection("churches")
                .whereField("verified", isEqualTo: true)
                .limit(to: 8)
                .getDocuments()

            let items = snapshot.documents.compactMap { doc -> DiscoveryRailItem? in
                let data = doc.data()
                let title = data["name"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                let imageURLString = data["imageURL"] as? String ?? data["logoURL"] as? String
                let city = data["city"] as? String
                return DiscoveryRailItem(
                    id: doc.documentID,
                    type: .church,
                    title: title,
                    subtitle: city,
                    imageURL: imageURLString.flatMap { URL(string: $0) },
                    badgeText: data["isVerified"] as? Bool == true ? "Verified" : nil,
                    progressFraction: nil,
                    metadata: ["churchId": doc.documentID]
                )
            }

            return DiscoveryRail(
                id: DiscoveryRailType.churchesNearYou.rawValue,
                type: .churchesNearYou,
                items: items,
                loadedAt: .now
            )
        } catch {
            return nil
        }
    }

    private func fetchUpcomingEvents() async -> DiscoveryRail? {
        do {
            let now = Timestamp(date: Date())
            let snapshot = try await db
                .collection("events")
                .whereField("startDate", isGreaterThan: now)
                .order(by: "startDate", descending: false)
                .limit(to: 8)
                .getDocuments()

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"

            let items = snapshot.documents.compactMap { doc -> DiscoveryRailItem? in
                let data = doc.data()
                let title = data["title"] as? String ?? data["name"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                let imageURLString = data["imageURL"] as? String ?? data["bannerURL"] as? String
                var badgeText: String? = nil
                if let startTs = data["startDate"] as? Timestamp {
                    badgeText = dateFormatter.string(from: startTs.dateValue())
                }
                return DiscoveryRailItem(
                    id: doc.documentID,
                    type: .event,
                    title: title,
                    subtitle: data["location"] as? String ?? data["venue"] as? String,
                    imageURL: imageURLString.flatMap { URL(string: $0) },
                    badgeText: badgeText,
                    progressFraction: nil,
                    metadata: ["eventId": doc.documentID]
                )
            }

            return DiscoveryRail(
                id: DiscoveryRailType.upcomingEvents.rawValue,
                type: .upcomingEvents,
                items: items,
                loadedAt: .now
            )
        } catch {
            return nil
        }
    }

    private func fetchFeaturedStudies() async -> DiscoveryRail? {
        do {
            // Queries editor-curated studies only — no engagement counters drive surfacing.
            let snapshot = try await db
                .collection("studies")
                .whereField("featured", isEqualTo: true)
                .order(by: "featuredAt", descending: true)
                .limit(to: 8)
                .getDocuments()

            let items = snapshot.documents.compactMap { doc -> DiscoveryRailItem? in
                let data = doc.data()
                let title = data["title"] as? String ?? data["name"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                let imageURLString = data["imageURL"] as? String ?? data["coverURL"] as? String
                return DiscoveryRailItem(
                    id: doc.documentID,
                    type: .study,
                    title: title,
                    subtitle: data["author"] as? String ?? data["description"] as? String,
                    imageURL: imageURLString.flatMap { URL(string: $0) },
                    badgeText: nil,
                    progressFraction: nil,
                    metadata: ["studyId": doc.documentID]
                )
            }

            return DiscoveryRail(
                id: DiscoveryRailType.featuredStudies.rawValue,
                type: .featuredStudies,
                items: items,
                loadedAt: .now
            )
        } catch {
            return nil
        }
    }

    private func fetchPeopleYouShouldMeet(userId: String) async -> DiscoveryRail? {
        do {
            // Fetch the current user's churchId first
            let userDoc = try await db.collection("users").document(userId).getDocument()
            guard let churchId = userDoc.data()?["churchId"] as? String,
                  !churchId.isEmpty else {
                return nil
            }

            let snapshot = try await db
                .collection("users")
                .whereField("churchId", isEqualTo: churchId)
                .whereField("allowDiscovery", isEqualTo: true)
                .limit(to: 8)
                .getDocuments()

            let items = snapshot.documents.compactMap { doc -> DiscoveryRailItem? in
                guard doc.documentID != userId else { return nil } // exclude self
                let data = doc.data()
                let title = data["displayName"] as? String ?? data["username"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                let imageURLString = data["photoURL"] as? String ?? data["avatarURL"] as? String
                return DiscoveryRailItem(
                    id: doc.documentID,
                    type: .person,
                    title: title,
                    subtitle: data["bio"] as? String,
                    imageURL: imageURLString.flatMap { URL(string: $0) },
                    badgeText: nil,
                    progressFraction: nil,
                    metadata: ["userId": doc.documentID, "churchId": churchId]
                )
            }

            return DiscoveryRail(
                id: DiscoveryRailType.peopleYouShouldMeet.rawValue,
                type: .peopleYouShouldMeet,
                items: items,
                loadedAt: .now
            )
        } catch {
            return nil
        }
    }

    private func fetchPrayerCommunities() async -> DiscoveryRail? {
        do {
            let snapshot = try await db
                .collection("spaces")
                .whereField("category", isEqualTo: "prayer")
                .limit(to: 8)
                .getDocuments()

            let items = snapshot.documents.compactMap { doc -> DiscoveryRailItem? in
                let data = doc.data()
                let title = data["name"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                let imageURLString = data["imageURL"] as? String ?? data["coverImageURL"] as? String
                return DiscoveryRailItem(
                    id: doc.documentID,
                    type: .space,
                    title: title,
                    subtitle: data["description"] as? String,
                    imageURL: imageURLString.flatMap { URL(string: $0) },
                    badgeText: nil,
                    progressFraction: nil,
                    metadata: ["spaceId": doc.documentID, "category": "prayer"]
                )
            }

            return DiscoveryRail(
                id: DiscoveryRailType.prayerCommunities.rawValue,
                type: .prayerCommunities,
                items: items,
                loadedAt: .now
            )
        } catch {
            return nil
        }
    }

    private func fetchNewCommunities() async -> DiscoveryRail? {
        do {
            let snapshot = try await db
                .collection("spaces")
                .order(by: "createdAt", descending: true)
                .limit(to: 8)
                .getDocuments()

            let items = snapshot.documents.compactMap { doc -> DiscoveryRailItem? in
                let data = doc.data()
                let title = data["name"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                let imageURLString = data["imageURL"] as? String ?? data["coverImageURL"] as? String
                return DiscoveryRailItem(
                    id: doc.documentID,
                    type: .space,
                    title: title,
                    subtitle: data["description"] as? String,
                    imageURL: imageURLString.flatMap { URL(string: $0) },
                    badgeText: "New",
                    progressFraction: nil,
                    metadata: ["spaceId": doc.documentID]
                )
            }

            return DiscoveryRail(
                id: DiscoveryRailType.newCommunities.rawValue,
                type: .newCommunities,
                items: items,
                loadedAt: .now
            )
        } catch {
            return nil
        }
    }

    private func fetchChurchNotes() async -> DiscoveryRail? {
        do {
            let snapshot = try await db
                .collection("churchNotes")
                .whereField("public", isEqualTo: true)
                .order(by: "sharedAt", descending: true)
                .limit(to: 8)
                .getDocuments()

            let items = snapshot.documents.compactMap { doc -> DiscoveryRailItem? in
                let data = doc.data()
                let title = data["title"] as? String ?? data["sermonTitle"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                let imageURLString = data["imageURL"] as? String ?? data["thumbnailURL"] as? String
                return DiscoveryRailItem(
                    id: doc.documentID,
                    type: .churchNote,
                    title: title,
                    subtitle: data["speakerName"] as? String ?? data["churchName"] as? String,
                    imageURL: imageURLString.flatMap { URL(string: $0) },
                    badgeText: nil,
                    progressFraction: nil,
                    metadata: ["noteId": doc.documentID]
                )
            }

            return DiscoveryRail(
                id: DiscoveryRailType.churchNotes.rawValue,
                type: .churchNotes,
                items: items,
                loadedAt: .now
            )
        } catch {
            return nil
        }
    }
}
