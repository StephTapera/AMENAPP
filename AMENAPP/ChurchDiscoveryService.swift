// ChurchDiscoveryService.swift
// AMEN App — Intelligent Church Discovery System
//
// Purpose: Go far beyond a static map. Create a smart recommendation system
// that helps users find the right church based on deep preference matching,
// smart scoring, and first-visit guidance.
//
// Architecture:
//   ChurchDiscoveryService     ← orchestrates search + ranking
//   ChurchRecommendationEngine ← personalized scoring algorithm
//   ChurchPreferenceProfile    ← user's saved discovery preferences
//   FirstVisitCompanion        ← structured first-visit guidance flow
//   ChurchRichProfile          ← enriched church model with all metadata
//
// Data sources (abstracted):
//   - Firestore church profiles (AMEN-managed)
//   - User preference profile (local + Firestore)
//   - Location services (MapKit)

import Foundation
import SwiftUI
import CoreLocation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Rich Church Profile

/// Extended church model with all metadata needed for smart discovery.
/// This enriches the basic Church model from FindChurchView.swift.
struct ChurchRichProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let denomination: String?
    let description: String?
    let address: String
    let city: String
    let state: String
    let latitude: Double
    let longitude: Double
    let website: String?
    let phone: String?
    let email: String?
    let logoURL: String?
    let bannerURL: String?
    let isVerified: Bool

    // Service information
    let serviceTimes: [ServiceTime]
    let languages: [String]
    let hasLivestream: Bool
    let livestreamURL: String?

    // Community characteristics
    let tags: [ChurchTag]
    let ageGroups: [AgeGroup]
    let hasAccessibility: Bool
    let hasKidsMinistry: Bool
    let hasYouthMinistry: Bool
    let hasCollegeMinistry: Bool

    // Discovery metadata
    var distanceMiles: Double?
    var recommendationScore: Double = 0
    var matchReasons: [String] = []
    var isSaved: Bool = false
    var hasVisited: Bool = false

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var primaryServiceTime: String {
        serviceTimes.first?.display ?? "Service times available"
    }

    var isNearby: Bool { (distanceMiles ?? 999) < 15 }
    var isWorthTheDrive: Bool { (distanceMiles ?? 999) < 50 && recommendationScore > 75 }

    struct ServiceTime: Identifiable, Equatable {
        let id = UUID()
        let day: String       // "Sunday", "Wednesday"
        let time: String      // "10:00 AM"
        let name: String?     // "Contemporary Service", "Traditional Service"

        var display: String { "\(day) \(time)" }
    }

    enum ChurchTag: String, CaseIterable, Equatable {
        case expository = "Expository Preaching"
        case worshipLed = "Worship-Led"
        case prayerFocused = "Prayer-Focused"
        case missionsMinded = "Missions-Minded"
        case smallGroups = "Small Groups"
        case youngAdults = "Young Adults"
        case diverse = "Diverse Community"
        case traditional = "Traditional"
        case contemporary = "Contemporary"
        case firstTimerFriendly = "First-Timer Friendly"
        case familyFocused = "Family-Focused"
        case socialJustice = "Social Justice"
        case reformed = "Reformed"
        case charismatic = "Charismatic"
        case bilingual = "Bilingual"
    }

    enum AgeGroup: String, CaseIterable, Equatable {
        case children = "Children"
        case youth = "Youth (6–12)"
        case teens = "Teens"
        case collegeYoungAdults = "College & Young Adults"
        case adults = "Adults"
        case seniors = "Seniors"
    }

    static func == (lhs: ChurchRichProfile, rhs: ChurchRichProfile) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Church Preference Profile

/// The user's saved preferences for church discovery.
/// Drives personalized ranking and smart recommendations.
struct ChurchPreferenceProfile: Codable {
    var maxDistanceMiles: Double = 20
    var preferredDenominations: [String] = []
    var preferredTags: [String] = []
    var preferredAgeGroups: [String] = []
    var preferredLanguage: String = "English"
    var requiresLivestream: Bool = false
    var requiresKidsMinistry: Bool = false
    var requiresAccessibility: Bool = false
    var hasCompletedOnboarding: Bool = false
    var lastUpdated: Date = Date()
}

// MARK: - Church Recommendation Engine

struct ChurchRecommendationEngine {

