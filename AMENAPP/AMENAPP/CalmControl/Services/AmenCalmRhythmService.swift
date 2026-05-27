import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import SwiftUI

@MainActor
final class AmenCalmRhythmService: ObservableObject {
    static let shared = AmenCalmRhythmService()

    @Published var rhythm = AmenSpiritualRhythm()
    @Published var streaks: [AmenSpiritualActivityType: AmenStreakState] = [:]
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var uid: String? { Auth.auth().currentUser?.uid }

    private init() {}

    // MARK: - Load All

    func loadAll() async {
        guard let uid else { return }
        isLoading = true
        defer { isLoading = false }
        async let r: () = loadRhythm(uid: uid)
        async let s: () = loadStreaks(uid: uid)
        _ = await (r, s)
    }

    // MARK: - Rhythm

    func loadRhythm(uid: String) async {
        do {
            let doc = try await db.collection("users").document(uid)
                .collection("spiritualRhythm").document("main").getDocument()
            if let data = doc.data() {
                rhythm = try Firestore.Decoder().decode(AmenSpiritualRhythm.self, from: data)
            }
        } catch {
            dlog("⚠️ AmenCalmRhythmService.loadRhythm: \(error)")
        }
    }

    // MARK: - Streaks

    func loadStreaks(uid: String) async {
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("streaks").getDocuments()
            for doc in snapshot.documents {
                if let type = AmenSpiritualActivityType(rawValue: doc.documentID),
                   let streak = try? Firestore.Decoder().decode(AmenStreakState.self, from: doc.data()) {
                    streaks[type] = streak
                }
            }
            // Seed defaults for any missing activity types
            for type in AmenSpiritualActivityType.allCases where streaks[type] == nil {
                streaks[type] = .empty(type)
            }
        } catch {
            dlog("⚠️ AmenCalmRhythmService.loadStreaks: \(error)")
        }
    }

    // MARK: - Record Activity

    func recordActivity(_ type: AmenSpiritualActivityType) async {
        guard let uid else { return }
        do {
            let callable = Functions.functions().httpsCallable("recordSpiritualActivity")
            _ = try await callable.call(["activityType": type.rawValue, "userId": uid])
            rhythm.lastActivityAt = Date()
            await loadStreaks(uid: uid)
            await updateMomentumLabel()
        } catch {
            dlog("⚠️ AmenCalmRhythmService.recordActivity: \(error)")
        }
    }

    // MARK: - Sabbath Mode

    func setSabbathMode(enabled: Bool) async {
        guard let uid else { return }
        rhythm.sabbathModeEnabled = enabled
        do {
            try await db.collection("users").document(uid)
                .collection("spiritualRhythm").document("main")
                .setData(
                    ["sabbathModeEnabled": enabled, "updatedAt": FieldValue.serverTimestamp()],
                    merge: true
                )
        } catch {
            dlog("⚠️ AmenCalmRhythmService.setSabbathMode: \(error)")
        }
    }

    // MARK: - Streak Recovery

    func recoverStreak(type: AmenSpiritualActivityType) async {
        guard let uid else { return }
        do {
            let callable = Functions.functions().httpsCallable("calculateStreakState")
            _ = try await callable.call(["streakType": type.rawValue, "action": "recover", "userId": uid])
            await loadStreaks(uid: uid)
        } catch {
            dlog("⚠️ AmenCalmRhythmService.recoverStreak: \(error)")
        }
    }

    // MARK: - Momentum

    func updateMomentumLabel() async {
        guard let uid else { return }
        let label = computeMomentum()
        rhythm.privateMomentumState = label
        do {
            try await db.collection("users").document(uid)
                .collection("spiritualRhythm").document("main")
                .setData(["privateMomentumState": label.rawValue], merge: true)
        } catch {
            dlog("⚠️ AmenCalmRhythmService.updateMomentumLabel: \(error)")
        }
    }

    private func computeMomentum() -> AmenSpiritualMomentumState {
        if rhythm.isInactiveSeven { return .resting }
        let avg = streaks.values.map(\.currentCount).reduce(0, +) / max(streaks.count, 1)
        if avg >= 14 { return .grounded }
        if avg >= 7 { return .growing }
        return .reflecting
    }

    // MARK: - Inactivity Policy

    func checkInactivityPolicy() async {
        guard let uid else { return }
        if rhythm.isInactiveSeven && !rhythm.inactiveNoticeSent {
            do {
                let callable = Functions.functions().httpsCallable("pauseInactiveUserNotifications")
                _ = try await callable.call(["userId": uid])
                rhythm.inactiveNoticeSent = true
                rhythm.notificationsPausedDueToInactivity = true
                try await db.collection("users").document(uid)
                    .collection("spiritualRhythm").document("main")
                    .setData(
                        ["inactiveNoticeSent": true, "notificationsPausedDueToInactivity": true],
                        merge: true
                    )
            } catch {
                dlog("⚠️ AmenCalmRhythmService.checkInactivityPolicy: \(error)")
            }
        }
    }

    func restoreAfterReturn() async {
        guard let uid else { return }
        do {
            let callable = Functions.functions().httpsCallable("restoreUserAfterInactivity")
            _ = try await callable.call(["userId": uid])
            rhythm.inactiveNoticeSent = false
            rhythm.notificationsPausedDueToInactivity = false
            rhythm.lastActivityAt = Date()
            await loadRhythm(uid: uid)
        } catch {
            dlog("⚠️ AmenCalmRhythmService.restoreAfterReturn: \(error)")
        }
    }

    // MARK: - Convenience

    func streak(for type: AmenSpiritualActivityType) -> AmenStreakState {
        streaks[type] ?? .empty(type)
    }
}

private func dlog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}
