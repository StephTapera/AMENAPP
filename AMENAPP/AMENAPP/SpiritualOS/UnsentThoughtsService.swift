import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class UnsentThoughtsService: ObservableObject {
    static let shared = UnsentThoughtsService()

    @Published var activeThoughts: [UnsentThought] = []
    @Published var isAnalyzing = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Detection

    // Call from composerTextDidChange — lightweight client-side heuristics only
    func detectRisk(text: String, surface: String) -> [String] {
        var flags: [String] = []
        let lowered = text.lowercased()

        // Late-night (local time)
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 22 || hour <= 4 { flags.append("late_night") }

        // Word length heuristic for rapid typing (caller should throttle)
        if text.count > 200 { flags.append("long_draft") }

        // Conflict language patterns
        let conflictWords = ["you always", "you never", "you're wrong", "that's not fair", "typical", "every time"]
        if conflictWords.contains(where: { lowered.contains($0) }) { flags.append("conflict_language") }

        // Shame language
        let shameWords = ["should be ashamed", "how could you", "pathetic", "disgraceful"]
        if shameWords.contains(where: { lowered.contains($0) }) { flags.append("shame_language") }

        return flags
    }

    // Call backend for deeper analysis (debounce this — don't call on every keystroke)
    func analyzeText(text: String, surface: String) async -> (riskFlags: [String], emotionalIntensity: Double, suggestedAction: String?) {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let clientFlags = detectRisk(text: text, surface: surface)

        do {
            let callable = Functions.functions().httpsCallable("detectUnsentThoughtRisk")
            let result = try await callable.call([
                "textLength": text.count,
                "surface": surface,
                "clientFlags": clientFlags,
                "hourOfDay": Calendar.current.component(.hour, from: Date())
            ])

            if let data = result.data as? [String: Any] {
                let flags = data["riskFlags"] as? [String] ?? clientFlags
                let intensity = data["emotionalIntensityScore"] as? Double ?? 0.0
                let action = data["suggestedAction"] as? String
                return (flags, intensity, action)
            }
        } catch {
            // Fallback: use client-side flags only
        }

        let intensity = Double(clientFlags.count) / 5.0
        return (clientFlags, min(intensity, 1.0), clientFlags.isEmpty ? nil : "run_peace_check")
    }

    // MARK: - CRUD

    func saveThought(draftText: String, surface: String, flags: [String], intensity: Double, suggestedAction: String?) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let thought = UnsentThought(
            id: nil,
            userId: uid,
            sourceSurface: surface,
            draftText: draftText,
            emotionalIntensityScore: intensity,
            riskFlags: flags,
            suggestedAction: suggestedAction,
            resolvedAt: nil,
            resolutionType: nil
        )

        do {
            _ = try db.collection("users").document(uid).collection("unsentThoughts").addDocument(from: thought)
        } catch {
            // Silent — this is a private signal, not critical path
        }
    }

    func resolveThought(_ thought: UnsentThought, resolutionType: String) async {
        guard let uid = Auth.auth().currentUser?.uid, let id = thought.id else { return }

        do {
            try await db.collection("users").document(uid)
                .collection("unsentThoughts").document(id)
                .updateData([
                    "resolvedAt": FieldValue.serverTimestamp(),
                    "resolutionType": resolutionType
                ])
        } catch {
            // Silent
        }
    }

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("users").document(uid)
            .collection("unsentThoughts")
            .whereField("resolvedAt", isEqualTo: NSNull())
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                self.activeThoughts = docs.compactMap { try? $0.data(as: UnsentThought.self) }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }
}
