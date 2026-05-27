import Foundation
import AVFoundation
import FirebaseDatabase
import FirebaseAuth

// MARK: - GroupWatchCoordinator
// Synchronises playback position across participants via Firebase RTDB.
// - Publishes currentTime every 500ms when hosting/watching.
// - Seeks local player if remote drift exceeds 1 second.
// - Manages participant presence via onDisconnect.

@MainActor
final class GroupWatchCoordinator: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var participants: [String] = []

    var player: AVPlayer?

    private var sessionId: String?
    private var syncTimer: Timer?
    private var rtdb: DatabaseReference { Database.database().reference() }
    private var timeObserverHandle: DatabaseHandle?
    private var participantsHandle: DatabaseHandle?
    private var participantRef: DatabaseReference?

    // MARK: - Public API

    func join(sessionId: String, player: AVPlayer) {
        self.sessionId = sessionId
        self.player = player

        setupPresence(sessionId: sessionId)
        seekToCurrentRemoteTime(sessionId: sessionId)
        startObserving(sessionId: sessionId)
        startSync(sessionId: sessionId)
    }

    func leave() {
        syncTimer?.invalidate()
        syncTimer = nil

        if let id = sessionId {
            if let handle = timeObserverHandle {
                rtdb.child("groupWatch/\(id)/currentTime").removeObserver(withHandle: handle)
            }
            if let handle = participantsHandle {
                rtdb.child("groupWatch/\(id)/participants").removeObserver(withHandle: handle)
            }
        }

        // onDisconnect already handles RTDB cleanup; cancel it if leaving intentionally.
        participantRef?.cancelDisconnectOperations()
        participantRef?.removeValue()
        participantRef = nil
        sessionId = nil
        player = nil
    }

    // MARK: - Presence

    private func setupPresence(sessionId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = rtdb.child("groupWatch/\(sessionId)/participants/\(uid)")
        participantRef = ref
        ref.setValue(true)
        ref.onDisconnectRemoveValue()
    }

    private func seekToCurrentRemoteTime(sessionId: String) {
        rtdb.child("groupWatch/\(sessionId)/currentTime").observeSingleEvent(of: .value) { [weak self] snapshot in
            guard let self, let value = snapshot.value as? TimeInterval else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.seekPlayer(to: value)
            }
        }
    }

    // MARK: - Sync (publish)

    private func startSync(sessionId: String) {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      let player = self.player else { return }
                let time = player.currentTime().seconds
                guard time.isFinite else { return }
                self.currentTime = time
                self.rtdb.child("groupWatch/\(sessionId)/currentTime").setValue(time)
            }
        }
    }

    // MARK: - Observe (consume)

    private func startObserving(sessionId: String) {
        // Observe remote time for drift correction
        timeObserverHandle = rtdb.child("groupWatch/\(sessionId)/currentTime")
            .observe(.value) { [weak self] snapshot in
                guard let self,
                      let remoteTime = snapshot.value as? TimeInterval else { return }
                Task { @MainActor [weak self] in
                    guard let self,
                          let player = self.player else { return }
                    let localTime = player.currentTime().seconds
                    let drift = abs(localTime - remoteTime)
                    if drift > 1.0 {
                        self.seekPlayer(to: remoteTime)
                    }
                }
            }

        // Observe participants list
        participantsHandle = rtdb.child("groupWatch/\(sessionId)/participants")
            .observe(.value) { [weak self] snapshot in
                guard let self else { return }
                let uids = (snapshot.value as? [String: Any])?.keys.map { $0 } ?? []
                Task { @MainActor [weak self] in
                    self?.participants = uids
                }
            }
    }

    // MARK: - Helpers

    private func seekPlayer(to time: TimeInterval) {
        guard time.isFinite, let player else { return }
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
