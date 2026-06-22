// AmenChurchHubViewModel.swift
// AMEN Spiritual OS — Church Hub
// @Observable view model, real Firestore parallel loads, lightweight model types.
// Created 2026-06-03.

import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

// MARK: - Model types

struct ChurchHubProfile: Identifiable {
    let id: String
    var name: String
    var denomination: String?
    var heroImageURL: String?
    var logoURL: String?
    var liveStreamURL: String?
    var bio: String
    var location: String
    var memberCount: Int
    var websiteURL: String?
    var verifiedMinistry: Bool
}

struct ChurchSermon: Identifiable {
    let id: String
    var title: String
    var speakerName: String
    var thumbnailURL: String?
    var videoURL: String?
    var publishedAt: Date
    var durationSeconds: Int
    var views: Int
    var series: String?
}

struct ChurchEvent: Identifiable {
    let id: String
    var title: String
    var startDate: Date
    var location: String
    var imageURL: String?
    var attendeeCount: Int
    var isVirtual: Bool
    var rsvpURL: String?
}

struct ChurchSmallGroup: Identifiable {
    let id: String
    var name: String
    var focus: String
    var memberCount: Int
    var meetingSchedule: String
    var leaderId: String
    var imageURL: String?
}

struct ChurchMinister: Identifiable {
    let id: String
    var name: String
    var role: String
    var photoURL: String?
    var bio: String?
}

struct ChurchHighlight: Identifiable {
    let id: String
    var imageURL: String
    var caption: String
    var date: Date
}

struct PrayerPreview: Identifiable {
    let id: String
    var text: String
    var prayerCount: Int
    var anonymous: Bool
}

struct VolunteerOpportunity: Identifiable {
    let id: String
    var title: String
    var ministry: String
    var commitment: String
    var spotsRemaining: Int
    var imageURL: String?
}

// MARK: - AmenChurchHubViewModel

@Observable
@MainActor
final class AmenChurchHubViewModel {

    // MARK: - Exposed state

    var church: ChurchHubProfile?
    var sermons: [ChurchSermon] = []
    var events: [ChurchEvent] = []
    var smallGroups: [ChurchSmallGroup] = []
    var ministers: [ChurchMinister] = []
    var communityHighlights: [ChurchHighlight] = []
    var prayerWallPreviews: [PrayerPreview] = []
    var volunteerOpps: [VolunteerOpportunity] = []

    var isLiveNow: Bool { church?.liveStreamURL != nil && liveViewerCount > 0 }
    var liveViewerCount: Int = 0

    var isFollowing: Bool = false

    var isLoadingChurch: Bool = false
    var isLoadingSermons: Bool = false
    var isLoadingEvents: Bool = false
    var isLoadingGroups: Bool = false
    var isLoadingMinisters: Bool = false
    var isLoadingHighlights: Bool = false
    var isLoadingPrayers: Bool = false
    var isLoadingVolunteer: Bool = false

    // MARK: - Private

    private let churchId: String
    @ObservationIgnored private let db = Firestore.firestore()

    // MARK: - Init

    init(churchId: String) {
        self.churchId = churchId
    }

    // MARK: - Load (parallel per section)

    func load(churchId: String) async {
        guard !churchId.isEmpty else { return }

        let churchRef = db.collection("churches").document(churchId)

        // Church profile gates everything — load first
        isLoadingChurch = true
        church = await loadChurchHubProfile(ref: churchRef)
        isLoadingChurch = false

        // All remaining sections load in parallel
        isLoadingSermons = true
        isLoadingEvents = true
        isLoadingGroups = true
        isLoadingMinisters = true
        isLoadingHighlights = true
        isLoadingPrayers = true
        isLoadingVolunteer = true

        async let sermonsResult    = loadSermons(ref: churchRef)
        async let eventsResult     = loadEvents(churchId: churchId)
        async let groupsResult     = loadSmallGroups(ref: churchRef)
        async let ministersResult  = loadMinisters(ref: churchRef)
        async let highlightsResult = loadHighlights(ref: churchRef)
        async let prayersResult    = loadPrayerPreviews(churchId: churchId)
        async let volunteerResult  = loadVolunteerOpps(ref: churchRef)
        async let liveResult       = loadLiveViewerCount(ref: churchRef)
        async let followResult     = loadFollowStatus(churchId: churchId)

        let (s, e, g, m, h, p, v, live, following) =
            await (sermonsResult, eventsResult, groupsResult, ministersResult,
                   highlightsResult, prayersResult, volunteerResult, liveResult, followResult)

        sermons             = s
        events              = e
        smallGroups         = g
        ministers           = m
        communityHighlights = h
        prayerWallPreviews  = p
        volunteerOpps       = v
        liveViewerCount     = live
        isFollowing         = following

        isLoadingSermons   = false
        isLoadingEvents    = false
        isLoadingGroups    = false
        isLoadingMinisters = false
        isLoadingHighlights = false
        isLoadingPrayers   = false
        isLoadingVolunteer = false
    }

