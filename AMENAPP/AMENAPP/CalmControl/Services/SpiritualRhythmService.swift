import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import SwiftUI

@MainActor
final class SpiritualRhythmService: ObservableObject {
    static let shared = SpiritualRhythmService()

    @Published var rhythm = AmenSpiritualRhythm()
    @Published var streaks: [AmenStreakType: AmenStreak] = [:]
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var uid: String? { Auth.auth().currentUser?.uid }

    // MARK: Load

    func loadAll() async {
        guard let uid else { return }
        isLoading = true
        defer { isLoading = false }
        async let r: () = loadRhythm(uid: uid)
        async let s: () = loadStreaks(uid: uid)
        _ = await (r, s)
    }

    func loadRhythm(uid: String) async {
        do {
            let doc = try await db.collection("users").document(uid)
                .collection("spiritualRhythm").document("main")
                .getDocument()
            if let data = doc.data() {
                rhythm = try Firestore.Decoder().decode(AmenSpiritualRhythm.self, from: data)
            }
        } catch {
            dlog("⚠️ SpiritualRhythmService: loadRhythm error: \(error)")
        }
    }

    func loadStreaks(uid: String) async {
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("streaks")
                .getDocuments()
            for doc in snapshot.documents {
                if let streak = try? doc.data(as: AmenStreak.self),
                   let type = AmenStreakType(rawValue: doc.documentID) {
                    streaks[type] = streak
                }
            }
        } catch {
            dlog("⚠️ SpiritualRhythmService: loadStreaks error: \(error)")
        }
    }

    // MARK: Record Activity

    func recordActivity(_ type: AmenStreakType) async {
        guard let uid else { return }
        do {
            let callable = Functions.functions().httpsCallable("recordSpiritualActivity")
            _ = try await callable.call(["activityType": type.rawValue, "userId": uid])
            await loadStreaks(uid: uid)
            await updateMomentumLabel()
        } catch {
            dlog("⚠️ SpiritualRhythmService: recordActivity error: \(error)")
        }
    }

    // MARK: Sabbath Mode

    func setSabbathMode(enabled: Bool) async {
        guard let uid else { return }
        rhythm.sabbathModeEnabled = enabled
        do {
            try await db.collection("users").document(uid)
                .collection("spiritualRhythm").document("main")
                .setData(["sabbathModeEnabled": enabled, "updatedAt": FieldValue.serverTimestamp()], merge: true)
        } catch {
            dlog("⚠️ SpiritualRhythmService: setSabbathMode error: \(error)")
        }
    }

    // MARK: Streak Recovery

    func recoverStreak(type: AmenStreakType) async {
        guard let uid else { return }
        do {
            let callable = Functions.functions().httpsCallable("calculateStreakState")
            _ = try await callable.call(["streakType": type.rawValue, "action": "recover", "userId": uid])
            await loadStreaks(uid: uid)
        } catch {
            dlog("⚠️ SpiritualRhythmService: recoverStreak error: \(error)")
        }
    }

    // MARK: Momentum

    func updateMomentumLabel() async {
        guard let uid else { return }
        let label = computeMomentumLabel()
        rhythm.momentumLabel = label
        do {
            try await db.collection("users").document(uid)
                .collection("spiritualRhythm").document("main")
                .setData(["momentumLabel": label.rawValue], merge: true)
        } catch {
            dlog("⚠️ SpiritualRhythmService: updateMomentumLabel error: \(error)")
        }
    }

    private func computeMomentumLabel() -> AmenMomentumLabel {
        let activeStreaks = streaks.values.filter { $0.state.isAlive && $0.currentCount > 0 }
        if rhythm.isInactiveSeven { return .resting }
        if activeStreaks.isEmpty { return .returning }
        let avgCount = activeStreaks.map(\.currentCount).reduce(0, +) / max(activeStreaks.count, 1)
        if avgCount >= 14 { return .grounded }
        if avgCount >= 7 { return .growing }
        return .reflecting
    }

    // MARK: Inactivity Check

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
                    .setData(["inactiveNoticeSent": true, "notificationsPausedDueToInactivity": true], merge: true)
            } catch {
                dlog("⚠️ SpiritualRhythmService: checkInactivityPolicy error: \(error)")
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
            rhythm.lastActivityDate = Date()
            await loadRhythm(uid: uid)
        } catch {
            dlog("⚠️ SpiritualRhythmService: restoreAfterReturn error: \(error)")
        }
    }

    // MARK: Streak for Display

    func streak(for type: AmenStreakType) -> AmenStreak {
        streaks[type] ?? AmenStreak(type: type)
    }
}

private func dlog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}
