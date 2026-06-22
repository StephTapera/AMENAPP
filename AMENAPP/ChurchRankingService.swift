import Foundation
import CoreLocation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

struct ChurchFitBreakdownItem: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let verdict: String
}

struct ChurchFirstVisitSnapshot: Equatable {
    let entrance: String?
    let parking: String?
    let whatToWear: String?
    let childcareSummary: String?
    let serviceLength: String?
    let greetingSummary: String?
    let livestreamPreview: String?
}

struct ChurchSermonSnapshot: Equatable {
    let topic: String
    let scripture: String?
    let style: String?
    let quote: String?
    let matchSummary: String?
}

struct ChurchSundayPlanSnapshot: Equatable {
    let serviceLabel: String
    let driveTimeLabel: String
    let reminderLabel: String
    let parkingLabel: String
    let childcareLabel: String
    let whatToExpectLabel: String
    let directionsLabel: String
}

struct ChurchRankingSnapshot: Equatable {
    let churchId: UUID
    let score: Int
    let reason: String
    let reasonDetails: [String]
    let urgencyLabel: String?
    let bestVisitSummary: String?
    let fitBreakdown: [ChurchFitBreakdownItem]
    let personalityTags: [String]
    let socialProof: [String]
    let sermon: ChurchSermonSnapshot?
    let firstVisit: ChurchFirstVisitSnapshot?
    let sundayPlan: ChurchSundayPlanSnapshot?
    let isLiveNow: Bool
    let isStartingSoon: Bool
}

private struct RankedChurchResponse {
    let churchId: String
    let score: Int
    let reason: String
    let reasonDetails: [String]
    let tags: [String]
    let nextService: String?
    let distance: Double?
    let live: Bool
    let serviceSoon: Bool
    let bestVisit: String?
    let fitBreakdown: [ChurchFitBreakdownItem]
    let socialProof: [String]
    let sermon: ChurchSermonSnapshot?
    let firstVisit: ChurchFirstVisitSnapshot?
    let sundayPlan: ChurchSundayPlanSnapshot?
}

private enum ChurchSearchNeed: CaseIterable {
    case lonely
    case community
    case newToFaith
    case deeperTeaching
    case prayer
    case kids

    static func match(for query: String) -> ChurchSearchNeed? {
        let lowered = query.lowercased()
        if lowered.contains("lonely") { return .lonely }
        if lowered.contains("community") { return .community }
        if lowered.contains("new to faith") || lowered.contains("new believer") { return .newToFaith }
        if lowered.contains("deeper teaching") || lowered.contains("bible teaching") { return .deeperTeaching }
        if lowered.contains("need prayer") || lowered.contains("prayer") { return .prayer }
        if lowered.contains("kids") || lowered.contains("children") || lowered.contains("bringing my kids") { return .kids }
        return nil
    }
}

@MainActor
final class ChurchRankingService: ObservableObject {
    static let shared = ChurchRankingService()

    @Published private(set) var snapshots: [UUID: ChurchRankingSnapshot] = [:]
    @Published private(set) var orderedChurchIds: [UUID] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private lazy var functions = Functions.functions()
    private var rawChurchData: [String: [String: Any]] = [:]
    private var sermonsByChurchId: [String: ChurchSermonSnapshot] = [:]
    private var listeners: [String: ListenerRegistration] = [:]
    private var userContextListener: ListenerRegistration?
    private var userContext: [String: Any] = [:]

    private init() {
        startUserContextListener()
    }

    func observe(church: Church) {
        let key = church.id.uuidString
        guard listeners[key] == nil else { return }

        listeners[key] = db.collection("churches").document(key).addSnapshotListener { [weak self] snapshot, _ in
            guard let self else { return }
            if let data = snapshot?.data() {
                self.rawChurchData[key] = data
            }

            Task { @MainActor in
                self.refreshLocalSnapshot(for: church)
                await self.loadLatestSermon(for: key)
            }
        }
    }

