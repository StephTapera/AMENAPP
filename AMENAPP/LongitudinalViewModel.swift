// LongitudinalViewModel.swift — AMEN App
// View model for the Longitudinal Self / My Journey feature

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
class LongitudinalViewModel: ObservableObject {
    @Published var profile: LongitudinalProfile = .empty
    @Published var thisDayPost: String?
    @Published var isLoading = false
    @Published var isAnalyzing = false
    @Published var hasSeenOnboarding = false
    @Published var hasGrantedPermission = false

    private lazy var db = Firestore.firestore()

    var hasProfile: Bool { !profile.growthArcs.isEmpty || !profile.topicEvolution.isEmpty }

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        hasSeenOnboarding = UserDefaults.standard.bool(forKey: "longitudinalOnboardingSeen_\(uid)")
        isLoading = true
        defer { isLoading = false }

        do {
            let doc = try await db.collection("longitudinalProfiles").document(uid).getDocument()
            if let p = try? doc.data(as: LongitudinalProfile.self) {
                profile = p
                hasGrantedPermission = true
            }
        } catch {
            dlog("⚠️ LongitudinalViewModel.load: \(error)")
        }

        await fetchThisDayPost(uid: uid)
    }

    private func fetchThisDayPost(uid: String) async {
        let cal = Calendar.current
        let now = Date()
        let month = cal.component(.month, from: now)
        let day   = cal.component(.day,   from: now)

        // Look back 1–3 years for a post on this calendar day
        for yearsBack in 1...3 {
            guard let targetYear = cal.date(byAdding: .year, value: -yearsBack, to: now),
                  let dayStart = cal.date(from: DateComponents(
                      year: cal.component(.year, from: targetYear),
                      month: month, day: day, hour: 0, minute: 0, second: 0)),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let snap = try? await db.collection("posts")
                .whereField("authorId", isEqualTo: uid)
                .whereField("createdAt", isGreaterThanOrEqualTo: Timestamp(date: dayStart))
                .whereField("createdAt", isLessThan: Timestamp(date: dayEnd))
                .limit(to: 1)
                .getDocuments()

            if let doc = snap?.documents.first,
               let content = doc.data()["content"] as? String, !content.isEmpty {
                thisDayPost = String(content.prefix(200))
                return
            }
        }
    }

    func grantPermissionAndAnalyze() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        hasGrantedPermission = true
        hasSeenOnboarding = true
        UserDefaults.standard.set(true, forKey: "longitudinalOnboardingSeen_\(uid)")
        await requestAIAnalysis()
    }

    func requestAIAnalysis() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Fetch recent posts to pass to AI
        let snap = try? await db.collection("posts")
            .whereField("authorId", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 30)
            .getDocuments()

        let postTexts = snap?.documents.compactMap {
            $0.data()["content"] as? String
        }.prefix(20).joined(separator: "\n---\n") ?? "No recent posts."

        let system = """
        You are an AI spiritual growth analyst for AMEN, a Christian social app. \
        Analyze a user's recent posts and identify: \
        1. 2-3 growth arcs (transformations from one state to another) \
        2. Their current "chapter title" (a poetic 3-5 word season description) \
        3. Top themes/topics from their posts \
        4. 1-3 notable milestones (meaningful moments, answered prayers, key turning points) \
        Respond ONLY with valid JSON matching this schema exactly: \
        {"currentChapter":"...","growthArcs":[{"fromState":"...","toState":"...","sfSymbol":"...","summary":"..."}],"topics":["..."],"milestones":[{"id":"1","title":"...","description":"...","sfSymbol":"star.fill"}]}
        """
        let payload: [String: Any] = [
            "systemPrompt": system,
            "userMessage": "Analyze these posts:\n\(postTexts)",
            "maxTokens": 600
        ]

        guard let result = try? await Functions.functions()
            .httpsCallable("bereanChatProxy").call(payload),
              let dict = result.data as? [String: Any],
              let text = dict["text"] as? String,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // Use sample data as fallback
            profile = LongitudinalProfile(
                userId: uid,
                growthArcs: GrowthArc.samples,
                topicEvolution: [],
                milestones: [],
                currentChapter: "Season of Growth",
                isSharedPublicly: false
            )
            return
        }

        let chapter = json["currentChapter"] as? String ?? "A New Season"
        let arcData = json["growthArcs"] as? [[String: Any]] ?? []
        let arcs = arcData.enumerated().map { idx, a in
            GrowthArc(
                id: "\(idx)",
                fromState: a["fromState"] as? String ?? "",
                toState: a["toState"] as? String ?? "",
                sfSymbol: a["sfSymbol"] as? String ?? "arrow.up.heart.fill",
                startDate: nil, endDate: nil,
                relatedPostIds: [],
                summary: a["summary"] as? String ?? ""
            )
        }
        let topics = json["topics"] as? [String] ?? []
        let snapshot = TopicSnapshot(
            id: "\(Int(Date().timeIntervalSince1970))",
            year: Calendar.current.component(.year, from: Date()),
            topTopics: topics,
            emotionalColor: "purple",
            aiChapterTitle: chapter,
            topPostIds: []
        )
        let milestoneData = json["milestones"] as? [[String: Any]] ?? []
        let milestones = milestoneData.map { m in
            JourneyMilestone(
                id: m["id"] as? String ?? UUID().uuidString,
                title: m["title"] as? String ?? "",
                description: m["description"] as? String ?? "",
                date: nil,
                sfSymbol: m["sfSymbol"] as? String ?? "star.fill"
            )
        }

        let p = LongitudinalProfile(
            userId: uid,
            growthArcs: arcs,
            topicEvolution: [snapshot],
            milestones: milestones,
            currentChapter: chapter,
            isSharedPublicly: false
        )
        profile = p
        do {
            try await db.collection("longitudinalProfiles").document(uid).setData(
                try Firestore.Encoder().encode(p)
            )
        } catch {
            print("LongitudinalViewModel: failed to save longitudinal profile — \(error.localizedDescription)")
        }
    }

    func togglePublicSharing() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        profile.isSharedPublicly.toggle()
        do {
            try await db.collection("longitudinalProfiles").document(uid)
                .updateData(["isSharedPublicly": profile.isSharedPublicly])
        } catch {
            print("LongitudinalViewModel: failed to update public sharing — \(error.localizedDescription)")
        }
    }
}