    /// Score a church profile for a given user preference profile.
    /// Returns 0–100.
    static func score(
        church: ChurchRichProfile,
        preferences: ChurchPreferenceProfile,
        userLocation: CLLocation?
    ) -> (score: Double, reasons: [String]) {
        var score: Double = 50  // Baseline
        var reasons: [String] = []

        // ── Distance scoring ─────────────────────────────────────────────
        if let userLoc = userLocation {
            let churchLoc = CLLocation(latitude: church.latitude, longitude: church.longitude)
            let distanceMiles = userLoc.distance(from: churchLoc) / 1609.34
            if distanceMiles <= 2 {
                score += 25
                reasons.append("Very close to you (\(String(format: "%.1f", distanceMiles)) mi)")
            } else if distanceMiles <= 5 {
                score += 20
                reasons.append("Close to you (\(String(format: "%.1f", distanceMiles)) mi)")
            } else if distanceMiles <= 10 {
                score += 12
            } else if distanceMiles <= 20 {
                score += 5
            } else if distanceMiles > preferences.maxDistanceMiles {
                score -= 10
            }
        }

        // ── Denomination match ────────────────────────────────────────────
        if !preferences.preferredDenominations.isEmpty,
           let denom = church.denomination,
           preferences.preferredDenominations.contains(denom) {
            score += 20
            reasons.append("Matches your denomination preference")
        }

        // ── Tag matching ──────────────────────────────────────────────────
        let churchTagStrings = church.tags.map { $0.rawValue }
        let matchedTags = preferences.preferredTags.filter { churchTagStrings.contains($0) }
        let tagScore = Double(matchedTags.count) * 8
        score += min(24, tagScore)
        if !matchedTags.isEmpty {
            reasons.append("Matches: \(matchedTags.prefix(2).joined(separator: ", "))")
        }

        // ── Hard requirements ─────────────────────────────────────────────
        if preferences.requiresKidsMinistry && church.hasKidsMinistry {
            score += 15
            reasons.append("Has kids ministry")
        } else if preferences.requiresKidsMinistry && !church.hasKidsMinistry {
            score -= 30  // Strong penalty for unmet hard requirement
        }

        if preferences.requiresLivestream && church.hasLivestream {
            score += 10
            reasons.append("Has livestream")
        } else if preferences.requiresLivestream && !church.hasLivestream {
            score -= 20
        }

        if preferences.requiresAccessibility && church.hasAccessibility {
            score += 10
            reasons.append("Accessible")
        } else if preferences.requiresAccessibility && !church.hasAccessibility {
            score -= 25
        }

        // ── Language match ────────────────────────────────────────────────
        if !preferences.preferredLanguage.isEmpty && preferences.preferredLanguage != "English" {
            if church.languages.contains(preferences.preferredLanguage) {
                score += 15
                reasons.append("Services in \(preferences.preferredLanguage)")
            }
        }

        // ── Verification boost ────────────────────────────────────────────
        if church.isVerified {
            score += 5
        }

        // ── First-timer friendly ──────────────────────────────────────────
        if church.tags.contains(.firstTimerFriendly) {
            score += 8
        }

        return (min(100, max(0, score)), reasons)
    }
}

// MARK: - First Visit Companion

struct FirstVisitCompanionGuide: Identifiable {
    let id = UUID()
    let churchName: String
    let steps: [FirstVisitStep]
    let encouragement: String

    struct FirstVisitStep: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let icon: String
    }

    static func make(for church: ChurchRichProfile) -> FirstVisitCompanionGuide {
        FirstVisitCompanionGuide(
            churchName: church.name,
            steps: [
                FirstVisitStep(
                    title: "Service time",
                    detail: church.primaryServiceTime,
                    icon: "clock.fill"
                ),
                FirstVisitStep(
                    title: "What to expect",
                    detail: church.tags.isEmpty
                        ? "A welcoming community gathering for worship and teaching."
                        : "A \(church.tags.prefix(2).map { $0.rawValue.lowercased() }.joined(separator: " & ")) community.",
                    icon: "info.circle.fill"
                ),
                FirstVisitStep(
                    title: "Arrive a few minutes early",
                    detail: "Give yourself time to find parking and settle in. Most churches have greeters who can help.",
                    icon: "figure.walk"
                ),
                FirstVisitStep(
                    title: "You don't need to know all the words",
                    detail: "It's completely okay to observe, sit, and just listen on your first visit.",
                    icon: "heart.fill"
                ),
                FirstVisitStep(
                    title: "After the service",
                    detail: "Many churches have a welcome area for first-timers. Feel free to introduce yourself or ask questions.",
                    icon: "person.2.fill"
                ),
            ],
            encouragement: "Taking that first step can feel big — but you're not alone. Many in this community have been where you are. We're praying for you."
        )
    }
}

// MARK: - Church Discovery Service