    func stopObserving(churchId: String) {
        listeners[churchId]?.remove()
        listeners[churchId] = nil
    }

    func snapshot(for church: Church) -> ChurchRankingSnapshot? {
        snapshots[church.id]
    }

    func orderedChurches(from churches: [Church]) -> [Church] {
        guard !orderedChurchIds.isEmpty else { return churches }
        let lookup = Dictionary(uniqueKeysWithValues: churches.map { ($0.id, $0) })
        let ranked = orderedChurchIds.compactMap { lookup[$0] }
        let leftovers = churches.filter { !orderedChurchIds.contains($0.id) }
        return ranked + leftovers
    }

    func refreshRanking(
        churches: [Church],
        userLocation: CLLocationCoordinate2D?,
        query: String,
        intent: String,
        firstVisitMode: Bool
    ) async {
        guard !churches.isEmpty else {
            orderedChurchIds = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let payload: [String: Any] = [
                "userId": Auth.auth().currentUser?.uid ?? "",
                "location": [
                    "latitude": userLocation?.latitude as Any,
                    "longitude": userLocation?.longitude as Any,
                ],
                "timeContext": [
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                    "timezone": TimeZone.current.identifier,
                    "firstVisitMode": firstVisitMode,
                ],
                "intent": intent,
                "query": query,
                "candidateChurches": churches.map { church in
                    [
                        "churchId": church.id.uuidString,
                        "name": church.name,
                        "denomination": church.denomination,
                        "address": church.address,
                        "distance": church.distanceValue,
                        "serviceTime": church.serviceTime,
                        "website": church.website as Any,
                    ]
                },
            ]

            let callable = functions.httpsCallable("rankChurchesForUser")
            let result = try await callable.call(payload)
            guard let root = result.data as? [String: Any],
                  let items = root["results"] as? [[String: Any]] else {
                applyFallbackRanking(churches: churches, query: query, intent: intent, firstVisitMode: firstVisitMode)
                return
            }

            var ordered: [UUID] = []
            for item in items {
                guard let parsed = parseRankedChurch(item) else { continue }
                guard let church = churches.first(where: { $0.id.uuidString == parsed.churchId }) else { continue }
                let snapshot = buildSnapshot(church: church, ranked: parsed)
                snapshots[church.id] = snapshot
                ordered.append(church.id)
            }

            for church in churches where snapshots[church.id] == nil {
                refreshLocalSnapshot(for: church)
            }

            orderedChurchIds = ordered
        } catch {
            applyFallbackRanking(churches: churches, query: query, intent: intent, firstVisitMode: firstVisitMode)
        }
    }

