// ONEPrivacyMirrorService.swift
// ONE — Privacy mirror enforcement: controls how visible you are to strangers.
// P4-D | Writes to Firestore /one_users/{uid}. Visibility logic is client-enforced;
//        server-side enforcement via Firestore rules is added in P5 hardening.
//
// Symmetry rule: sealed viewers appear anonymous even to open subjects.
// You cannot ghost-browse without accepting that you are also a ghost.

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ONEPrivacyMirrorService: ObservableObject {

    static let shared = ONEPrivacyMirrorService()

    @Published var currentLevel: ONEPrivacyMirrorLevel = .translucent
    @Published var isUpdating = false

    private let db = Firestore.firestore()
    private init() {}

    // MARK: - Level management

    func updateLevel(_ level: ONEPrivacyMirrorLevel) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isUpdating = true
        defer { isUpdating = false }
        try await db.collection("one_users").document(uid).updateData([
            "privacyMirror": level.rawValue
        ])
        currentLevel = level
    }

    func loadCurrentLevel() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snapshot = try? await db.collection("one_users").document(uid).getDocument()
        if let raw = snapshot?.data()?["privacyMirror"] as? String,
           let level = ONEPrivacyMirrorLevel(rawValue: raw) {
            currentLevel = level
        }
    }

    // MARK: - Visibility logic

    /// Whether a viewer can access a subject's profile given their mirror levels.
    /// Sealed subject = invisible to all strangers. Open subject = visible to all.
    func visibilityGranted(
        viewerLevel: ONEPrivacyMirrorLevel,
        subjectLevel: ONEPrivacyMirrorLevel
    ) -> Bool {
        switch subjectLevel {
        case .sealed:      return false   // sealed subject invisible to all strangers
        case .opaque:      return false   // profile exists but nothing readable
        case .translucent: return viewerLevel != .sealed
        case .open:        return true    // open is visible even to sealed viewers
        }
    }

    /// How a viewer appears to the subjects they browse.
    func viewerIdentityLabel(for viewerLevel: ONEPrivacyMirrorLevel) -> String {
        switch viewerLevel {
        case .sealed:      return "Anonymous"
        case .opaque:      return "Visible as existing"
        case .translucent: return "Name + bio visible"
        case .open:        return "Fully visible"
        }
    }

    // MARK: - UI Metadata

    var symmetryDescription: String {
        switch currentLevel {
        case .sealed:
            return "You browse anonymously. Subjects see no identity trace from you."
        case .opaque:
            return "You exist on the platform, but strangers cannot read your profile."
        case .translucent:
            return "Public authors can see your name and bio when you view their content."
        case .open:
            return "Your full profile is visible to anyone whose content you engage with."
        }
    }
}

// MARK: - ONEPrivacyMirrorLevel view metadata

extension ONEPrivacyMirrorLevel {
    var mirrorDescription: String {
        switch self {
        case .sealed:
            return "Anonymous browsing. You also appear anonymous to the world."
        case .opaque:
            return "Your profile exists but no detail is visible to strangers."
        case .translucent:
            return "Your name and bio are visible. Posts need a witness relationship."
        case .open:
            return "Fully public profile. Anyone can see your content."
        }
    }

    var symmetryNote: String {
        switch self {
        case .sealed:
            return "You appear as \"Anonymous\" to public authors."
        case .opaque:
            return "Authors know you exist but cannot read your profile."
        case .translucent:
            return "Authors see your name and bio."
        case .open:
            return "Authors see your full profile."
        }
    }
}
