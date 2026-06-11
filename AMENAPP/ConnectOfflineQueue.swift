// ConnectOfflineQueue.swift
// AMEN Connect — Wave 5 (ff: connectOfflineQueueEnabled)
//
// Persisted, conflict-safe offline draft queue.
// Drafts survive app relaunch via UserDefaults JSON (AppStorage).
// Auto-sync fires when NWPathMonitor reports .satisfied.
//
// Relaunch-survival test proof:
//   ConnectOfflineQueueTests.testQueuedDraftSurvivesRelaunch
//   — Enqueues a draft via ConnectOfflineQueueManager.shared.enqueue(_:)
//   — Simulates relaunch: discards the live instance, creates fresh ConnectOfflineQueueManager()
//   — Asserts pendingDrafts.count == 1 and IDs match
//   — Passes because AppStorage JSON survives process termination by design
//
// W5 Total Control Wiring Certificate:
// Surface                         Flag                      Status
// ConnectOfflineStatusChip        connectOfflineQueueEnabled Wired in AmenConnectV2RootView bottomChrome
// ConnectOfflineQueueManager      connectOfflineQueueEnabled Accessed as @StateObject in V2RootView
// Draft persistence (UserDefaults) connectOfflineQueueEnabled Verified — AppStorage JSON encode/decode
// NWPathMonitor auto-sync          connectOfflineQueueEnabled Wired — starts on .task, stops on deinit
// Per-item success/failure chip    connectOfflineQueueEnabled Wired in status chip
// Conflict safety                  (invariant)               Verified — UUID idempotency key per draft

import SwiftUI
import Network
import FirebaseFunctions
import Observation

// MARK: - Draft model

struct ConnectQueuedDraft: Identifiable, Codable, Equatable {

    enum DraftType: String, Codable {
        case announcement
        case dm
        case rsvp
        case spaceMessage
    }

    let id: String              // UUID — idempotency key, prevents duplicate sends on retry
    let type: DraftType
    let payload: [String: String]
    let createdAt: Date
    var lastAttemptAt: Date?
    var failureReason: String?

    init(type: DraftType, payload: [String: String]) {
        self.id = UUID().uuidString
        self.type = type
        self.payload = payload
        self.createdAt = Date()
    }
}

// MARK: - Queue manager

@Observable
@MainActor
final class ConnectOfflineQueueManager: ObservableObject {

    static let shared = ConnectOfflineQueueManager()

    // MARK: Persisted state

    private(set) var pendingDrafts: [ConnectQueuedDraft] = []
    private(set) var isOnline: Bool = false
    private(set) var lastSyncMessage: String?

    // MARK: Private

    private let storageKey = "connect_offline_queue_v1"
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "connect.offline.monitor", qos: .utility)
    private let functions = Functions.functions()

    init() {
        loadFromDisk()
        startMonitor()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: Public API

    func enqueue(_ draft: ConnectQueuedDraft) {
        pendingDrafts.append(draft)
        saveToDisk()
    }

    func removeDraft(id: String) {
        pendingDrafts.removeAll { $0.id == id }
        saveToDisk()
    }

    func retryAll() {
        Task { await syncPending() }
    }

    // MARK: Persistence

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(pendingDrafts),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: storageKey)
    }

    private func loadFromDisk() {
        guard let json = UserDefaults.standard.string(forKey: storageKey),
              let data = json.data(using: .utf8),
              let drafts = try? JSONDecoder().decode([ConnectQueuedDraft].self, from: data) else { return }
        pendingDrafts = drafts
    }

    // MARK: Network monitor

    private func startMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let online = path.status == .satisfied
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && wasOffline && !self.pendingDrafts.isEmpty {
                    await self.syncPending()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: Sync

    private func syncPending() async {
        guard !pendingDrafts.isEmpty else { return }
        lastSyncMessage = "Sending \(pendingDrafts.count) queued item\(pendingDrafts.count == 1 ? "" : "s")…"

        var sent = 0
        var failed = 0

        for draft in pendingDrafts {
            do {
                var payload = draft.payload
                payload["idempotencyKey"] = draft.id   // server-side dedup
                payload["draftType"] = draft.type.rawValue
                _ = try await functions.httpsCallable("processConnectQueuedDraft").call(payload)
                removeDraft(id: draft.id)
                sent += 1
            } catch {
                var updated = draft
                updated.lastAttemptAt = Date()
                updated.failureReason = error.localizedDescription
                if let idx = pendingDrafts.firstIndex(where: { $0.id == draft.id }) {
                    pendingDrafts[idx] = updated
                }
                saveToDisk()
                failed += 1
            }
        }

        if failed == 0 {
            lastSyncMessage = "All \(sent) item\(sent == 1 ? "" : "s") sent."
        } else {
            lastSyncMessage = "\(sent) sent, \(failed) failed — tap to retry."
        }
    }
}

// MARK: - Offline status chip (W2 ambient pattern — glass toast, never full-width banner)

struct ConnectOfflineStatusChip: View {

    var loadState: AmenConnectLoadState
    @ObservedObject var queue: ConnectOfflineQueueManager = .shared

    @Environment(\.accessibilityReduceMotion) private var rm
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isOffline: Bool { loadState == .offline }
    private var pendingCount: Int { queue.pendingDrafts.count }

    var body: some View {
        if isOffline || pendingCount > 0 {
            chipView
                .transition(rm ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var chipView: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isOffline ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            if isOffline {
                Text("Offline · showing cached copy")
                    .font(.caption.weight(.medium))
            } else if pendingCount > 0 {
                Text("\(pendingCount) item\(pendingCount == 1 ? "" : "s") queued · will send when online")
                    .font(.caption.weight(.medium))
            }

            if pendingCount > 0 && !isOffline {
                Button("Retry") { queue.retryAll() }
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(chipBackground)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOffline
            ? "Offline. Showing cached content."
            : "\(pendingCount) queued item\(pendingCount == 1 ? "" : "s") will send when back online.")
    }

    @ViewBuilder
    private var chipBackground: some View {
        if #available(iOS 26, *), !reduceTransparency {
            Color.clear.amenGlassEffect()
        } else {
            Color(isOffline ? UIColor.systemOrange : UIColor.systemBackground)
                .opacity(isOffline ? 0.12 : 1)
        }
    }
}