    func searchAndSort(_ churches: [Church], query: String) -> [Church] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return churches }

        let need = ChurchSearchNeed.match(for: trimmed)
        let scored = churches.map { church -> (Church, Double) in
            let lowered = trimmed.lowercased()
            let snapshot = snapshots[church.id]
            let haystack = [
                church.name,
                church.address,
                church.denomination,
                snapshot?.reason ?? "",
                snapshot?.personalityTags.joined(separator: " ") ?? "",
                snapshot?.socialProof.joined(separator: " ") ?? "",
                snapshot?.sermon?.topic ?? "",
                snapshot?.sermon?.scripture ?? "",
            ].joined(separator: " ").lowercased()

            var score = haystack.contains(lowered) ? 3.0 : 0.0
            if let need, matches(need: need, church: church, snapshot: snapshot) {
                score += 4.0
            }
            if let snapshot {
                score += Double(snapshot.score) / 100.0
            }
            return (church, score)
        }

        let filtered = scored.filter { $0.1 > 0 }
        if filtered.isEmpty { return churches }
        return filtered.sorted { $0.1 > $1.1 }.map(\.0)
    }

    func matchesQuickFilter(_ filter: FindChurchView.QuickFilter, church: Church) -> Bool {
        let snapshot = snapshots[church.id]
        switch filter {
        case .nearestNow:
            return church.distanceValue <= 5
        case .serviceToday:
            return church.serviceTime.lowercased().contains("sunday") || snapshot?.isStartingSoon == true || snapshot?.isLiveNow == true
        case .openNow:
            return snapshot?.isLiveNow == true || snapshot?.isStartingSoon == true
        case .visitedBefore:
            return false
        case .highlyRated:
            return (snapshot?.score ?? 0) >= 80
        case .serviceSoon:
            return snapshot?.isStartingSoon == true || snapshot?.isLiveNow == true
        case .teaching:
            return matchesPersonality("Bible-heavy", snapshot: snapshot)
        case .worship:
            return matchesPersonality("Worship-forward", snapshot: snapshot)
        case .family:
            return matchesPersonality("Family-centered", snapshot: snapshot)
        case .youngAdults:
            return matchesPersonality("Young adult active", snapshot: snapshot)
        case .newHere:
            return matchesPersonality("New-believer friendly", snapshot: snapshot) || snapshot?.firstVisit != nil
        }
    }

    private func matchesPersonality(_ value: String, snapshot: ChurchRankingSnapshot?) -> Bool {
        snapshot?.personalityTags.contains(value) == true
    }

    private func parseRankedChurch(_ data: [String: Any]) -> RankedChurchResponse? {
        guard let churchId = data["churchId"] as? String else { return nil }

        let fitItems = (data["fitBreakdown"] as? [[String: Any]] ?? []).compactMap { item -> ChurchFitBreakdownItem? in
            guard let title = item["title"] as? String, let verdict = item["verdict"] as? String else { return nil }
            return ChurchFitBreakdownItem(title: title, verdict: verdict)
        }

        let sermon: ChurchSermonSnapshot?
        if let sermonData = data["sermon"] as? [String: Any],
           let topic = sermonData["topic"] as? String {
            sermon = ChurchSermonSnapshot(
                topic: topic,
                scripture: sermonData["scripture"] as? String,
                style: sermonData["style"] as? String,
                quote: sermonData["quote"] as? String,
                matchSummary: sermonData["matchSummary"] as? String
            )
        } else {
            sermon = nil
        }

        let firstVisit: ChurchFirstVisitSnapshot?
        if let visitData = data["firstVisit"] as? [String: Any] {
            firstVisit = ChurchFirstVisitSnapshot(
                entrance: visitData["entrance"] as? String,
                parking: visitData["parking"] as? String,
                whatToWear: visitData["whatToWear"] as? String,
                childcareSummary: visitData["childcareSummary"] as? String,
                serviceLength: visitData["serviceLength"] as? String,
                greetingSummary: visitData["greetingSummary"] as? String,
                livestreamPreview: visitData["livestreamPreview"] as? String
            )
        } else {
            firstVisit = nil
        }

        let sundayPlan: ChurchSundayPlanSnapshot?
        if let planData = data["sundayPlan"] as? [String: Any],
           let serviceLabel = planData["serviceLabel"] as? String,
           let driveTimeLabel = planData["driveTimeLabel"] as? String,
           let reminderLabel = planData["reminderLabel"] as? String,
           let parkingLabel = planData["parkingLabel"] as? String,
           let childcareLabel = planData["childcareLabel"] as? String,
           let whatToExpectLabel = planData["whatToExpectLabel"] as? String,
           let directionsLabel = planData["directionsLabel"] as? String {
            sundayPlan = ChurchSundayPlanSnapshot(
                serviceLabel: serviceLabel,
                driveTimeLabel: driveTimeLabel,
                reminderLabel: reminderLabel,
                parkingLabel: parkingLabel,
                childcareLabel: childcareLabel,
                whatToExpectLabel: whatToExpectLabel,
                directionsLabel: directionsLabel
            )
        } else {
            sundayPlan = nil
        }

        return RankedChurchResponse(
            churchId: churchId,
            score: data["score"] as? Int ?? Int((data["score"] as? Double ?? 0).rounded()),
            reason: data["reason"] as? String ?? "Recommended for you",
            reasonDetails: data["reasonDetails"] as? [String] ?? [],
            tags: data["tags"] as? [String] ?? [],
            nextService: data["nextService"] as? String,
            distance: data["distance"] as? Double,
            live: data["live"] as? Bool ?? false,
            serviceSoon: data["serviceSoon"] as? Bool ?? false,
            bestVisit: data["bestVisit"] as? String,
            fitBreakdown: fitItems,
            socialProof: data["socialProof"] as? [String] ?? [],
            sermon: sermon,
            firstVisit: firstVisit,
            sundayPlan: sundayPlan
        )
    }

    private func buildSnapshot(church: Church, ranked: RankedChurchResponse) -> ChurchRankingSnapshot {
        let doc = rawChurchData[church.id.uuidString]
        let sermon = ranked.sermon ?? sermonsByChurchId[church.id.uuidString]
        let fit = ranked.fitBreakdown.isEmpty ? makeLocalFitBreakdown(for: church, raw: doc) : ranked.fitBreakdown
        let personality = ranked.tags.isEmpty ? derivePersonalityTags(church: church, raw: doc) : ranked.tags
        let firstVisit = ranked.firstVisit ?? deriveFirstVisitSnapshot(church: church, raw: doc)
        let socialProof = ranked.socialProof.isEmpty ? deriveSocialProof(raw: doc) : ranked.socialProof
        let urgencyLabel = ranked.live ? "Live now" : (ranked.serviceSoon ? "Starts soon" : ranked.nextService)
        let sundayPlan = ranked.sundayPlan ?? makeSundayPlan(for: church, firstVisit: firstVisit)

        return ChurchRankingSnapshot(
            churchId: church.id,
            score: ranked.score,
            reason: ranked.reason,
            reasonDetails: ranked.reasonDetails.isEmpty ? [ranked.reason] : ranked.reasonDetails,
            urgencyLabel: urgencyLabel,
            bestVisitSummary: ranked.bestVisit ?? deriveBestVisitSummary(church: church, raw: doc, firstVisit: firstVisit),
            fitBreakdown: fit,
            personalityTags: personality,
            socialProof: socialProof,
            sermon: sermon,
            firstVisit: firstVisit,
            sundayPlan: sundayPlan,
            isLiveNow: ranked.live,
            isStartingSoon: ranked.serviceSoon
        )
    }

    private func applyFallbackRanking(churches: [Church], query: String, intent: String, firstVisitMode: Bool) {
        let locallyRanked = churches.map { church -> (Church, Int) in
            refreshLocalSnapshot(for: church)
            var score = snapshots[church.id]?.score ?? 50
            if firstVisitMode, snapshots[church.id]?.firstVisit != nil {
                score += 10
            }
            if !query.isEmpty, searchAndSort([church], query: query).first != nil {
                score += 8
            }
            if intent == "family", snapshots[church.id]?.personalityTags.contains("Family-centered") == true {
                score += 10
            }
            return (church, score)
        }

        orderedChurchIds = locallyRanked.sorted { $0.1 > $1.1 }.map { $0.0.id }
    }

    private func refreshLocalSnapshot(for church: Church) {
        let raw = rawChurchData[church.id.uuidString]
        let fit = makeLocalFitBreakdown(for: church, raw: raw)
        let personality = derivePersonalityTags(church: church, raw: raw)
        let firstVisit = deriveFirstVisitSnapshot(church: church, raw: raw)
        let sermon = sermonsByChurchId[church.id.uuidString]
        let score = min(99, max(55, localBaseScore(for: church, raw: raw, fit: fit, firstVisit: firstVisit)))

        snapshots[church.id] = ChurchRankingSnapshot(
            churchId: church.id,
            score: score,
            reason: localReason(for: church, personality: personality, firstVisit: firstVisit),
            reasonDetails: [
                localReason(for: church, personality: personality, firstVisit: firstVisit),
                church.distanceValue <= 5 ? "Close enough for a consistent Sunday rhythm." : "Worth the drive if the fit matters most.",
            ],
            urgencyLabel: church.nextServiceCountdown ?? church.shortServiceTime,
            bestVisitSummary: deriveBestVisitSummary(church: church, raw: raw, firstVisit: firstVisit),
            fitBreakdown: fit,
            personalityTags: personality,
            socialProof: deriveSocialProof(raw: raw),
            sermon: sermon,
            firstVisit: firstVisit,
            sundayPlan: makeSundayPlan(for: church, firstVisit: firstVisit),
            isLiveNow: isLikelyLiveNow(church),
            isStartingSoon: church.nextServiceCountdown?.lowercased().contains("starts in") == true
        )
    }

    private func localBaseScore(
        for church: Church,
        raw: [String: Any]?,
        fit: [ChurchFitBreakdownItem],
        firstVisit: ChurchFirstVisitSnapshot?
    ) -> Int {
        var total = 58
        if church.distanceValue <= 3 { total += 18 }
        else if church.distanceValue <= 8 { total += 10 }
        if fit.contains(where: { $0.title == "Teaching" && $0.verdict == "Strong" }) { total += 10 }
        if fit.contains(where: { $0.title == "Family fit" && $0.verdict == "Strong" }) { total += 8 }
        if firstVisit != nil { total += 6 }
        if (raw?["hasLivestream"] as? Bool) == true { total += 2 }
        return total
    }

    private func localReason(for church: Church, personality: [String], firstVisit: ChurchFirstVisitSnapshot?) -> String {
        if personality.contains("Bible-heavy") {
            return "Matches your preference for Bible teaching."
        }
        if firstVisit != nil {
            return "Strong first-time visitor guidance and a clear Sunday plan."
        }
        if church.distanceValue <= 5 {
            return "Close to you and easy to try this week."
        }
        return "Balanced fit across distance, worship rhythm, and practical visit details."
    }

    private func loadLatestSermon(for churchId: String) async {
        let query = db.collection("churches").document(churchId).collection("sermons").order(by: "publishedAt", descending: true).limit(to: 1)
        guard let snapshot = try? await query.getDocuments(),
              let data = snapshot.documents.first?.data() else {
            return
        }

        let topic = (data["topic"] as? String) ?? (data["title"] as? String) ?? "Recent teaching"
        sermonsByChurchId[churchId] = ChurchSermonSnapshot(
            topic: topic,
            scripture: data["scripture"] as? String ?? data["scriptureReference"] as? String,
            style: data["style"] as? String,
            quote: data["quote"] as? String ?? data["keyQuote"] as? String,
            matchSummary: data["matchSummary"] as? String
        )
    }

    private func startUserContextListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        userContextListener?.remove()
        userContextListener = db.collection("user_context").document(uid).addSnapshotListener { [weak self] snapshot, _ in
            self?.userContext = snapshot?.data() ?? [:]
        }
    }

    private func makeLocalFitBreakdown(for church: Church, raw: [String: Any]?) -> [ChurchFitBreakdownItem] {
        let score = ChurchFitScoreService.shared.computeFitScore(
            user: ChurchFitScoreService.shared.loadUserPreferences(),
            church: ChurchProfileVector(
                denomination: church.denomination,
                serviceStyle: .noPreference,
                distanceMiles: Float(church.distanceValue),
                amenUserCount: raw?["amenUserCount"] as? Int ?? 0
            )
        )

        return [
            ChurchFitBreakdownItem(title: "Teaching", verdict: church.denomination.lowercased().contains("baptist") ? "Strong" : "Medium"),
            ChurchFitBreakdownItem(title: "Worship", verdict: personalityHint(from: raw).contains("Worship-forward") ? "Strong" : "Medium"),
            ChurchFitBreakdownItem(title: "Family fit", verdict: (raw?["hasChildcare"] as? Bool) == true ? "Strong" : ((raw?["hasChildcare"] as? Bool) == false ? "Medium" : "Medium")),
            ChurchFitBreakdownItem(title: "Distance", verdict: church.distanceValue <= 5 ? "Close" : (church.distanceValue <= 12 ? "Manageable" : "Far")),
            ChurchFitBreakdownItem(title: "First-time friendly", verdict: firstTimeFriendlyVerdict(raw: raw, topScore: score.score)),
        ]
    }

    private func derivePersonalityTags(church: Church, raw: [String: Any]?) -> [String] {
        var tags = Set<String>()
        personalityHint(from: raw).forEach { tags.insert($0) }

        let denomination = church.denomination.lowercased()
        if denomination.contains("baptist") || denomination.contains("presbyterian") {
            tags.insert("Bible-heavy")
        }
        if denomination.contains("pentecostal") {
            tags.insert("Charismatic")
            tags.insert("Worship-forward")
        }
        if denomination.contains("catholic") || denomination.contains("methodist") {
            tags.insert("Quiet/traditional")
        }

        if (raw?["hasChildcare"] as? Bool) == true {
            tags.insert("Family-centered")
        }
        if (raw?["youngAdultActive"] as? Bool) == true {
            tags.insert("Young adult active")
        }
        if (raw?["newBelieverFriendly"] as? Bool) == true || (raw?["welcomeTeamActive"] as? Bool) == true {
            tags.insert("New-believer friendly")
        }
        if (raw?["communityServiceFocused"] as? Bool) == true {
            tags.insert("Community-service focused")
        }

        return Array(tags).sorted()
    }

    private func personalityHint(from raw: [String: Any]?) -> [String] {
        if let tags = raw?["personalityTags"] as? [String], !tags.isEmpty {
            return tags
        }
        if let categories = raw?["categories"] as? [String], !categories.isEmpty {
            return categories
        }
        if let tags = raw?["tags"] as? [String], !tags.isEmpty {
            return tags.map { normalizePersonalityTag($0) }
        }
        return []
    }

    private func normalizePersonalityTag(_ raw: String) -> String {
        let lowered = raw.lowercased()
        if lowered.contains("worship") { return "Worship-forward" }
        if lowered.contains("family") { return "Family-centered" }
        if lowered.contains("young") { return "Young adult active" }
        if lowered.contains("charismatic") { return "Charismatic" }
        if lowered.contains("traditional") { return "Quiet/traditional" }
        if lowered.contains("new") { return "New-believer friendly" }
        if lowered.contains("bible") || lowered.contains("expository") { return "Bible-heavy" }
        if lowered.contains("service") || lowered.contains("outreach") { return "Community-service focused" }
        return raw
    }

    private func deriveBestVisitSummary(
        church: Church,
        raw: [String: Any]?,
        firstVisit: ChurchFirstVisitSnapshot?
    ) -> String? {
        let childcare = (raw?["hasChildcare"] as? Bool) == true ? "childcare available" : "childcare details unclear"
        let welcome = (raw?["welcomeTeamActive"] as? Bool) == true ? "welcome team active" : "low-pressure arrival"
        let crowd = (raw?["crowdWindowHint"] as? String) ?? "typically easier than the earliest service"
        return "Best first-time visit: \(church.shortServiceTime) - \(childcare), \(welcome), \(crowd)."
    }

    private func deriveSocialProof(raw: [String: Any]?) -> [String] {
        guard let raw else { return [] }
        var lines: [String] = []

        if let nearbySaved = raw["savedByNearbyCount"] as? Int, nearbySaved > 0 {
            lines.append("\(nearbySaved) people near you saved this church.")
        }
        if let youngAdult = raw["youngAdultAffinity"] as? String, !youngAdult.isEmpty {
            lines.append("Popular with \(youngAdult.lowercased()).")
        }
        if let familySignal = raw["familyAreaSignal"] as? String, !familySignal.isEmpty {
            lines.append(familySignal)
        }
        if let amenFriends = raw["amenFriendCount"] as? Int, amenFriends > 0 {
            lines.append("\(amenFriends) friends from AMEN follow this church.")
        }

        return Array(lines.prefix(3))
    }

    private func deriveFirstVisitSnapshot(church: Church, raw: [String: Any]?) -> ChurchFirstVisitSnapshot? {
        let enhancementGuide = ChurchEnhancementStore.shared.data(for: church.id.uuidString)?.firstVisitGuide
        let serviceLengthMinutes = raw?["serviceLengthMinutes"] as? Int
        let livestream = raw?["livestreamURL"] as? String

        let snapshot = ChurchFirstVisitSnapshot(
            entrance: raw?["entranceInfo"] as? String ?? enhancementGuide?.arrivalTip,
            parking: raw?["parkingInfo"] as? String ?? enhancementGuide?.parking,
            whatToWear: raw?["dressCode"] as? String ?? enhancementGuide?.whatToWear,
            childcareSummary: (raw?["hasChildcare"] as? Bool) == true ? "Children's check-in available." : nil,
            serviceLength: serviceLengthMinutes.map { "\($0)-minute service" },
            greetingSummary: (raw?["welcomeTeamActive"] as? Bool) == true ? "Welcome team usually available near the entrance." : nil,
            livestreamPreview: livestream
        )

        if snapshot.entrance == nil,
           snapshot.parking == nil,
           snapshot.whatToWear == nil,
           snapshot.childcareSummary == nil,
           snapshot.serviceLength == nil,
           snapshot.greetingSummary == nil,
           snapshot.livestreamPreview == nil {
            return nil
        }

        return snapshot
    }

    private func makeSundayPlan(for church: Church, firstVisit: ChurchFirstVisitSnapshot?) -> ChurchSundayPlanSnapshot {
        let driveMinutes = max(8, Int((church.distanceValue * 3.4).rounded()))
        let reminderLead = max(20, driveMinutes + 15)
        return ChurchSundayPlanSnapshot(
            serviceLabel: church.serviceTime,
            driveTimeLabel: "\(driveMinutes) min drive",
            reminderLabel: "Reminder \(reminderLead) min before",
            parkingLabel: firstVisit?.parking ?? "Parking details available in church info",
            childcareLabel: firstVisit?.childcareSummary ?? "Childcare info not listed",
            whatToExpectLabel: firstVisit?.whatToWear ?? "Come as you are",
            directionsLabel: church.address
        )
    }

    private func firstTimeFriendlyVerdict(raw: [String: Any]?, topScore: Int) -> String {
        if (raw?["welcomeTeamActive"] as? Bool) == true || (raw?["newBelieverFriendly"] as? Bool) == true {
            return "High"
        }
        return topScore >= 80 ? "Medium" : "Developing"
    }

    private func isLikelyLiveNow(_ church: Church) -> Bool {
        let now = Date()
        let calendar = Calendar.current
        return calendar.component(.weekday, from: now) == 1 && (8...13).contains(calendar.component(.hour, from: now))
    }

    private func matches(need: ChurchSearchNeed, church: Church, snapshot: ChurchRankingSnapshot?) -> Bool {
        switch need {
        case .lonely, .community:
            return snapshot?.personalityTags.contains("Community-service focused") == true ||
                snapshot?.socialProof.contains(where: { $0.localizedCaseInsensitiveContains("community") }) == true
        case .newToFaith:
            return snapshot?.personalityTags.contains("New-believer friendly") == true
        case .deeperTeaching:
            return snapshot?.personalityTags.contains("Bible-heavy") == true ||
                snapshot?.fitBreakdown.contains(where: { $0.title == "Teaching" && $0.verdict == "Strong" }) == true
        case .prayer:
            return snapshot?.personalityTags.contains("Charismatic") == true ||
                snapshot?.sermon?.topic.localizedCaseInsensitiveContains("prayer") == true
        case .kids:
            return snapshot?.personalityTags.contains("Family-centered") == true ||
                snapshot?.firstVisit?.childcareSummary != nil
        }
    }
}

