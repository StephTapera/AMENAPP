// A11yCoPilotService.swift
// AMEN Universal Accessibility Engine — A8 Accessibility Co-Pilot
// Strictly assistive: helps users understand content, never authors content as a human.

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

@MainActor
final class A11yCoPilotService: ObservableObject {
    static let shared = A11yCoPilotService()

    // MARK: - Model

    struct CoPilotHint: Identifiable, Codable {
        let id: String
        let text: String
        let actionLabel: String?
        let action: CoPilotAction?

        enum CoPilotAction: String, Codable {
            case translate
            case simplify
            case readAloud
            case openFaithIntel
            case addToHighlights
        }
    }

    // MARK: - Published State

    @Published private(set) var hints: [CoPilotHint] = []

    private init() {}

    // MARK: - Refresh Hints

    /// Calls the `a11yContextProxy` Cloud Function and updates `hints`.
    /// No-ops if `a11yCoPilotEnabled` is off.
    /// Records `.contextCardOpened` when the call returns at least one hint.
    func refreshHints(context: String) async {
        guard TrustAccessibilityFeatureFlags.shared.a11yCoPilotEnabled else { return }
        guard !context.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        do {
            let callable = Functions.functions().httpsCallable(
                TrustA11yCallable.a11yContextProxy.rawValue
            )
            let result = try await callable.call(["context": context])

            guard let data = result.data as? [[String: Any]] else { return }

            let decoded: [CoPilotHint] = data.compactMap { dict in
                guard
                    let id = dict["id"] as? String,
                    let text = dict["text"] as? String
                else { return nil }
                let actionLabel = dict["actionLabel"] as? String
                let actionRaw = dict["action"] as? String
                let action = actionRaw.flatMap { CoPilotHint.CoPilotAction(rawValue: $0) }
                return CoPilotHint(id: id, text: text, actionLabel: actionLabel, action: action)
            }

            hints = decoded

            // Record a context-card signal when hints are actually surfaced so the
            // adaptive engine can learn the user benefits from co-pilot assistance.
            if !decoded.isEmpty {
                AccessibilitySignalCollector.shared.recordSignal(.contextCardOpened)
            }
        } catch {
            // Non-critical: silently fail so the main content flow is unaffected.
        }
    }

    // MARK: - Record Hint Action

    /// Maps a CoPilotAction to the corresponding `AccessibilitySignal` and records
    /// it. Call this from the view's `onAction` handler immediately before (or after)
    /// dispatching the real action so the adaptive engine stays in sync.
    func recordHintAction(_ action: CoPilotHint.CoPilotAction) {
        let signal: AccessibilitySignal
        switch action {
        case .translate:       signal = .translated
        case .simplify:        signal = .simplified
        case .readAloud:       signal = .listenedToPost
        case .openFaithIntel:  signal = .contextCardOpened
        case .addToHighlights: return   // no corresponding adaptive signal — no-op
        }
        AccessibilitySignalCollector.shared.recordSignal(signal)
    }

    // MARK: - Translate Count (convenience for suggestion engine)

    /// Exposes the current translate-usage count from the on-device signal store so
    /// callers can derive proactive suggestions without importing the collector directly.
    var translateCount: Int {
        AccessibilitySignalCollector.shared.signals.translateCount
    }

    // MARK: - Dismiss Hint

    /// Removes the hint locally and persists the dismissed id to Firestore.
    func dismissHint(id: String, userId: String) async throws {
        hints.removeAll { $0.id == id }
        guard !userId.isEmpty else { return }
        let ref = Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("settings")
            .document("dismissedCoPilotHints")
        try await ref.setData(
            ["dismissedIds": FieldValue.arrayUnion([id])],
            merge: true
        )
    }
}
