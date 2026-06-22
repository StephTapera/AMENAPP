// ImpactEngine.swift
// AMEN App — Community Around Content OS / Platform Layer
//
// Connects content communities to real-world opportunities: churches, volunteer roles,
// events, mission trips, meetups, and small groups.
//
// Feature flag: CommunityOSFlag.realWorldImpactEngine

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - RealWorldOpportunityType

enum RealWorldOpportunityType: String, CaseIterable, Codable {
    case volunteerRole        = "volunteer"
    case churchEvent          = "church_event"
    case worshipNight         = "worship_night"
    case prayerGroup          = "prayer_group"
    case missionTrip          = "mission_trip"
    case smallGroup           = "small_group"
    case conferenceOrRetreat  = "conference"

    var displayName: String {
        switch self {
        case .volunteerRole:       return "Volunteer Role"
        case .churchEvent:         return "Church Event"
        case .worshipNight:        return "Worship Night"
        case .prayerGroup:         return "Prayer Group"
        case .missionTrip:         return "Mission Trip"
        case .smallGroup:          return "Small Group"
        case .conferenceOrRetreat: return "Conference / Retreat"
        }
    }

    var systemImage: String {
        switch self {
        case .volunteerRole:       return "hand.raised.fill"
        case .churchEvent:         return "building.columns.fill"
        case .worshipNight:        return "music.note"
        case .prayerGroup:         return "hands.sparkles.fill"
        case .missionTrip:         return "airplane"
        case .smallGroup:          return "person.3.fill"
        case .conferenceOrRetreat: return "ticket.fill"
        }
    }
}

// MARK: - RealWorldOpportunity

struct RealWorldOpportunity: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let type: RealWorldOpportunityType
    let churchId: String?
    let churchName: String?
    let location: String?
    let description: String
    let signUpURL: String?
    let communityNodeId: String?
    let affinityTopics: [CommunityAffinityTopic]
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        type: RealWorldOpportunityType,
        churchId: String? = nil,
        churchName: String? = nil,
        location: String? = nil,
        description: String,
        signUpURL: String? = nil,
        communityNodeId: String? = nil,
        affinityTopics: [CommunityAffinityTopic] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.churchId = churchId
        self.churchName = churchName
        self.location = location
        self.description = description
        self.signUpURL = signUpURL
        self.communityNodeId = communityNodeId
        self.affinityTopics = affinityTopics
        self.createdAt = createdAt
    }

    /// Convenience factory from a Firestore document data dictionary.
    init?(from data: [String: Any]) {
        guard
            let id = data["id"] as? String,
            let title = data["title"] as? String,
            let typeRaw = data["type"] as? String,
            let type = RealWorldOpportunityType(rawValue: typeRaw),
            let description = data["description"] as? String
        else { return nil }

        self.id = id
        self.title = title
        self.type = type
        self.churchId = data["churchId"] as? String
        self.churchName = data["churchName"] as? String
        self.location = data["location"] as? String
        self.description = description
        self.signUpURL = data["signUpURL"] as? String
        self.communityNodeId = data["communityNodeId"] as? String
        self.affinityTopics = (data["affinityTopics"] as? [String] ?? [])
            .compactMap { CommunityAffinityTopic(rawValue: $0) }
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }

    var firestoreData: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "type": type.rawValue,
            "description": description,
            "affinityTopics": affinityTopics.map { $0.rawValue },
            "createdAt": Timestamp(date: createdAt)
        ]
        if let churchId    = churchId    { dict["churchId"] = churchId }
        if let churchName  = churchName  { dict["churchName"] = churchName }
        if let location    = location    { dict["location"] = location }
        if let signUpURL   = signUpURL   { dict["signUpURL"] = signUpURL }
        if let nodeId      = communityNodeId { dict["communityNodeId"] = nodeId }
        return dict
    }
}

// MARK: - ImpactEngine

