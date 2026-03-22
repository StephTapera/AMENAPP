//
//  Feature05_AccountabilityThread.swift
//  AMENAPP
//
//  Accountability Thread — goal-based threads with weekly check-ins,
//  streak tracking, and Claude-generated habit extraction on creation.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import Combine

// MARK: - Models

struct AccountabilityThread: Identifiable {
    let id: String
    let members: [String]
    let goalTitle: String
    let goalDescription: String
    let createdAt: Date
    var streaks: [String: Int]      // uid → streak count
    var lastCheckIn: Date?
    var habits: [String]            // Claude-extracted from goalDescription
}

struct AccountabilityCheckIn: Identifiable {
    let id: String
    let userId: String
    let weekId: String
    let responses: [String: String] // habitKey → response text
    let createdAt: Date
}

// MARK: - Manager

final class AccountabilityThreadManager: ObservableObject {
    static let shared = AccountabilityThreadManager()

    @Published var myThreads: [AccountabilityThread] = []
    @Published var weeklyPrompt: String = ""

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()
    private var listeners: [String: ListenerRegistration] = [:]

    private init() {}

    // MARK: - Create

    func createAccountabilityThread(
        members: [String],
        goalTitle: String,
        goalDescription: String
    ) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { return "" }

        // 1. Ask Claude to extract 3 habits from the goal description
        let habits = await extractHabits(from: goalDescription) ?? ["Habit 1", "Habit 2", "Habit 3"]

        let threadId = UUID().uuidString
        var streaks: [String: Int] = [:]
        for memberId in members { streaks[memberId] = 0 }

        let data: [String: Any] = [
            "members":         members,
            "goalTitle":       goalTitle,
            "goalDescription": goalDescription,
            "habits":          habits,
            "createdAt":       FieldValue.serverTimestamp(),
            "streaks":         streaks,
            "lastCheckIn":     NSNull(),
            "createdBy":       uid,
        ]

        try await db.collection("accountabilityThreads").document(threadId).setData(data)
        dlog("✅ [Accountability] Created thread \(threadId) with habits: \(habits)")
        return threadId
    }

    // MARK: - Check-in

    func submitCheckIn(
        threadId: String,
        weekId: String,
        responses: [String: String]
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        try await db
            .collection("accountabilityThreads").document(threadId)
            .collection("checkIns").document(weekId)
            .collection("responses").document(uid)
            .setData([
                "userId":    uid,
                "responses": responses,
                "createdAt": FieldValue.serverTimestamp(),
            ])

        // Update lastCheckIn on the thread
        try await db.collection("accountabilityThreads").document(threadId).updateData([
            "lastCheckIn": FieldValue.serverTimestamp(),
        ])

        dlog("✅ [Accountability] Check-in submitted for week \(weekId)")
    }

    // MARK: - Listen

    func listenToThread(threadId: String) {
        guard listeners[threadId] == nil else { return }

        let listener = db.collection("accountabilityThreads").document(threadId)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let d = snap?.data() else { return }
                let thread = AccountabilityThread(
                    id:              snap!.documentID,
                    members:         d["members"]         as? [String] ?? [],
                    goalTitle:       d["goalTitle"]       as? String   ?? "",
                    goalDescription: d["goalDescription"] as? String   ?? "",
                    createdAt:       (d["createdAt"]      as? Timestamp)?.dateValue() ?? Date(),
                    streaks:         d["streaks"]         as? [String: Int] ?? [:],
                    lastCheckIn:     (d["lastCheckIn"]    as? Timestamp)?.dateValue(),
                    habits:          d["habits"]          as? [String] ?? []
                )
                DispatchQueue.main.async {
                    self.myThreads.removeAll { $0.id == threadId }
                    self.myThreads.append(thread)
                }
            }
        listeners[threadId] = listener
    }

    func stopListening(threadId: String) {
        listeners[threadId]?.remove()
        listeners.removeValue(forKey: threadId)
    }

    // MARK: - Fetch weekly prompt

    func fetchWeeklyPrompt(threadId: String, weekId: String) async {
        let doc = try? await db
            .collection("accountabilityThreads").document(threadId)
            .collection("weeklyPrompts").document(weekId)
            .getDocument()
        guard let text = doc?.data()?["question"] as? String else { return }
        await MainActor.run { weeklyPrompt = text }
    }

    // MARK: - Private: Claude habit extraction

    private func extractHabits(from description: String) async -> [String]? {
        let payload: [String: Any] = [
            "model":      "claude-sonnet-4-6",
            "max_tokens": 128,
            "messages": [[
                "role": "user",
                "content": "Extract exactly 3 measurable habit categories from this goal: '\(description)'. Return only JSON: {\"habits\":[\"habit1\",\"habit2\",\"habit3\"]}"
            ]],
        ]
        do {
            let result = try await functions.httpsCallable("bereanGenericProxy").call(payload)
            guard let dict = result.data as? [String: Any],
                  let text = dict["text"] as? String,
                  let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let habits = json["habits"] as? [String]
            else { return nil }
            return habits
        } catch {
            dlog("⚠️ [Accountability] habit extraction error: \(error.localizedDescription)")
            return nil
        }
    }
}
