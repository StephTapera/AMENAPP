//
//  OfflineMessageQueue.swift
//  AMENAPP
//
//  Queue for messages sent while offline
//

import Foundation
import SwiftUI
import Combine

class OfflineMessageQueue: ObservableObject {
    static let shared = OfflineMessageQueue()
    
    private let userDefaults = UserDefaults.standard
    private let queueKey = "offlineMessageQueue"
    
    @Published var queuedCount: Int = 0
    
    struct QueuedMessage: Codable, Identifiable {
        let id: String
        let conversationId: String
        let text: String
        let timestamp: Date
        let replyToMessageId: String?
        var retryCount: Int = 0
        
        init(conversationId: String, text: String, replyToMessageId: String? = nil) {
            self.id = UUID().uuidString
            self.conversationId = conversationId
            self.text = text
            self.timestamp = Date()
            self.replyToMessageId = replyToMessageId
        }
    }
    
    private init() {
        updateCount()
    }
    
    // MARK: - Queue Management
    
    func queueMessage(conversationId: String, text: String, replyToMessageId: String? = nil) -> String {
        let message = QueuedMessage(
            conversationId: conversationId,
            text: text,
            replyToMessageId: replyToMessageId
        )
        
        var queue = getQueue()
        queue.append(message)
        saveQueue(queue)
        updateCount()
        
        print("📥 Queued message offline: \(message.id)")
        
        return message.id
    }
    
    func processQueue() async {
        let queue = getQueue()
        
        guard !queue.isEmpty else {
            print("✅ No queued messages to process")
            return
        }
        
        print("🔄 Processing \(queue.count) queued messages...")
        
        for message in queue {
            do {
                try await FirebaseMessagingService.shared.sendMessage(
                    conversationId: message.conversationId,
                    text: message.text,
                    replyToMessageId: message.replyToMessageId
                )
                
                removeFromQueue(message.id)
                print("✅ Sent queued message: \(message.id)")
                
            } catch {
                print("❌ Failed to send queued message \(message.id): \(error)")
                
                // Increment retry count
                var updatedQueue = getQueue()
                if let index = updatedQueue.firstIndex(where: { $0.id == message.id }) {
                    updatedQueue[index].retryCount += 1
                    
                    // Remove if too many retries (max 5)
                    if updatedQueue[index].retryCount >= 5 {
                        print("⚠️ Max retries reached for message: \(message.id)")
                        updatedQueue.remove(at: index)
                    }
                    
                    saveQueue(updatedQueue)
                }
            }
        }
        
        updateCount()
    }
    
    func clearQueue() {
        saveQueue([])
        updateCount()
        print("🗑️ Cleared offline message queue")
    }
    
    // MARK: - Private Helpers
    
    private func getQueue() -> [QueuedMessage] {
        guard let data = userDefaults.data(forKey: queueKey),
              let queue = try? JSONDecoder().decode([QueuedMessage].self, from: data) else {
            return []
        }
        return queue
    }
    
    private func saveQueue(_ queue: [QueuedMessage]) {
        if let data = try? JSONEncoder().encode(queue) {
            userDefaults.set(data, forKey: queueKey)
        }
    }
    
    private func removeFromQueue(_ id: String) {
        var queue = getQueue()
        queue.removeAll { $0.id == id }
        saveQueue(queue)
        updateCount()
    }
    
    private func updateCount() {
        DispatchQueue.main.async {
            self.queuedCount = self.getQueue().count
        }
    }
    
    // MARK: - Statistics
    
    var hasQueuedMessages: Bool {
        queuedCount > 0
    }
    
    var oldestQueuedMessageAge: TimeInterval? {
        let queue = getQueue()
        guard let oldest = queue.min(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }
        return Date().timeIntervalSince(oldest.timestamp)
    }
}

// MARK: - SwiftUI View

struct OfflineQueueIndicator: View {
    @ObservedObject var queue = OfflineMessageQueue.shared
    
    var body: some View {
        if queue.hasQueuedMessages {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                
                Text("Sending \(queue.queuedCount) message\(queue.queuedCount == 1 ? "" : "s")...")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
            )
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - App Lifecycle Integration

extension OfflineMessageQueue {
    /// Call this when app becomes active
    func handleAppBecameActive() {
        Task {
            await processQueue()
        }
    }
    
    /// Call this when network status changes to connected
    func handleNetworkConnected() {
        Task {
            await processQueue()
        }
    }
}
