// BereanVisionService.swift
// AMENAPP — Camera OS
// Berean Vision: the faith layer of Context Lens.
// Point at a Bible, sermon slide, or bulletin → scripture refs, notes, summary, discussion questions.
// Saved to Berean study workspace.

import Foundation
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth

// MARK: - BereanVisionError

enum BereanVisionError: Error, LocalizedError {
    case notAuthenticated
    case scanFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use Berean Vision."
        case .scanFailed(let message):
            return "Berean Vision scan failed: \(message)"
        case .saveFailed(let message):
            return "Could not save to study: \(message)"
        }
    }
}

// MARK: - BereanVisionService

actor BereanVisionService {

    // MARK: Shared instance

    static let shared = BereanVisionService()

    // MARK: Private dependencies

    private lazy var functions = Functions.functions()
    private let db = Firestore.firestore()

    // MARK: - Init

    private init() {}

    // MARK: - Analyze

    /// Calls the `bereanVisionScan` Cloud Function with the pre-extracted OCR text.
    /// Returns a populated `BereanVisionScanResult`, or a safe empty fallback on failure.
    func analyze(imageData: Data, rawOCRText: String) async -> BereanVisionScanResult {
        do {
            let callable = functions.httpsCallable("bereanVisionScan")
            let result = try await callable.call(["text": rawOCRText] as [String: Any])

            guard let data = result.data as? [String: Any] else {
                return emptyResult()
            }

            let scriptureRefs = data["scriptureRefs"] as? [String] ?? []
            let summary = data["summary"] as? String ?? ""
            let studyNotes = data["studyNotes"] as? [String] ?? []
            let discussionQuestions = data["discussionQuestions"] as? [String] ?? []
            let confidence = data["confidence"] as? Double ?? 0.0

            return BereanVisionScanResult(
                scriptureRefs: scriptureRefs,
                summary: summary,
                studyNotes: studyNotes,
                discussionQuestions: discussionQuestions,
                confidence: confidence
            )
        } catch {
            dlog("⚠️ BereanVisionService.analyze: \(error)")
            return emptyResult()
        }
    }

    // MARK: - Save to Study

    /// Persists a scan result to the user's Berean study workspace.
    ///
    /// Firestore layout:
    ///   users/{uid}/bereanProjects/{projectId}        ← project document
    ///   users/{uid}/bereanProjects/{projectId}/memoryEntries/{entryId}  ← entry document
    ///
    /// Throws `BereanVisionError.notAuthenticated` when no user is signed in.
    func saveToStudy(result: BereanVisionScanResult, sourceLabel: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanVisionError.notAuthenticated
        }

        let projectsRef = db
            .collection("users")
            .document(uid)
            .collection("bereanProjects")

        // Upsert a project titled "Camera Vision Notes" — look for an existing one first
        // to avoid proliferating duplicate projects.
        let projectId: String
        do {
            let snapshot = try await projectsRef
                .whereField("title", isEqualTo: "Camera Vision Notes")
                .limit(to: 1)
                .getDocuments()

            if let existing = snapshot.documents.first {
                projectId = existing.documentID
            } else {
                // Create a fresh project document
                let newProjectRef = projectsRef.document()
                let projectData: [String: Any] = [
                    "title": "Camera Vision Notes",
                    "description": "Saved from Camera OS",
                    "status": "active",
                    "visibility": "private",
                    "ownerUid": uid,
                    "tags": ["camera", "vision", "scripture"],
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                try await newProjectRef.setData(projectData)
                projectId = newProjectRef.documentID
            }
        } catch {
            throw BereanVisionError.saveFailed(error.localizedDescription)
        }

        // Build the memory-entry content
        let scriptureSection = result.scriptureRefs.isEmpty
            ? ""
            : "\n\nScripture: \(result.scriptureRefs.joined(separator: ", "))"
        let entryContent = result.summary + scriptureSection

        let entryData: [String: Any] = [
            "entryType": "insight",
            "content": entryContent,
            "projectId": projectId,
            "ownerUid": uid,
            "sourceLabel": sourceLabel,
            "isResolved": false,
            "createdAt": FieldValue.serverTimestamp()
        ]

        do {
            try await db
                .collection("users")
                .document(uid)
                .collection("bereanProjects")
                .document(projectId)
                .collection("memoryEntries")
                .addDocument(data: entryData)
        } catch {
            throw BereanVisionError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Faith Content Detection

    /// Heuristic keyword check — returns true when the text is likely faith-related.
    func isFaithContent(text: String) -> Bool {
        let lower = text.lowercased()
        let faithKeywords: [String] = [
            "scripture", "verse", "john", "matthew", "luke", "acts",
            "psalms", "genesis", "romans", "corinthians", "revelation",
            "sermon", "gospel", "jesus", "christ", "holy spirit", "amen"
        ]
        return faithKeywords.contains { lower.contains($0) }
    }

    // MARK: - Private helpers

    /// A safe, zero-value fallback result for when the CF call fails.
    private func emptyResult() -> BereanVisionScanResult {
        BereanVisionScanResult(
            scriptureRefs: [],
            summary: "",
            studyNotes: [],
            discussionQuestions: [],
            confidence: 0.0
        )
    }
}
