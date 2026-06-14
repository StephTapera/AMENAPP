// BereanGroupNotebookService.swift
// AMEN App — Berean Notebooks at Table scope: shared highlights + discussion guide generation
//
// SECURITY FIX (Adversarial Audit — Attack 3):
//   sharedNotebook(for:) now verifies that the current user is a member of the Table
//   before opening a Firestore listener. Non-members receive notAMember immediately.
//   Previously, any authenticated user who knew a tableId could read all entries.
//
// Flag gate: AMENFeatureFlags.shared.bereanNotebooksGroups

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - DiscussionGuide

struct DiscussionGuide: Codable {
    var tableId: String
    var questions: [String]   // 3-5 discussion questions
    var themes: [String]      // emerging themes from highlights
    var generatedAt: Date
}

// MARK: - NotebookEntry

struct NotebookEntry: Codable, Identifiable {
    var id: String
    var uid: String
    var highlight: String
    var createdAt: Date
}

// MARK: - BereanGroupNotebookService

@MainActor
final class BereanGroupNotebookService: ObservableObject {

    static let shared = BereanGroupNotebookService()

    private let db = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "us-east1")

    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {}

    // MARK: - Ingest Highlight

    /// Ingests a highlight into the shared notebook for a Table.
    func ingestHighlight(_ highlight: String, tableId: String, uid: String) async throws {
        guard AMENFeatureFlags.shared.bereanNotebooksGroups else { return }
        guard !highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let entry: [String: Any] = [
            "uid": uid,
            "highlight": highlight,
            "createdAt": FieldValue.serverTimestamp()
        ]

        try await db
            .collection("tables")
            .document(tableId)
            .collection("notebookEntries")
            .addDocument(data: entry)
    }

    // MARK: - Generate Discussion Guide

    /// Calls the `generateDiscussionGuide` Cloud Function to produce a discussion guide.
    func generateDiscussionGuide(tableId: String) async throws -> DiscussionGuide {
        guard AMENFeatureFlags.shared.bereanNotebooksGroups else {
            throw BereanGroupNotebookError.featureDisabled
        }

        isLoading = true
        defer { isLoading = false }

        let callable = functions.httpsCallable("generateDiscussionGuide")

        do {
            let result = try await callable.call(["tableId": tableId])
            guard let data = result.data as? [String: Any] else {
                throw BereanGroupNotebookError.invalidResponse
            }
            return try decodeGuide(from: data, tableId: tableId)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Membership Verification

    /// Returns true iff the currently authenticated user is a member of the given Table.
    ///
    /// SECURITY INVARIANT: This check must gate all read operations on Table content.
    /// It relies on the "members" array field in the Table document. Firestore rules
    /// provide a parallel server-side enforcement layer.
    private func currentUserIsMember(of tableId: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let tableDoc = try await db.collection("tables").document(tableId).getDocument()
        guard tableDoc.exists, let data = tableDoc.data() else { return false }
        let members = data["members"] as? [String] ?? []
        return members.contains(uid)
    }

    // MARK: - Shared Notebook Stream

    /// Returns an AsyncThrowingStream of notebook entries for a Table, ordered by creation time.
    ///
    /// SECURITY: Verifies that the current user is a member of the Table before attaching
    /// a Firestore listener. Non-members receive BereanGroupNotebookError.notAMember immediately.
    /// This is a client-side defence; Firestore security rules provide the server-side layer.
    func sharedNotebook(for tableId: String) -> AsyncThrowingStream<[NotebookEntry], Error> {
        AsyncThrowingStream { continuation in
            guard AMENFeatureFlags.shared.bereanNotebooksGroups else {
                continuation.finish()
                return
            }

            Task {
                // Membership gate — block non-members before opening any listener.
                do {
                    guard try await currentUserIsMember(of: tableId) else {
                        continuation.finish(throwing: BereanGroupNotebookError.notAMember)
                        return
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                // Member confirmed — attach Firestore listener.
                let listener = self.db
                    .collection("tables")
                    .document(tableId)
                    .collection("notebookEntries")
                    .order(by: "createdAt", descending: false)
                    .addSnapshotListener { snapshot, error in
                        if let error {
                            continuation.finish(throwing: error)
                            return
                        }
                        guard let snapshot else { return }
                        let entries = snapshot.documents.compactMap { doc -> NotebookEntry? in
                            let data = doc.data()
                            guard let uid = data["uid"] as? String,
                                  let highlight = data["highlight"] as? String,
                                  let ts = (data["createdAt"] as? Timestamp)?.dateValue() else {
                                return nil
                            }
                            return NotebookEntry(
                                id: doc.documentID,
                                uid: uid,
                                highlight: highlight,
                                createdAt: ts
                            )
                        }
                        continuation.yield(entries)
                    }

                continuation.onTermination = { _ in listener.remove() }
            }
        }
    }

    // MARK: - Private Helpers

    private func decodeGuide(from data: [String: Any], tableId: String) throws -> DiscussionGuide {
        let questions = data["questions"] as? [String] ?? []
        let themes = data["themes"] as? [String] ?? []
        let generatedAt: Date
        if let ts = data["generatedAt"] as? Timestamp {
            generatedAt = ts.dateValue()
        } else if let epochMs = data["generatedAt"] as? Double {
            generatedAt = Date(timeIntervalSince1970: epochMs / 1000)
        } else {
            generatedAt = Date()
        }
        return DiscussionGuide(
            tableId: data["tableId"] as? String ?? tableId,
            questions: questions,
            themes: themes,
            generatedAt: generatedAt
        )
    }
}

// MARK: - Errors

enum BereanGroupNotebookError: LocalizedError {
    case featureDisabled
    case invalidResponse
    case notAMember

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Berean Notebooks are not enabled."
        case .invalidResponse:
            return "Could not parse the discussion guide response."
        case .notAMember:
            return "You are not a member of this Table."
        }
    }
}
