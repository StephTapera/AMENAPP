import Foundation
import AVFoundation
import FirebaseDatabase
import UIKit

@MainActor
class GroupWatchCoordinator: ObservableObject {
    @Published var participants: [String] = []
    @Published var isConnected = false

    var player: AVPlayer?

    private var sessionId: String?
    private var rtdb: DatabaseReference?
    private var syncTask: Task<Void, Never>?
    private var observeHandle: UInt = 0

    func join(sessionId: String, player: AVPlayer) {
        self.sessionId = sessionId
        self.player = player
        let ref = Database.database().reference()
        self.rtdb = ref

        let sessionRef = ref.child("groupWatch").child(sessionId)

        // Set presence
        let presenceRef = sessionRef.child("participants").child(currentUserId())
        presenceRef.setValue(true)
        presenceRef.onDisconnectRemoveValue()

        // Observe current time from host
        observeHandle = sessionRef.child("currentTime").observe(.value) { [weak self] snapshot in
            guard let self, let serverTime = snapshot.value as? Double else { return }
            Task { @MainActor in
                guard let player = self.player else { return }
                let localTime = player.currentTime().seconds
                if abs(localTime - serverTime) > 1.0 {
                    player.seek(to: CMTime(seconds: serverTime, preferredTimescale: 600))
                }
            }
        }

        // Observe participants
        sessionRef.child("participants").observe(.value) { [weak self] snapshot in
            let kids = (snapshot.value as? [String: Any])?.keys.map { $0 } ?? []
            Task { @MainActor in self?.participants = kids }
        }

        isConnected = true
        startSync(sessionRef: sessionRef)
    }

    func leave() {
        syncTask?.cancel()
        guard let sessionId, let rtdb else { return }
        rtdb.child("groupWatch").child(sessionId).child("participants").child(currentUserId()).removeValue()
        rtdb.child("groupWatch").child(sessionId).child("currentTime").removeAllObservers()
        isConnected = false
    }

    private func startSync(sessionRef: DatabaseReference) {
        syncTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let player else { continue }
                let time = player.currentTime().seconds
                let timeRef = sessionRef.child("currentTime")
                try? await timeRef.setValue(time)
            }
        }
    }

    private func currentUserId() -> String {
        // Returns Firebase Auth UID; fallback to device ID
        return "anonymous_\(UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)"
    }
}
