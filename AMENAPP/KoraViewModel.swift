// KoraViewModel.swift
// AMENAPP
//
// ViewModel for the Kora spiritual accountability circles feature.

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
class KoraViewModel: ObservableObject {

    @Published var circles: [KoraCircle] = []
    @Published var activeCheckIns: [KoraCheckIn] = []
    @Published var isLoading: Bool = false

    private lazy var db = Firestore.firestore()
    private var circleListener: ListenerRegistration?

    // MARK: - Circles

    func loadCircles() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        circleListener?.remove()
        circleListener = db.collection("koraCircles")
            .whereField("memberIds", arrayContains: uid)
            .order(by: "nextCheckInAt")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    dlog("KoraViewModel: loadCircles error: \(error)")
                    Task { @MainActor in self.isLoading = false }
                    return
                }
                let decoded = snapshot?.documents.compactMap { doc -> KoraCircle? in
                    try? doc.data(as: KoraCircle.self)
                } ?? []
                Task { @MainActor in
                    self.circles = decoded
                    self.isLoading = false
                    await self.refreshActiveCheckIns()
                }
            }
    }

    private func refreshActiveCheckIns() async {
        var open: [KoraCheckIn] = []
        for circle in circles {
            guard let circleId = circle.id else { continue }
            let fetched = await loadCheckIns(for: circleId)
            let openOnes = fetched.filter { $0.status == .open }
            open.append(contentsOf: openOnes)
        }
        activeCheckIns = open
    }

    func createCircle(
        name: String,
        purpose: KoraPurpose,
        rhythm: KoraRhythm,
        dayOfWeek: Int?,
        hour: Int?,
        isPrivate: Bool,
        memberIds: [String],
        coverColorHex: String
    ) async throws -> KoraCircle {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw KoraError.notAuthenticated
        }

        var allMembers = memberIds
        if !allMembers.contains(uid) { allMembers.insert(uid, at: 0) }

        let nextCheckIn = nextCheckInDate(rhythm: rhythm, dayOfWeek: dayOfWeek, hour: hour)

        var circle = KoraCircle(
            workspaceId: "default",
            name: name,
            purpose: purpose,
            memberIds: allMembers,
            memberCount: allMembers.count,
            rhythmType: rhythm,
            rhythmDayOfWeek: dayOfWeek,
            rhythmHour: hour,
            aiCheckInEnabled: true,
            lastCheckInAt: nil,
            nextCheckInAt: nextCheckIn,
            coverColorHex: coverColorHex,
            isPrivate: isPrivate,
            createdAt: Date()
        )

        let ref = try db.collection("koraCircles").addDocument(from: circle)
        circle.id = ref.documentID
        dlog("KoraViewModel: created circle \(ref.documentID)")
        return circle
    }

    private func nextCheckInDate(rhythm: KoraRhythm, dayOfWeek: Int?, hour: Int?) -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
        comps.hour = hour ?? 9
        comps.minute = 0
        comps.second = 0
        if let base = cal.date(from: comps) {
            return base.addingTimeInterval(TimeInterval(rhythm.days * 86400))
        }
        return now.addingTimeInterval(TimeInterval(rhythm.days * 86400))
    }

    // MARK: - Check-ins

    func loadCheckIns(for circleId: String) async -> [KoraCheckIn] {
        do {
            let snapshot = try await db.collection("koraCheckIns")
                .whereField("circleId", isEqualTo: circleId)
                .order(by: "openedAt", descending: true)
                .limit(to: 20)
                .getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: KoraCheckIn.self) }
        } catch {
            dlog("KoraViewModel: loadCheckIns error: \(error)")
            return []
        }
    }

    func submitResponse(
        checkInId: String,
        circleId: String,
        responseText: String,
        mood: KoraMood,
        isPrivate: Bool
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw KoraError.notAuthenticated
        }
        let response = KoraCheckInResponse(
            checkInId: checkInId,
            circleId: circleId,
            authorId: uid,
            responseText: responseText,
            mood: mood,
            isPrivate: isPrivate,
            createdAt: Date()
        )
        try db.collection("koraCheckInResponses").addDocument(from: response)
        dlog("KoraViewModel: submitted response for checkIn \(checkInId)")
    }

    func generateCheckInQuestion(for circle: KoraCircle) async -> String {
        let systemPrompt = """
        You are a compassionate spiritual guide helping a small group called "\(circle.name)" \
        focused on \(circle.purpose.label). Generate a single, open-ended check-in question \
        that encourages honest, faith-centered reflection. Keep it warm, personal, and under 30 words. \
        Return only the question text, nothing else.
        """
        let userMessage = "Generate a check-in question for this group."
        do {
            let functions = Functions.functions()
            let result = try await functions.httpsCallable("bereanChatProxy").call([
                "systemPrompt": systemPrompt,
                "userMessage": userMessage,
                "maxTokens": 80
            ])
            if let data = result.data as? [String: Any],
               let text = data["text"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            dlog("KoraViewModel: generateCheckInQuestion error: \(error)")
        }
        return "How has your faith journey been this week?"
    }

    // MARK: - Journal

    func loadJournalEntries(circleId: String) async -> [KoraJournalEntry] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        do {
            let snapshot = try await db.collection("koraJournalEntries")
                .whereField("circleId", isEqualTo: circleId)
                .whereField("authorId", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .limit(to: 30)
                .getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: KoraJournalEntry.self) }
        } catch {
            dlog("KoraViewModel: loadJournalEntries error: \(error)")
            return []
        }
    }

    func submitJournalEntry(
        circleId: String,
        content: String,
        sharedWith: KoraShareScope
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw KoraError.notAuthenticated
        }
        let entry = KoraJournalEntry(
            circleId: circleId,
            authorId: uid,
            content: content,
            sharedWith: sharedWith,
            aiReflection: nil,
            createdAt: Date()
        )
        let ref = try db.collection("koraJournalEntries").addDocument(from: entry)
        dlog("KoraViewModel: submitted journal entry \(ref.documentID)")

        // Generate AI reflection asynchronously and save back
        Task {
            let reflection = await generateJournalReflection(for: content)
            try? await ref.updateData(["aiReflection": reflection])
        }
    }

    private func generateJournalReflection(for content: String) async -> String {
        let systemPrompt = """
        You are a gentle, scripture-grounded spiritual companion. A person has shared a personal \
        journal entry with you. Offer a brief, warm reflection (2-3 sentences) that acknowledges \
        what they shared and points them gently toward scripture or prayer. Be pastoral, not preachy.
        """
        do {
            let functions = Functions.functions()
            let result = try await functions.httpsCallable("bereanChatProxy").call([
                "systemPrompt": systemPrompt,
                "userMessage": content,
                "maxTokens": 150
            ])
            if let data = result.data as? [String: Any],
               let text = data["text"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            dlog("KoraViewModel: generateJournalReflection error: \(error)")
        }
        return "Thank you for sharing your heart. May you find peace and guidance as you seek God."
    }

    // MARK: - Lifecycle

    deinit {
        circleListener?.remove()
    }
}

// MARK: - Errors

enum KoraError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to use Kora."
        }
    }
}