@MainActor
final class ChurchDiscoveryService: ObservableObject {

    static let shared = ChurchDiscoveryService()

    private let db = Firestore.firestore()
    private let flags = AMENFeatureFlags.shared

    @Published private(set) var recommendedChurches: [ChurchRichProfile] = []
    @Published private(set) var nearbyChurches: [ChurchRichProfile] = []
    @Published private(set) var savedChurches: [ChurchRichProfile] = []
    @Published private(set) var isLoading: Bool = false
    @Published var userPreferences = ChurchPreferenceProfile()

    private var userLocation: CLLocation?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadPreferences()
    }

    // MARK: - Location

    func updateUserLocation(_ location: CLLocation) {
        userLocation = location
        Task { await refreshRecommendations() }
    }

    // MARK: - Recommendations

    func refreshRecommendations() async {
        guard flags.churchDiscoverySmartRankingEnabled else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var churches = try await fetchChurches()

            // Score and rank
            churches = churches.map { church in
                var c = church
                let (score, reasons) = ChurchRecommendationEngine.score(
                    church: church,
                    preferences: userPreferences,
                    userLocation: userLocation
                )
                c.recommendationScore = score
                c.matchReasons = reasons
                // Compute distance
                if let loc = userLocation {
                    let churchLoc = CLLocation(latitude: church.latitude, longitude: church.longitude)
                    c.distanceMiles = loc.distance(from: churchLoc) / 1609.34
                }
                return c
            }
            .sorted { $0.recommendationScore > $1.recommendationScore }

            recommendedChurches = churches
            nearbyChurches = churches.filter { $0.isNearby }

        } catch {
            print("[ChurchDiscovery] Failed to fetch churches: \(error)")
        }
    }

    func searchChurches(query: String) async -> [ChurchRichProfile] {
        guard !query.isEmpty else { return recommendedChurches }
        let lower = query.lowercased()
        return recommendedChurches.filter { church in
            church.name.lowercased().contains(lower) ||
            (church.denomination?.lowercased().contains(lower) ?? false) ||
            church.city.lowercased().contains(lower) ||
            church.tags.contains(where: { $0.rawValue.lowercased().contains(lower) })
        }
    }

    func filterChurches(tags: [ChurchRichProfile.ChurchTag], maxDistance: Double?) -> [ChurchRichProfile] {
        var results = recommendedChurches
        if !tags.isEmpty {
            results = results.filter { church in
                tags.allSatisfy { church.tags.contains($0) }
            }
        }
        if let maxDist = maxDistance {
            results = results.filter { ($0.distanceMiles ?? 999) <= maxDist }
        }
        return results
    }

    func saveChurch(_ church: ChurchRichProfile) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db
            .collection("users").document(uid)
            .collection("savedChurches").document(church.id)
            .setData([
                "churchId": church.id,
                "churchName": church.name,
                "savedAt": FieldValue.serverTimestamp()
            ])
        if !savedChurches.contains(church) {
            savedChurches.append(church)
        }
    }

    func unsaveChurch(_ churchId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db
            .collection("users").document(uid)
            .collection("savedChurches").document(churchId)
            .delete()
        savedChurches.removeAll { $0.id == churchId }
    }

    // MARK: - First Visit Companion

    func firstVisitGuide(for church: ChurchRichProfile) -> FirstVisitCompanionGuide {
        FirstVisitCompanionGuide.make(for: church)
    }

    func markVisited(_ churchId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db
            .collection("users").document(uid)
            .collection("churchVisits").document(churchId)
            .setData([
                "churchId": churchId,
                "visitedAt": FieldValue.serverTimestamp()
            ])
    }

    // MARK: - Service Reminders

    func scheduleServiceReminder(for church: ChurchRichProfile) {
        guard flags.churchServiceRemindersEnabled else { return }
        // Integration point for UNUserNotificationCenter
        // Notification content would be: "Your saved church — \(church.name) — has a service today at \(church.primaryServiceTime)"
        print("[ChurchDiscovery] Service reminder scheduled for \(church.name)")
    }

    // MARK: - Preferences

    func savePreferences() {
        if let data = try? JSONEncoder().encode(userPreferences) {
            UserDefaults.standard.set(data, forKey: "churchDiscoveryPreferences")
        }
    }

    private func loadPreferences() {
        if let data = UserDefaults.standard.data(forKey: "churchDiscoveryPreferences"),
           let prefs = try? JSONDecoder().decode(ChurchPreferenceProfile.self, from: data) {
            userPreferences = prefs
        }
    }

    func completePreferencesOnboarding() {
        userPreferences.hasCompletedOnboarding = true
        savePreferences()
        Task { await refreshRecommendations() }
    }

    // MARK: - Firestore Fetch

    private func fetchChurches() async throws -> [ChurchRichProfile] {
        let snapshot = try await db
            .collection("churches")
            .whereField("isPublished", isEqualTo: true)
            .limit(to: 100)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> ChurchRichProfile? in
            let data = doc.data()
            guard let name = data["name"] as? String,
                  let lat = data["latitude"] as? Double,
                  let lon = data["longitude"] as? Double else { return nil }

            // Parse service times
            let serviceTimesData = data["serviceTimes"] as? [[String: String]] ?? []
            let serviceTimes = serviceTimesData.map { st in
                ChurchRichProfile.ServiceTime(
                    day: st["day"] ?? "",
                    time: st["time"] ?? "",
                    name: st["name"]
                )
            }

            // Parse tags
            let tagStrings = data["tags"] as? [String] ?? []
            let tags = tagStrings.compactMap { ChurchRichProfile.ChurchTag(rawValue: $0) }

            return ChurchRichProfile(
                id: doc.documentID,
                name: name,
                denomination: data["denomination"] as? String,
                description: data["description"] as? String,
                address: data["address"] as? String ?? "",
                city: data["city"] as? String ?? "",
                state: data["state"] as? String ?? "",
                latitude: lat,
                longitude: lon,
                website: data["website"] as? String,
                phone: data["phone"] as? String,
                email: data["email"] as? String,
                logoURL: data["logoURL"] as? String,
                bannerURL: data["bannerURL"] as? String,
                isVerified: data["isVerified"] as? Bool ?? false,
                serviceTimes: serviceTimes,
                languages: data["languages"] as? [String] ?? ["English"],
                hasLivestream: data["hasLivestream"] as? Bool ?? false,
                livestreamURL: data["livestreamURL"] as? String,
                tags: tags,
                ageGroups: [],
                hasAccessibility: data["hasAccessibility"] as? Bool ?? false,
                hasKidsMinistry: data["hasKidsMinistry"] as? Bool ?? false,
                hasYouthMinistry: data["hasYouthMinistry"] as? Bool ?? false,
                hasCollegeMinistry: data["hasCollegeMinistry"] as? Bool ?? false
            )
        }
    }
}