actor ImpactEngine {

    // MARK: Singleton

    static let shared = ImpactEngine()

    // MARK: Private

    private let db = Firestore.firestore()

    private var opportunitiesCollection: CollectionReference {
        db.collection("realWorldOpportunities")
    }

    // MARK: - fetchOpportunities(for communityNode:)

    /// Queries opportunities by matching affinityTopics array-contains-any.
    func fetchOpportunities(for communityNode: CommunityNode, limit: Int) async throws -> [RealWorldOpportunity] {
        guard await CommunityOSFlagService.shared.isEnabled(.realWorldImpactEngine) else {
            dlog("[ImpactEngine] Flag realWorldImpactEngine is off — skipping fetch for node")
            return []
        }

        let safeLimit = max(1, min(limit, 50))

        // Derive affinity topics from the community node's content kind
        let topics = communityNode.contentKind.defaultCommunityLayers
            .compactMap { layer -> CommunityAffinityTopic? in
                switch layer {
                case .prayer:     return .prayer
                case .worship:    return .worship
                case .study:      return .discipleship
                case .mentorship: return .leadership
                case .realWorld:  return .missions
                default:          return nil
                }
            }
            .map { $0.rawValue }

        guard !topics.isEmpty else { return [] }

        let snapshot = try await opportunitiesCollection
            .whereField("affinityTopics", arrayContainsAny: Array(topics.prefix(10)))
            .limit(to: safeLimit)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> RealWorldOpportunity? in
            RealWorldOpportunity(from: doc.data())
        }
    }

    // MARK: - fetchOpportunities(for userId:)

    /// Fetches opportunities that match the user's DNA affinity topics.
    func fetchOpportunities(for userId: String) async throws -> [RealWorldOpportunity] {
        guard await CommunityOSFlagService.shared.isEnabled(.realWorldImpactEngine) else {
            dlog("[ImpactEngine] Flag realWorldImpactEngine is off — skipping fetch for user")
            return []
        }

        let dnaSnapshot = try await db
            .collection("communityDNAProfiles")
            .document(userId)
            .getDocument()

        let rawAffinities = dnaSnapshot.data()?["topAffinities"] as? [[String: Any]] ?? []
        let topics: [String] = rawAffinities
            .compactMap { raw -> (String, Double)? in
                guard
                    let topicRaw = raw["topic"] as? String,
                    let score = raw["score"] as? Double
                else { return nil }
                return (topicRaw, score)
            }
            .filter { $0.1 > 0.3 }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0.0 }

        guard !topics.isEmpty else { return [] }

        let snapshot = try await opportunitiesCollection
            .whereField("affinityTopics", arrayContainsAny: Array(topics.prefix(10)))
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> RealWorldOpportunity? in
            RealWorldOpportunity(from: doc.data())
        }
    }

    // MARK: - createOpportunity

    /// Writes a new RealWorldOpportunity to Firestore.
    func createOpportunity(_ opportunity: RealWorldOpportunity) async throws {
        guard await CommunityOSFlagService.shared.isEnabled(.realWorldImpactEngine) else {
            dlog("[ImpactEngine] Flag realWorldImpactEngine is off — skipping create")
            return
        }

        try await opportunitiesCollection
            .document(opportunity.id)
            .setData(opportunity.firestoreData)

        dlog("[ImpactEngine] Created opportunity: \(opportunity.id) '\(opportunity.title)'")
    }

    // MARK: - suggestMeetups

    /// If community memberCount > CommunityEmergenceThresholds.minMembersForEventSuggestion,
    /// returns or creates meetup suggestions for the community.
    func suggestMeetups(for communityNode: CommunityNode) async throws -> [RealWorldOpportunity] {
        guard await CommunityOSFlagService.shared.isEnabled(.realWorldImpactEngine) else {
            dlog("[ImpactEngine] Flag realWorldImpactEngine is off — skipping meetup suggestions")
            return []
        }

        guard communityNode.memberCount >= CommunityEmergenceThresholds.minMembersForEventSuggestion else {
            dlog("[ImpactEngine] Community '\(communityNode.name)' has \(communityNode.memberCount) members — below meetup threshold")
            return []
        }

        // Check if meetup suggestions already exist for this node
        let existingSnapshot = try await opportunitiesCollection
            .whereField("communityNodeId", isEqualTo: communityNode.id)
            .whereField("type", isEqualTo: RealWorldOpportunityType.smallGroup.rawValue)
            .limit(to: 5)
            .getDocuments()

        let existing = existingSnapshot.documents.compactMap { doc -> RealWorldOpportunity? in
            RealWorldOpportunity(from: doc.data())
        }

        if !existing.isEmpty {
            dlog("[ImpactEngine] Returning \(existing.count) existing meetup suggestions for '\(communityNode.name)'")
            return existing
        }

        // Auto-generate a meetup suggestion for this community
        let suggestion = RealWorldOpportunity(
            title: "Meet with Your \(communityNode.name) Community",
            type: .smallGroup,
            description: "This community has grown enough to gather in person. Connect with others who share your passion for \(communityNode.contentKind.displayName.lowercased()).",
            communityNodeId: communityNode.id,
            affinityTopics: communityNode.contentKind.defaultCommunityLayers.compactMap { layer -> CommunityAffinityTopic? in
                switch layer {
                case .prayer:     return .prayer
                case .worship:    return .worship
                case .study:      return .discipleship
                case .mentorship: return .leadership
                default:          return nil
                }
            }
        )

        try await createOpportunity(suggestion)
        dlog("[ImpactEngine] Created meetup suggestion for '\(communityNode.name)' (memberCount: \(communityNode.memberCount))")
        return [suggestion]
    }
}

