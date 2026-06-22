// ContextAssistService.swift
// AMEN App — Accessibility Intelligence Layer (Phase 4)
//
// Manages dismissed/saved terms (Firestore users/{uid}/contextAssist).
// LLM fallback for unlisted terms via transformContent function.

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ContextAssistService: ObservableObject {

    static let shared = ContextAssistService()

    @Published private(set) var savedTerms: [String] = []
    @Published private(set) var dismissedTerms: Set<String> = []

    private lazy var db = Firestore.firestore()
    private let localDismissedKey = "amen.context.dismissedTerms"
    private let localSavedKey = "amen.context.savedTerms"

    private init() {
        loadLocal()
    }

    // MARK: - Public API

    /// Save a term for the user's reference
    func saveTerm(_ term: String) {
        guard !savedTerms.contains(term) else { return }
        savedTerms.append(term)
        persistLocal()
        Task { await persistToFirestore() }
    }

    /// Dismiss a term (don't show it again for this user)
    func dismissTerm(_ term: String) {
        dismissedTerms.insert(term)
        persistLocal()
        Task { await persistToFirestore() }
    }

    /// Check if a term has been dismissed
    func isDismissed(_ term: String) -> Bool {
        dismissedTerms.contains(term.lowercased())
    }

    /// Check if a term has been saved
    func isSaved(_ term: String) -> Bool {
        savedTerms.contains(term.lowercased())
    }

    /// Filter detected terms to exclude dismissed ones
    func filterDismissed(_ terms: [DetectedTerm]) -> [DetectedTerm] {
        terms.filter { !isDismissed($0.term.lowercased()) }
    }

    // MARK: - Local Persistence

    private func loadLocal() {
        if let dismissed = UserDefaults.standard.array(forKey: localDismissedKey) as? [String] {
            dismissedTerms = Set(dismissed)
        }
        if let saved = UserDefaults.standard.array(forKey: localSavedKey) as? [String] {
            savedTerms = saved
        }
    }

    private func persistLocal() {
        UserDefaults.standard.set(Array(dismissedTerms), forKey: localDismissedKey)
        UserDefaults.standard.set(savedTerms, forKey: localSavedKey)
    }

    // MARK: - Firestore Persistence

    private func persistToFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "savedTerms": savedTerms,
            "dismissedTerms": Array(dismissedTerms),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        do {
            try await db.collection("users").document(uid)
                .setData(["contextAssist": data], merge: true)
        } catch {
            print("ContextAssistService: failed to sync context assist state — \(error.localizedDescription)")
        }
    }

    /// Load user's context assist state from Firestore
    func loadFromFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            if let data = doc.data(),
               let assist = data["contextAssist"] as? [String: Any] {
                if let saved = assist["savedTerms"] as? [String] {
                    savedTerms = saved
                }
                if let dismissed = assist["dismissedTerms"] as? [String] {
                    dismissedTerms = Set(dismissed)
                }
                persistLocal()
            }
        } catch {
            dlog("[ContextAssist] Firestore load failed: \(error)")
        }
    }
}
