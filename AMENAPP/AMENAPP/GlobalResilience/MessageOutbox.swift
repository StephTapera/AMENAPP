// MessageOutbox.swift
// AMEN — Offline Message Outbox
// SwiftData-backed persistent queue with NWPathMonitor flush and exponential backoff.
// OutboxStatus is defined in GlobalResilienceContracts.swift — do not redefine here.

import SwiftData
import SwiftUI
import Network
import FirebaseFunctions

// MARK: - OutboxMessage Model

@Model
final class OutboxMessage {
    @Attribute(.unique) var id: String
    var idempotencyKey: String
    var threadId: String
    var recipientId: String
    var bodyText: String?
    var mediaLocalPath: String?
    /// Backing store for OutboxStatus enum.
    var statusRaw: String
    var createdAt: Date
    var lastAttemptAt: Date?
    var attemptCount: Int
    var errorMessage: String?

    init(
        id: String = UUID().uuidString,
        idempotencyKey: String = UUID().uuidString,
        threadId: String,
        recipientId: String,
        bodyText: String? = nil,
        mediaLocalPath: String? = nil,
        statusRaw: String = OutboxStatus.pending.rawValue,
        createdAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        attemptCount: Int = 0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.threadId = threadId
        self.recipientId = recipientId
        self.bodyText = bodyText
        self.mediaLocalPath = mediaLocalPath
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.attemptCount = attemptCount
        self.errorMessage = errorMessage
    }

    /// Convenience accessor for the typed status.
    var status: OutboxStatus {
        get { OutboxStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - MessageOutbox

@MainActor
final class MessageOutbox: ObservableObject {

    // MARK: Singleton

    static let shared: MessageOutbox = MessageOutbox()

    // MARK: Published State

    @Published private(set) var pendingMessages: [OutboxMessage] = []

    // MARK: Private

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let monitor: NWPathMonitor = NWPathMonitor()
    private let monitorQueue: DispatchQueue = DispatchQueue(label: "com.amen.outbox.networkMonitor")

    // Backoff constants
    private let backoffBase: Double = 2.0
    private let backoffMultiplier: Double = 2.0
    private let backoffMax: Double = 60.0
    private let maxAttempts: Int = 5

    // MARK: Init

    init() {
        do {
            let schema = Schema([OutboxMessage.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("MessageOutbox: failed to create ModelContainer — \(error)")
        }
        refreshPending()
    }

    // MARK: - Public API

    /// Inserts a new draft/pending message into the SwiftData store.
    func enqueue(_ draft: OutboxMessage) {
        context.insert(draft)
        save()
        refreshPending()
    }

    /// Marks a message as sent by id.
    func markSent(_ id: String) {
        guard let msg = findMessage(id: id) else { return }
        msg.status = .sent
        msg.errorMessage = nil
        save()
        refreshPending()
    }

    /// Marks a message as permanently failed with an error description.
    func markFailed(_ id: String, error: String) {
        guard let msg = findMessage(id: id) else { return }
        msg.status = .failed
        msg.errorMessage = error
        msg.lastAttemptAt = Date()
        save()
        refreshPending()
    }

    /// Resets a failed message back to pending so it will be retried on next flush.
    func retry(_ id: String) {
        guard let msg = findMessage(id: id) else { return }
        msg.status = .pending
        msg.errorMessage = nil
        msg.attemptCount = 0
        save()
        refreshPending()
        Task { await flushPending() }
    }

    // MARK: - Network Observation

    /// Starts the NWPathMonitor. Call once from AppDelegate / App init.
    func startNetworkObservation() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.status == .satisfied {
                Task { @MainActor in
                    await self.flushPending()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Flush

    private func flushPending() async {
        refreshPending()
        let toFlush = pendingMessages.filter {
            $0.status == .pending && $0.attemptCount < maxAttempts
        }
        for msg in toFlush {
            await attemptSend(msg)
        }
    }

    private func attemptSend(_ msg: OutboxMessage) async {
        let attempt = msg.attemptCount

        // Exponential backoff — skip delay on first attempt
        if attempt > 0 {
            let delay = min(backoffBase * pow(backoffMultiplier, Double(attempt - 1)), backoffMax)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        msg.lastAttemptAt = Date()
        msg.attemptCount += 1
        save()

        do {
            try await sendViaCallable(msg)
            markSent(msg.id)
        } catch {
            if msg.attemptCount >= maxAttempts {
                markFailed(msg.id, error: error.localizedDescription)
            } else {
                // Leave as pending; next flush or explicit retry will continue.
                msg.errorMessage = error.localizedDescription
                save()
                refreshPending()
            }
        }
    }

    // MARK: - Firebase Callable

    private func sendViaCallable(_ msg: OutboxMessage) async throws {
        let functions = Functions.functions()
        let callable = functions.httpsCallable("messaging-sendMessageGlobal")

        var payload: [String: Any] = [
            "threadId": msg.threadId,
            "recipientId": msg.recipientId,
            "idempotencyKey": msg.idempotencyKey
        ]
        if let body = msg.bodyText {
            payload["bodyText"] = body
        }
        // mediaLocalPath represents a previously-uploaded asset id when flushing
        if let assetId = msg.mediaLocalPath {
            payload["mediaAssetId"] = assetId
        }

        _ = try await callable.call(payload)
    }

    // MARK: - Helpers

    private func findMessage(id: String) -> OutboxMessage? {
        let descriptor = FetchDescriptor<OutboxMessage>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func refreshPending() {
        let descriptor = FetchDescriptor<OutboxMessage>(
            predicate: #Predicate { $0.statusRaw == "pending" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        pendingMessages = (try? context.fetch(descriptor)) ?? []
    }

    private func save() {
        do {
            try context.save()
        } catch {
            // Non-fatal: log and continue. The in-memory state remains consistent.
            print("[MessageOutbox] save error: \(error)")
        }
    }
}