// MARK: - ImpactOpportunitiesView

/// Renders a vertically grouped list of real-world opportunities.
struct ImpactOpportunitiesView: View {

    let opportunities: [RealWorldOpportunity]

    /// Groups opportunities by type, maintaining a stable display order.
    private var grouped: [(type: RealWorldOpportunityType, items: [RealWorldOpportunity])] {
        var map: [RealWorldOpportunityType: [RealWorldOpportunity]] = [:]
        for opp in opportunities {
            map[opp.type, default: []].append(opp)
        }
        return RealWorldOpportunityType.allCases
            .compactMap { type -> (type: RealWorldOpportunityType, items: [RealWorldOpportunity])? in
                guard let items = map[type], !items.isEmpty else { return nil }
                return (type: type, items: items)
            }
    }

    var body: some View {
        Group {
            if CommunityOSFlagService.shared.isEnabled(.realWorldImpactEngine) {
                mainContent
            } else {
                Color(.systemBackground)
            }
        }
    }

    // MARK: Main content

    @ViewBuilder
    private var mainContent: some View {
        if opportunities.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    sectionHeader

                    ForEach(grouped, id: \.type) { group in
                        typeSectionView(type: group.type, items: group.items)
                    }
                }
                .padding()
            }
            .background(Color(.systemBackground))
        }
    }

    // MARK: Section header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk.circle.fill")
                .font(.title3)
                .foregroundColor(Color(.secondaryLabel))
            Text("Real-World Impact")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Color(.label))
        }
    }

    // MARK: Type section

    private func typeSectionView(type: RealWorldOpportunityType, items: [RealWorldOpportunity]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Type header
            HStack(spacing: 6) {
                Image(systemName: type.systemImage)
                    .font(.subheadline)
                    .foregroundColor(Color(.secondaryLabel))
                Text(type.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(.secondaryLabel))
            }

            ForEach(items) { opportunity in
                opportunityCard(opportunity)
            }
        }
    }

    // MARK: Opportunity card

    private func opportunityCard(_ opportunity: RealWorldOpportunity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: type badge + title
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: opportunity.type.systemImage)
                    .font(.title3)
                    .foregroundColor(Color(.secondaryLabel))
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    // Type label badge
                    Text(opportunity.type.displayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(.secondaryLabel))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())

                    Text(opportunity.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(.label))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Church name
            if let churchName = opportunity.churchName {
                HStack(spacing: 4) {
                    Image(systemName: "building.columns")
                        .font(.caption)
                        .foregroundColor(Color(.secondaryLabel))
                    Text(churchName)
                        .font(.caption)
                        .foregroundColor(Color(.secondaryLabel))
                }
            }

            // Location
            if let location = opportunity.location {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(Color(.secondaryLabel))
                    Text(location)
                        .font(.caption)
                        .foregroundColor(Color(.secondaryLabel))
                }
            }

            // Description (2 lines)
            Text(opportunity.description)
                .font(.footnote)
                .foregroundColor(Color(.secondaryLabel))
                .lineLimit(2)

            // Learn More button
            if let urlString = opportunity.signUpURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Text("Learn More")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .foregroundColor(Color(.systemBackground))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    // DESIGN FIX (LOW 2026-06-11): Removed .amenGlassEffect() — stacking it
                    // over an opaque Color(.label) background produces broken appearance on
                    // iOS 26. The opaque background alone is the correct treatment here.
                    .background(Color(.label))
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Learn more about \(opportunity.title)")
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.walk.circle")
                .font(.systemScaled(44))
                .foregroundColor(Color(.secondaryLabel))
            Text("Opportunities will appear as your community grows")
                .font(.body)
                .foregroundColor(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 32)
    }
}