    // MARK: - Follow / unfollow

    func toggleFollow() async {
        guard let uid = Auth.auth().currentUser?.uid, !churchId.isEmpty else { return }
        let ref = db.collection("churchFollowers").document(uid).collection("churches").document(churchId)
        do {
            if isFollowing {
                try await ref.delete()
                isFollowing = false
                if var c = church { c.memberCount = max(0, c.memberCount - 1); church = c }
            } else {
                try await ref.setData(["followedAt": Timestamp(date: Date())])
                isFollowing = true
                if var c = church { c.memberCount += 1; church = c }
            }
        } catch {
            // Silently swallow — UI remains optimistic on error
        }
    }

    // MARK: - Private loaders

    /// churches/{churchId}
    private func loadChurchHubProfile(ref: DocumentReference) async -> ChurchHubProfile? {
        do {
            let doc = try await ref.getDocument()
            guard let d = doc.data() else { return nil }
            return ChurchHubProfile(
                id: doc.documentID,
                name: d["name"] as? String ?? "",
                denomination: d["denomination"] as? String,
                heroImageURL: d["heroImageURL"] as? String,
                logoURL: d["logoURL"] as? String,
                liveStreamURL: d["liveStreamURL"] as? String,
                bio: d["bio"] as? String ?? "",
                location: d["location"] as? String ?? "",
                memberCount: d["memberCount"] as? Int ?? 0,
                websiteURL: d["websiteURL"] as? String,
                verifiedMinistry: d["verifiedMinistry"] as? Bool ?? false
            )
        } catch {
            return nil
        }
    }

