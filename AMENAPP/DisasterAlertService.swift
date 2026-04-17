// DisasterAlertService.swift
// AMEN App — AI-powered faith-based disaster/crisis alert system
// Calls bereanChatProxy with the disaster system prompt, parses JSON, writes to Firestore.

import Foundation
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth

// MARK: - DisasterAlertService

actor DisasterAlertService {
    static let shared = DisasterAlertService()
    private init() {}

    private lazy var db = Firestore.firestore()

    // MARK: - System Prompt

    private let systemPrompt = """
    You are the AMEN Disaster Response AI. When given a disaster event, you generate a structured JSON \
    response with:
    1. A brief, compassionate community alert (2-3 sentences)
    2. A relevant Scripture for hope/comfort
    3. Specific, actionable calls to action (pray, donate, volunteer, check-in)
    4. Curated resources (verified relief orgs)
    5. A faith-centered message of hope

    Always respond with ONLY valid JSON in this exact structure:
    {
      "id": "disaster_[timestamp]",
      "title": "Event Title",
      "location": "City, State/Country",
      "alertMessage": "2-3 sentence compassionate alert",
      "urgencyLevel": "critical|high|moderate",
      "scripture": {
        "reference": "Book Chapter:Verse",
        "text": "verse text",
        "translation": "NIV"
      },
      "callsToAction": [
        {"type": "pray|donate|volunteer|checkIn", "label": "Label", "url": "https://..."}
      ],
      "resources": [
        {"name": "Org Name", "role": "Role", "url": "https://...", "phone": "1-800-XXX-XXXX"}
      ],
      "hopeMessage": "1-2 sentences of faith-centered hope",
      "prayerCount": 0,
      "isActive": true
    }
    No markdown, no preamble.
    """

    // MARK: - Generate Alert

    /// Generate a disaster alert from an event description and write it to Firestore.
    /// Returns the created DisasterAlert document ID.
    @discardableResult
    func generateAndSaveAlert(
        eventDescription: String,
        location: String,
        urgency: String = "high"
    ) async throws -> String {
        let userMessage = """
        Generate a disaster response for: \(eventDescription) in \(location). \
        Urgency level: \(urgency). \
        Include verified relief organizations and a Scripture that speaks to this crisis.
        """

        let payload: [String: Any] = [
            "systemPrompt": systemPrompt,
            "userMessage": userMessage,
            "maxTokens": 600
        ]

        let result = try await Functions.functions()
            .httpsCallable("bereanChatProxy")
            .call(payload)

        guard let dict = result.data as? [String: Any],
              let rawText = dict["text"] as? String else {
            throw NSError(domain: "DisasterAlert", code: 1001,
                          userInfo: [NSLocalizedDescriptionKey: "Bad server response"])
        }

        // Strip markdown fences
        var cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let parts = cleaned.components(separatedBy: "```")
            cleaned = parts.first(where: { !$0.isEmpty && !$0.hasPrefix("json") }) ?? cleaned
        }
        // Extract JSON object
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "DisasterAlert", code: 1002,
                          userInfo: [NSLocalizedDescriptionKey: "JSON parse failed"])
        }

        // Stamp server timestamp
        let docId = "disaster_\(Int(Date().timeIntervalSince1970))"
        json["id"] = docId
        json["createdAt"] = FieldValue.serverTimestamp()
        json["prayerCount"] = 0
        json["isActive"] = true

        try await db.collection("disasters").document(docId).setData(json)
        return docId
    }

    // MARK: - Fetch Active Alerts

    /// Fetches active disaster alerts, ordered by creation time descending.
    func fetchActiveAlerts() async throws -> [[String: Any]] {
        let snapshot = try await db.collection("disasters")
            .whereField("isActive", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 5)
            .getDocuments()
        return snapshot.documents.map { $0.data() }
    }

    // MARK: - Deactivate Alert

    func deactivateAlert(id: String) async throws {
        try await db.collection("disasters").document(id).updateData(["isActive": false])
    }

    // MARK: - Increment Prayer Count

    func prayForDisaster(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let prayerRef = db.collection("disasters").document(id)
            .collection("prayers").document(uid)

        // Idempotent: only count first prayer per user
        let existing = try await prayerRef.getDocument()
        guard !existing.exists else { return }

        let batch = db.batch()
        batch.setData(["prayedAt": FieldValue.serverTimestamp()], forDocument: prayerRef)
        batch.updateData(["prayerCount": FieldValue.increment(Int64(1))],
                         forDocument: db.collection("disasters").document(id))
        try await batch.commit()
    }
}