// MARK: - Church Preference Onboarding View

struct ChurchPreferenceOnboardingView: View {
    @ObservedObject private var service = ChurchDiscoveryService.shared
    @State private var selectedTags: Set<ChurchRichProfile.ChurchTag> = []
    @State private var requiresKids: Bool = false
    @State private var requiresLivestream: Bool = false
    @State private var maxDistance: Double = 20
    let onComplete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find your church")
                        .font(.custom("OpenSans-Bold", size: 24))
                    Text("Help us personalize your church discovery experience.")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Community characteristics
                VStack(alignment: .leading, spacing: 12) {
                    Text("What matters to you?")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .padding(.horizontal, 20)

                    FlowLayout(spacing: 10) {
                        ForEach(ChurchRichProfile.ChurchTag.allCases, id: \.self) { tag in
                            TagChip(
                                title: tag.rawValue,
                                isSelected: selectedTags.contains(tag)
                            ) {
                                if selectedTags.contains(tag) { selectedTags.remove(tag) }
                                else { selectedTags.insert(tag) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Hard requirements
                VStack(alignment: .leading, spacing: 14) {
                    Text("Requirements")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .padding(.horizontal, 20)

                    VStack(spacing: 1) {
                        Toggle("Kids Ministry", isOn: $requiresKids)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))

                        Toggle("Livestream available", isOn: $requiresLivestream)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                }

                // Distance
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Max distance")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                        Spacer()
                        Text("\(Int(maxDistance)) miles")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)

                    Slider(value: $maxDistance, in: 5...100, step: 5)
                        .padding(.horizontal, 20)
                        .accentColor(.blue)
                }

                Button {
                    service.userPreferences.preferredTags = selectedTags.map { $0.rawValue }
                    service.userPreferences.requiresKidsMinistry = requiresKids
                    service.userPreferences.requiresLivestream = requiresLivestream
                    service.userPreferences.maxDistanceMiles = maxDistance
                    service.completePreferencesOnboarding()
                    onComplete()
                } label: {
                    Text("Find Churches")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Supporting Views

struct TagChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.custom("OpenSans-Medium", size: 13))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.blue : Color.gray.opacity(0.12),
                    in: Capsule()
                )
        }
    }
}

// FlowLayout is defined in AMENAPP/FlowLayout.swift
