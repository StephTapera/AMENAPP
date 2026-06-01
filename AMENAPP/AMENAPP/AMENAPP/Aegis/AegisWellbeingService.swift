// AegisWellbeingService.swift — C47–C50 Wellbeing Controls
// Capabilities: hiddenPublicMetrics, antiRageAmplification, antiDoomscroll, memoryResurfacing

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class AegisWellbeingService: ObservableObject {

    static let shared = AegisWellbeingService()

    @Published var state: AegisWellbeingState = AegisWellbeingState(
        userId: "",
        hiddenMetrics: false,
        antiRageEnabled: false,
        doomscrollGuardEnabled: false,
        lateNightFrictionEnabled: false,
        memoryControlsEnabled: false,
        mutedDates: [],
        mutedUserIds: [],
        sessionStartedAt: nil,
        scrollDepthToday: 0
    )

    private let db = Firestore.firestore()

    // Midnight reset timer
    private var midnightTask: Task<Void, Never>?

    private init() {}

    // MARK: - Configure

    func configure(for userId: String) async {
        do {
            let doc = try await db
                .collection("wellbeingState")
                .document(userId)
                .getDocument()

            if doc.exists, let data = doc.data() {
                state = decodeState(from: data, userId: userId)
            } else {
                state = AegisWellbeingState(
                    userId: userId,
                    hiddenMetrics: false,
                    antiRageEnabled: false,
                    doomscrollGuardEnabled: false,
                    lateNightFrictionEnabled: false,
                    memoryControlsEnabled: false,
                    mutedDates: [],
                    mutedUserIds: [],
                    sessionStartedAt: Date(),
                    scrollDepthToday: 0
                )
            }
        } catch {
            // Non-fatal: use defaults
            state = AegisWellbeingState(
                userId: userId,
                hiddenMetrics: false,
                antiRageEnabled: false,
                doomscrollGuardEnabled: false,
                lateNightFrictionEnabled: false,
                memoryControlsEnabled: false,
                mutedDates: [],
                mutedUserIds: [],
                sessionStartedAt: Date(),
                scrollDepthToday: 0
            )
        }

        scheduleMidnightReset()
    }

    // MARK: - Save

    func saveState() async {
        guard !state.userId.isEmpty else { return }
        let encoded = encodeState(state)
        try? await db
            .collection("wellbeingState")
            .document(state.userId)
            .setData(encoded, merge: true)
    }

    // MARK: - C47: Hidden Public Metrics

    /// Returns true when the hidden-metrics flag is enabled AND the user has opted in.
    var shouldHideMetrics: Bool {
        AegisFeatureFlags.shared.isEnabled(.hiddenPublicMetrics) && state.hiddenMetrics
    }

    // MARK: - C48: Anti-Rage Amplification

    /// Filters (deprioritises) engagement-bait posts when anti-rage mode is enabled.
    /// Returns the filtered list (bait posts moved to end, not removed).
    func filterForRageAmplification(_ posts: [String]) -> [String] {
        guard AegisFeatureFlags.shared.isEnabled(.antiRageAmplification),
              state.antiRageEnabled else { return posts }

        let triggerWords = [
            "outrage", "disgusting", "destroyed", "exposing", "shocking", "they don't want you to know",
            "wake up", "unbelievable", "this will make you angry", "you won't believe",
            "mainstream media", "cancel culture", "they're lying",
        ]

        func isBait(_ post: String) -> Bool {
            let text = post
            // Excessive question marks (≥3)
            let questionMarkCount = text.filter { $0 == "?" }.count
            if questionMarkCount >= 3 { return true }

            // ALL CAPS > 40% of alphabetic characters
            let letters = text.filter { $0.isLetter }
            if !letters.isEmpty {
                let upperCount = letters.filter { $0.isUppercase }.count
                if Double(upperCount) / Double(letters.count) > 0.40 { return true }
            }

            // Inflammatory trigger words
            let lower = text.lowercased()
            if triggerWords.contains(where: { lower.contains($0) }) { return true }

            return false
        }

        let normal = posts.filter { !isBait($0) }
        let bait   = posts.filter {  isBait($0) }
        return normal + bait
    }

    // MARK: - C49: Anti-Doomscroll

    /// Returns true if friction (a gentle pause prompt) should be shown.
    func checkDoomscrollFriction(scrollDepth: Int) -> Bool {
        guard AegisFeatureFlags.shared.isEnabled(.antiDoomscroll),
              state.doomscrollGuardEnabled else { return false }

        // Standard deep-scroll threshold
        if scrollDepth > 50 { return true }

        // Late-night threshold (1 AM – 4 AM)
        if state.lateNightFrictionEnabled {
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 1 && hour <= 4 && scrollDepth > 10 { return true }
        }

        return false
    }

    /// Increments the scroll depth counter; resets automatically at midnight.
    func recordScroll() {
        state.scrollDepthToday += 1
    }

    // MARK: - C50: Memory Resurfacing Controls

    /// Returns true if this post should be suppressed from memory/highlight surfaces.
    func shouldSuppressMemory(postDate: Date, involvedUserIds: [String]) -> Bool {
        guard AegisFeatureFlags.shared.isEnabled(.memoryResurfacing),
              state.memoryControlsEnabled else { return false }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        let dateMD = formatter.string(from: postDate)

        if state.mutedDates.contains(dateMD) { return true }
        if involvedUserIds.contains(where: { state.mutedUserIds.contains($0) }) { return true }

        return false
    }

    func muteDate(_ mmdd: String) {
        guard !state.mutedDates.contains(mmdd) else { return }
        state.mutedDates.append(mmdd)
        Task { await saveState() }
    }

    func muteUser(_ userId: String) {
        guard !state.mutedUserIds.contains(userId) else { return }
        state.mutedUserIds.append(userId)
        Task { await saveState() }
    }

    // MARK: - Midnight Reset

    private func scheduleMidnightReset() {
        midnightTask?.cancel()
        midnightTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
                components.day! += 1
                components.hour = 0
                components.minute = 0
                components.second = 0
                guard let midnight = Calendar.current.date(from: components) else { break }
                let interval = midnight.timeIntervalSince(now)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.state.scrollDepthToday = 0
                }
            }
        }
    }

    // MARK: - Codable Helpers

    private func decodeState(from data: [String: Any], userId: String) -> AegisWellbeingState {
        let mutedDates   = data["mutedDates"]   as? [String] ?? []
        let mutedUserIds = data["mutedUserIds"] as? [String] ?? []
        let sessionTs    = (data["sessionStartedAt"] as? Timestamp)?.dateValue()

        return AegisWellbeingState(
            userId: userId,
            hiddenMetrics:          data["hiddenMetrics"]          as? Bool ?? false,
            antiRageEnabled:        data["antiRageEnabled"]        as? Bool ?? false,
            doomscrollGuardEnabled: data["doomscrollGuardEnabled"] as? Bool ?? false,
            lateNightFrictionEnabled: data["lateNightFrictionEnabled"] as? Bool ?? false,
            memoryControlsEnabled:  data["memoryControlsEnabled"]  as? Bool ?? false,
            mutedDates:   mutedDates,
            mutedUserIds: mutedUserIds,
            sessionStartedAt: sessionTs ?? Date(),
            scrollDepthToday: data["scrollDepthToday"] as? Int ?? 0
        )
    }

    private func encodeState(_ s: AegisWellbeingState) -> [String: Any] {
        var d: [String: Any] = [
            "userId":                  s.userId,
            "hiddenMetrics":           s.hiddenMetrics,
            "antiRageEnabled":         s.antiRageEnabled,
            "doomscrollGuardEnabled":  s.doomscrollGuardEnabled,
            "lateNightFrictionEnabled": s.lateNightFrictionEnabled,
            "memoryControlsEnabled":   s.memoryControlsEnabled,
            "mutedDates":              s.mutedDates,
            "mutedUserIds":            s.mutedUserIds,
            "scrollDepthToday":        s.scrollDepthToday,
            "updatedAt":               FieldValue.serverTimestamp(),
        ]
        if let session = s.sessionStartedAt {
            d["sessionStartedAt"] = Timestamp(date: session)
        }
        return d
    }
}