    /// churches/{churchId}/sermons orderBy publishedAt desc limit 10
    private func loadSermons(ref: DocumentReference) async -> [ChurchSermon] {
        do {
            let snap = try await ref
                .collection("sermons")
                .order(by: "publishedAt", descending: true)
                .limit(to: 10)
                .getDocuments()
            return snap.documents.compactMap { doc -> ChurchSermon? in
                let d = doc.data()
                let title = d["title"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                return ChurchSermon(
                    id: doc.documentID,
                    title: title,
                    speakerName: d["speakerName"] as? String ?? "",
                    thumbnailURL: d["thumbnailURL"] as? String,
                    videoURL: d["videoURL"] as? String,
                    publishedAt: (d["publishedAt"] as? Timestamp)?.dateValue() ?? Date(),
                    durationSeconds: d["durationSeconds"] as? Int ?? 0,
                    views: d["views"] as? Int ?? 0,
                    series: d["series"] as? String
                )
            }
        } catch {
            return []
        }
    }

    /// events where hostChurchId == churchId AND startDate > now orderBy startDate asc limit 8
    private func loadEvents(churchId: String) async -> [ChurchEvent] {
        do {
            let snap = try await db.collection("events")
                .whereField("hostChurchId", isEqualTo: churchId)
                .whereField("startDate", isGreaterThan: Timestamp(date: Date()))
                .order(by: "startDate", descending: false)
                .limit(to: 8)
                .getDocuments()
            return snap.documents.compactMap { doc -> ChurchEvent? in
                let d = doc.data()
                let title = d["title"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                return ChurchEvent(
                    id: doc.documentID,
                    title: title,
                    startDate: (d["startDate"] as? Timestamp)?.dateValue() ?? Date(),
                    location: d["location"] as? String ?? "",
                    imageURL: d["imageURL"] as? String,
                    attendeeCount: d["attendeeCount"] as? Int ?? 0,
                    isVirtual: d["isVirtual"] as? Bool ?? false,
                    rsvpURL: d["rsvpURL"] as? String
                )
            }
        } catch {
            return []
        }
    }

    /// churches/{churchId}/smallGroups where active == true limit 8
    private func loadSmallGroups(ref: DocumentReference) async -> [ChurchSmallGroup] {
        do {
            let snap = try await ref
                .collection("smallGroups")
                .whereField("active", isEqualTo: true)
                .limit(to: 8)
                .getDocuments()
            return snap.documents.compactMap { doc -> ChurchSmallGroup? in
                let d = doc.data()
                let name = d["name"] as? String ?? ""
                guard !name.isEmpty else { return nil }
                return ChurchSmallGroup(
                    id: doc.documentID,
                    name: name,
                    focus: d["focus"] as? String ?? "",
                    memberCount: d["memberCount"] as? Int ?? 0,
                    meetingSchedule: d["meetingSchedule"] as? String ?? "",
                    leaderId: d["leaderId"] as? String ?? "",
                    imageURL: d["imageURL"] as? String
                )
            }
        } catch {
            return []
        }
    }

    /// churches/{churchId}/ministers orderBy order asc limit 8
    private func loadMinisters(ref: DocumentReference) async -> [ChurchMinister] {
        do {
            let snap = try await ref
                .collection("ministers")
                .order(by: "order", descending: false)
                .limit(to: 8)
                .getDocuments()
            return snap.documents.compactMap { doc -> ChurchMinister? in
                let d = doc.data()
                let name = d["name"] as? String ?? ""
                guard !name.isEmpty else { return nil }
                return ChurchMinister(
                    id: doc.documentID,
                    name: name,
                    role: d["role"] as? String ?? "",
                    photoURL: d["photoURL"] as? String,
                    bio: d["bio"] as? String
                )
            }
        } catch {
            return []
        }
    }

    /// churches/{churchId}/highlights orderBy date desc limit 10
    private func loadHighlights(ref: DocumentReference) async -> [ChurchHighlight] {
        do {
            let snap = try await ref
                .collection("highlights")
                .order(by: "date", descending: true)
                .limit(to: 10)
                .getDocuments()
            return snap.documents.compactMap { doc -> ChurchHighlight? in
                let d = doc.data()
                let imageURL = d["imageURL"] as? String ?? ""
                guard !imageURL.isEmpty else { return nil }
                return ChurchHighlight(
                    id: doc.documentID,
                    imageURL: imageURL,
                    caption: d["caption"] as? String ?? "",
                    date: (d["date"] as? Timestamp)?.dateValue() ?? Date()
                )
            }
        } catch {
            return []
        }
    }

    /// prayerRequests where churchId == churchId AND public == true orderBy createdAt desc limit 5
    private func loadPrayerPreviews(churchId: String) async -> [PrayerPreview] {
        do {
            let snap = try await db.collection("prayerRequests")
                .whereField("churchId", isEqualTo: churchId)
                .whereField("public", isEqualTo: true)
                .order(by: "createdAt", descending: true)
                .limit(to: 5)
                .getDocuments()
            return snap.documents.compactMap { doc -> PrayerPreview? in
                let d = doc.data()
                let text = d["text"] as? String ?? ""
                guard !text.isEmpty else { return nil }
                return PrayerPreview(
                    id: doc.documentID,
                    text: text,
                    prayerCount: d["prayerCount"] as? Int ?? 0,
                    anonymous: d["anonymous"] as? Bool ?? false
                )
            }
        } catch {
            return []
        }
    }

    /// churches/{churchId}/volunteerOpportunities where active == true limit 8
    private func loadVolunteerOpps(ref: DocumentReference) async -> [VolunteerOpportunity] {
        do {
            let snap = try await ref
                .collection("volunteerOpportunities")
                .whereField("active", isEqualTo: true)
                .limit(to: 8)
                .getDocuments()
            return snap.documents.compactMap { doc -> VolunteerOpportunity? in
                let d = doc.data()
                let title = d["title"] as? String ?? ""
                guard !title.isEmpty else { return nil }
                return VolunteerOpportunity(
                    id: doc.documentID,
                    title: title,
                    ministry: d["ministry"] as? String ?? "",
                    commitment: d["commitment"] as? String ?? "",
                    spotsRemaining: d["spotsRemaining"] as? Int ?? 0,
                    imageURL: d["imageURL"] as? String
                )
            }
        } catch {
            return []
        }
    }

    /// churches/{churchId}/liveSession — viewer count
    private func loadLiveViewerCount(ref: DocumentReference) async -> Int {
        do {
            let doc = try await ref.collection("liveSession").document("current").getDocument()
            return doc.data()?["viewerCount"] as? Int ?? 0
        } catch {
            return 0
        }
    }

    /// churchFollowers/{userId}/churches/{churchId} existence check
    private func loadFollowStatus(churchId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        do {
            let doc = try await db
                .collection("churchFollowers")
                .document(uid)
                .collection("churches")
                .document(churchId)
                .getDocument()
            return doc.exists
        } catch {
            return false
        }
    }
}