struct ChurchPersonalityTagRow: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(Color(red: 0.28, green: 0.28, blue: 0.28))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.78)))
                            .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 0.7))
                    }
                }
            }
        }
    }
}

struct ChurchFitBreakdownCard: View {
    let score: Int
    let items: [ChurchFitBreakdownItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(score)% Match")
                .font(.systemScaled(16, weight: .bold))
                .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.18))

            ForEach(items) { item in
                HStack {
                    Text(item.title)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.verdict)
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.18))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.05), lineWidth: 0.8))
        )
    }
}

struct ChurchBestVisitCard: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Best Time to Visit")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(summary)
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.05), lineWidth: 0.8))
        )
    }
}

struct ChurchSocialProofCard: View {
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ask People Like Me")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(Color(red: 0.22, green: 0.22, blue: 0.22))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.05), lineWidth: 0.8))
            )
        }
    }
}

struct ChurchSermonIntelligenceCard: View {
    let sermon: ChurchSermonSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sermon Intelligence")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(sermon.topic)
                .font(.systemScaled(14, weight: .bold))
                .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.18))

            if let scripture = sermon.scripture {
                Text(scripture)
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let style = sermon.style {
                Text("Style: \(style)")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(Color(red: 0.22, green: 0.22, blue: 0.22))
            }

            if let quote = sermon.quote {
                Text("\"\(quote)\"")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(Color(red: 0.28, green: 0.28, blue: 0.28))
                    .italic()
            }

            if let matchSummary = sermon.matchSummary {
                Text(matchSummary)
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.05), lineWidth: 0.8))
        )
    }
}

