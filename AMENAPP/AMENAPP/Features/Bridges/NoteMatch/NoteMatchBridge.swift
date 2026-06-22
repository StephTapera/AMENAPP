// NoteMatchBridge.swift
// AMEN — Features/Bridges/NoteMatch
//
// Subscribes to noteThemeDetected signals and adjusts the user's church DNA
// score vector by writing theme deltas to Firestore.
//
// Contract invariants (FROZEN — do not weaken):
//  • Tier-C only — device-local Tier-S signals never reach this bridge
//  • ConsentEdge.notesToMatching checked by ContextBus before signal is fanned out
//  • ContextIntelligenceFlags.noteToBridge must be ON (Remote Config ctx_note_to_give_bridge_enabled)
//  • No vanity metrics exposed here — raw deltas only; score computation is server-side
//  • MatchFeedbackCard is Premium-gated via GateView(.matchFeedbackExplained)

import Foundation
import FirebaseFirestore
import FirebaseAuth
import SwiftUI

// MARK: - NoteMatchBridge

/// Actor that subscribes to `noteThemeDetected` signals and writes theme deltas
/// into `churchDNA/{uid}/themeDeltas`. The church matching score computation
/// running in the backend consumes these deltas server-side.
///
/// Install once from AppDelegate / App init:
/// ```swift
/// Task { await NoteMatchBridge.shared.install() }
/// ```
actor NoteMatchBridge {
    static let shared = NoteMatchBridge()
    private init() {}

    func install() {
        Task {
            let stream = await ContextBus.shared.subscribe(to: [.noteThemeDetected])
            for await signal in stream {
                let isBridgeEnabled = await MainActor.run { ContextIntelligenceFlags.noteToBridge }
                guard isBridgeEnabled else { continue }
                await processThemeSignal(signal)
            }
        }
    }

    // MARK: - Private

    private func processThemeSignal(_ signal: ContextSignal) async {
        // Extract theme taxonomy from signal payload.
        guard
            let themeRaw = signal.payload["theme"]?.stringValue,
            let noteID = signal.subjectRefs.first(where: { $0.nodeType == .note })?.nodeID
        else { return }

        guard let uid = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        let delta: [String: Any] = [
            "theme": themeRaw,
            "noteID": noteID,
            "delta": 1.0,
            "occurredAt": FieldValue.serverTimestamp()
        ]

        // Fire-and-forget — failures are non-fatal; delta will be retried on next
        // note save if the user re-saves content with the same theme.
        _ = try? await db
            .collection("churchDNA")
            .document(uid)
            .collection("themeDeltas")
            .addDocument(data: delta)
    }
}

// MARK: - AnyCodableValue helpers (local convenience — do NOT duplicate in other files)

extension AnyCodableValue {
    /// Returns the associated String if this value is `.string(_)`, otherwise nil.
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Returns the associated Double if this value is `.double(_)` or `.int(_)`.
    var doubleValue: Double? {
        if case .double(let d) = self { return d }
        if case .int(let i) = self { return Double(i) }
        return nil
    }
}

// MARK: - MatchFeedbackCard

/// Shows a single line explaining why a church-match score changed.
/// Wrapped in `GateView(.matchFeedbackExplained)` — renders EmptyView for free
/// tier and EmptyView during crisis dampening (EntitlementGate handles both).
struct MatchFeedbackCard: View {
    let explanation: String

    var body: some View {
        GateView(.matchFeedbackExplained) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.tint)
                Text(explanation)
                    .font(.caption)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        } locked: { _ in
            // Intentionally empty — premium card; no upsell in this surface.
            EmptyView()
        }
    }
}