struct ChurchFirstVisitModeCard: View {
    let snapshot: ChurchFirstVisitSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("First-Time Visitor Mode")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.secondary)

            if let entrance = snapshot.entrance {
                Text("Entrance: \(entrance)")
                    .font(.systemScaled(12, weight: .medium))
            }
            if let parking = snapshot.parking {
                Text("Parking: \(parking)")
                    .font(.systemScaled(12, weight: .medium))
            }
            if let wear = snapshot.whatToWear {
                Text("What to wear: \(wear)")
                    .font(.systemScaled(12, weight: .medium))
            }
            if let childcare = snapshot.childcareSummary {
                Text(childcare)
                    .font(.systemScaled(12, weight: .medium))
            }
            if let serviceLength = snapshot.serviceLength {
                Text(serviceLength)
                    .font(.systemScaled(12, weight: .medium))
            }
            if let greeting = snapshot.greetingSummary {
                Text(greeting)
                    .font(.systemScaled(12, weight: .medium))
            }
            if let livestream = snapshot.livestreamPreview {
                Text("Livestream: \(livestream)")
                    .font(.systemScaled(12, weight: .medium))
            }
        }
        .foregroundStyle(Color(red: 0.22, green: 0.22, blue: 0.22))
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.05), lineWidth: 0.8))
        )
    }
}

struct ChurchSundayPlanCard: View {
    let plan: ChurchSundayPlanSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan My Sunday")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.secondary)

            Group {
                Text(plan.serviceLabel)
                Text(plan.driveTimeLabel)
                Text(plan.reminderLabel)
                Text(plan.parkingLabel)
                Text(plan.childcareLabel)
                Text(plan.whatToExpectLabel)
                Text(plan.directionsLabel)
            }
            .font(.systemScaled(12, weight: .medium))
            .foregroundStyle(Color(red: 0.22, green: 0.22, blue: 0.22))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.05), lineWidth: 0.8))
        )
    }
}
