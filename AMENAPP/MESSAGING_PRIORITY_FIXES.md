# Messaging System - Priority Fix List
**Quick Action Guide**

---

## 🔥 FIX IMMEDIATELY (App Won't Run)

### 1. Add Missing LinkPreview Type
**File:** `Message.swift`  
**Add after MessageReaction struct:**

```swift
struct LinkPreview: Identifiable, Equatable, Hashable {
    let id: UUID
    let url: URL
    let title: String?
    let description: String?
    let imageUrl: String?
    let favicon: String?
    
    init(
        url: URL,
        title: String? = nil,
        description: String? = nil,
        imageUrl: String? = nil,
        favicon: String? = nil
    ) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.description = description
        self.imageUrl = imageUrl
        self.favicon = favicon
    }
    
    static func == (lhs: LinkPreview, rhs: LinkPreview) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

---

### 2. Add Notification Names
**File:** Create `NotificationNames.swift` or add to `MessagingCoordinator.swift`

```swift
extension Notification.Name {
    static let openConversation = Notification.Name("openConversation")
    static let openMessageRequests = Notification.Name("openMessageRequests")
    static let newMessageReceived = Notification.Name("newMessageReceived")
    static let conversationUpdated = Notification.Name("conversationUpdated")
}
```

---

### 3. Fix Memory Leaks in ModernConversationDetailView
**File:** `ModernConversationDetailView.swift` (Inside MessagesView.swift)

**Replace the loadSampleMessages function:**

```swift
// MARK: - Message Actions

@State private var messagesListener: (() -> Void)?
@State private var typingListener: (() -> Void)?

private func loadSampleMessages() {
    // Load real messages from Firebase
    let conversationId = conversation.id
    messagesListener = FirebaseMessagingService.shared.startListeningToMessages(
        conversationId: conversationId
    ) { newMessages in
        messages = newMessages
        
        // Mark unread messages as read
        let unreadMessageIds = newMessages.filter { !$0.isRead && !$0.isFromCurrentUser }.map { $0.id }
        if !unreadMessageIds.isEmpty {
            Task {
                try? await FirebaseMessagingService.shared.markMessagesAsRead(
                    conversationId: conversationId,
                    messageIds: unreadMessageIds
                )
            }
        }
    }
}

private func simulateTyping() {
    // Real typing indicators will come from Firebase
    let conversationId = conversation.id
    typingListener = FirebaseMessagingService.shared.startListeningToTyping(
        conversationId: conversationId,
        onUpdate: { typingUsers in
            isTyping = !typingUsers.isEmpty
        }
    )
}
```

**Update onDisappear:**

```swift
.onDisappear {
    // Clean up listeners
    messagesListener?()
    typingListener?()
    messagesListener = nil
    typingListener = nil
}
```

---

### 4. Fix Task.detached Anti-Pattern
**File:** `MessagesView.swift`

**Replace all instances of `Task.detached { @MainActor in` with `Task { @MainActor in`**

Examples:
```swift
// BEFORE (❌ Wrong):
private func muteConversation(_ conversation: ChatConversation) {
    Task.detached { @MainActor in
        // ...
    }
}

// AFTER (✅ Correct):
private func muteConversation(_ conversation: ChatConversation) {
    Task { @MainActor in
        // ...
    }
}
```

Apply this fix to:
- `muteConversation` (line ~948)
- `pinConversation` (line ~969)
- `deleteConversation` (line ~990)
- `archiveConversation` (line ~1020)

---

## 🚨 FIX THIS WEEK (Critical Functionality)

### 5. Add Comprehensive Error Handling
**File:** Create `MessagingError.swift`

```swift
import SwiftUI

enum MessagingError: Identifiable, LocalizedError {
    case sendFailed(String)
    case muteFailed
    case pinFailed
    case archiveFailed
    case deleteFailed
    case loadFailed
    case networkError
    case permissionDenied
    case userBlocked
    case invalidInput(String)
    
    var id: String {
        switch self {
        case .sendFailed(let reason): return "sendFailed_\(reason)"
        case .muteFailed: return "muteFailed"
        case .pinFailed: return "pinFailed"
        case .archiveFailed: return "archiveFailed"
        case .deleteFailed: return "deleteFailed"
        case .loadFailed: return "loadFailed"
        case .networkError: return "networkError"
        case .permissionDenied: return "permissionDenied"
        case .userBlocked: return "userBlocked"
        case .invalidInput(let reason): return "invalidInput_\(reason)"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .sendFailed(let reason):
            return "Failed to send message: \(reason)"
        case .muteFailed:
            return "Failed to mute conversation"
        case .pinFailed:
            return "Failed to pin conversation"
        case .archiveFailed:
            return "Failed to archive conversation"
        case .deleteFailed:
            return "Failed to delete conversation"
        case .loadFailed:
            return "Failed to load messages"
        case .networkError:
            return "No internet connection"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .userBlocked:
            return "You cannot message this user"
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        }
    }
    
    var canRetry: Bool {
        switch self {
        case .sendFailed, .networkError, .loadFailed:
            return true
        default:
            return false
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Please check your internet connection and try again"
        case .sendFailed:
            return "Tap to retry sending"
        case .permissionDenied:
            return "Contact support if you think this is a mistake"
        case .userBlocked:
            return "Unblock this user to send messages"
        default:
            return nil
        }
    }
}
```

**Then update MessagesView.swift:**

```swift
@State private var currentError: MessagingError?

// Add to body:
.alert(item: $currentError) { error in
    Alert(
        title: Text("Error"),
        message: Text("\(error.errorDescription ?? "Unknown error")\n\n\(error.recoverySuggestion ?? "")"),
        primaryButton: error.canRetry ? .default(Text("Retry")) {
            retryLastAction()
        } : .default(Text("OK")),
        secondaryButton: .cancel()
    )
}

// Update error handling in functions:
private func muteConversation(_ conversation: ChatConversation) {
    Task { @MainActor in
        do {
            try await FirebaseMessagingService.shared.muteConversation(
                conversationId: conversation.id,
                muted: true
            )
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            print("🔕 Muted conversation: \(conversation.name)")
        } catch {
            print("❌ Error muting conversation: \(error)")
            currentError = .muteFailed  // ✅ Show error to user
        }
    }
}
```

---

### 6. Add Input Validation
**File:** Create `MessageValidator.swift`

```swift
import Foundation

enum ValidationError: Error, LocalizedError {
    case empty
    case tooLong(Int)
    case profanity
    case spam
    case tooManyImages(Int)
    
    var errorDescription: String? {
        switch self {
        case .empty:
            return "Message cannot be empty"
        case .tooLong(let max):
            return "Message is too long (max \(max) characters)"
        case .profanity:
            return "Message contains inappropriate content"
        case .spam:
            return "You're sending messages too quickly"
        case .tooManyImages(let max):
            return "Too many images (max \(max))"
        }
    }
}

struct MessageValidator {
    static let maxLength = 10000
    static let maxImages = 10
    
    static func validate(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            throw ValidationError.empty
        }
        
        guard trimmed.count <= maxLength else {
            throw ValidationError.tooLong(maxLength)
        }
        
        // Add more validation as needed
    }
    
    static func validateImages(_ images: [UIImage]) throws {
        guard images.count <= maxImages else {
            throw ValidationError.tooManyImages(maxImages)
        }
    }
    
    static func validateUsername(_ username: String) throws {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            throw ValidationError.empty
        }
        
        guard trimmed.count <= 100 else {
            throw ValidationError.tooLong(100)
        }
    }
}
```

**Use in ModernConversationDetailView:**

```swift
private func sendMessage() {
    guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty else { return }
    
    // ✅ Validate before sending
    do {
        if !messageText.isEmpty {
            try MessageValidator.validate(messageText)
        }
        if !selectedImages.isEmpty {
            try MessageValidator.validateImages(selectedImages)
        }
    } catch {
        errorMessage = error.localizedDescription
        showErrorAlert = true
        return
    }
    
    // Continue with send...
}
```

---

### 7. Add Search Debouncing
**File:** `CreateGroupView.swift` in MessagesView.swift

```swift
@State private var searchTask: Task<Void, Never>?
@State private var searchDebounceTimer: Timer?

private func performSearch() {
    // Cancel previous search
    searchTask?.cancel()
    searchDebounceTimer?.invalidate()
    
    guard !searchText.isEmpty else {
        searchResults = []
        return
    }
    
    guard searchText.count >= 2 else {
        searchResults = []
        return
    }
    
    isSearching = true
    
    // Debounce search by 300ms
    searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
        searchTask = Task {
            do {
                // Search for users using the messaging service
                let users = try await messagingService.searchUsers(query: searchText)
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    searchResults = users.map { SearchableUser(from: $0) }
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                print("❌ Error searching users: \(error)")
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }
}

// Clean up on disappear
.onDisappear {
    searchTask?.cancel()
    searchDebounceTimer?.invalidate()
}
```

---

### 8. Fix Typing Indicator
**File:** `ModernConversationDetailView.swift`

```swift
@State private var typingDebounceTimer: Timer?

private func handleTypingIndicator(isTyping: Bool) {
    // Cancel previous timer
    typingDebounceTimer?.invalidate()
    
    if isTyping {
        // Send typing started
        Task {
            try? await FirebaseMessagingService.shared.updateTypingStatus(
                conversationId: conversation.id,
                isTyping: true
            )
        }
        
        // Auto-stop typing after 5 seconds
        typingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            Task {
                try? await FirebaseMessagingService.shared.updateTypingStatus(
                    conversationId: conversation.id,
                    isTyping: false
                )
            }
        }
    } else {
        // Send typing stopped
        Task {
            try? await FirebaseMessagingService.shared.updateTypingStatus(
                conversationId: conversation.id,
                isTyping: false
            )
        }
    }
}

// Clean up on disappear
.onDisappear {
    typingDebounceTimer?.invalidate()
    // Send typing stopped
    Task {
        try? await FirebaseMessagingService.shared.updateTypingStatus(
            conversationId: conversation.id,
            isTyping: false
        )
    }
}
```

---

## ⚠️ FIX NEXT WEEK (Important Features)

### 9. Add Image Compression
**File:** Create `ImageCompressor.swift`

```swift
import UIKit

struct ImageCompressor {
    static func compress(_ image: UIImage, maxSizeMB: Double = 1.0, maxDimension: CGFloat = 1920) -> Data? {
        // Resize if needed
        let resized = resize(image, maxDimension: maxDimension)
        
        // Compress to target size
        var compression: CGFloat = 1.0
        var imageData = resized.jpegData(compressionQuality: compression)
        
        let maxBytes = Int(maxSizeMB * 1024 * 1024)
        
        while let data = imageData, data.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            imageData = resized.jpegData(compressionQuality: compression)
        }
        
        return imageData
    }
    
    static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
    
    static func generateThumbnail(_ image: UIImage, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        return resize(image, maxDimension: max(size.width, size.height))
    }
}

// Use before upload:
if let compressedData = ImageCompressor.compress(image) {
    // Upload compressedData instead of full image
}
```

---

### 10. Add Offline Support
**File:** Create `OfflineMessageQueue.swift`

```swift
import Foundation

class OfflineMessageQueue {
    static let shared = OfflineMessageQueue()
    
    private let userDefaults = UserDefaults.standard
    private let queueKey = "offlineMessageQueue"
    
    struct QueuedMessage: Codable {
        let id: String
        let conversationId: String
        let text: String
        let timestamp: Date
    }
    
    func queueMessage(conversationId: String, text: String) -> String {
        let message = QueuedMessage(
            id: UUID().uuidString,
            conversationId: conversationId,
            text: text,
            timestamp: Date()
        )
        
        var queue = getQueue()
        queue.append(message)
        saveQueue(queue)
        
        return message.id
    }
    
    func processQueue() async {
        let queue = getQueue()
        
        for message in queue {
            do {
                try await FirebaseMessagingService.shared.sendMessage(
                    conversationId: message.conversationId,
                    text: message.text,
                    replyToMessageId: nil
                )
                removeFromQueue(message.id)
            } catch {
                print("Failed to send queued message: \(error)")
                // Keep in queue for retry
            }
        }
    }
    
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
    }
}

// Use in app lifecycle:
.onAppear {
    Task {
        await OfflineMessageQueue.shared.processQueue()
    }
}
```

---

### 11. Add Network Status Monitoring
**File:** Create `NetworkMonitor.swift`

```swift
import Network
import SwiftUI

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = true
    @Published var connectionType: NWInterface.InterfaceType?
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }
}

// Add to MessagesView:
@StateObject private var networkMonitor = NetworkMonitor.shared

// Show indicator:
if !networkMonitor.isConnected {
    HStack {
        Image(systemName: "wifi.slash")
        Text("No internet connection")
    }
    .font(.custom("OpenSans-SemiBold", size: 13))
    .foregroundStyle(.white)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.red)
    .transition(.move(edge: .top))
}
```

---

## 📝 TESTING CHECKLIST

After implementing these fixes, test:

- [ ] Send text message
- [ ] Send message with photos
- [ ] Reply to message
- [ ] React to message
- [ ] Delete message
- [ ] Mute conversation
- [ ] Pin conversation
- [ ] Archive conversation
- [ ] Unarchive conversation
- [ ] Delete conversation
- [ ] Create group
- [ ] Search users
- [ ] Accept message request
- [ ] Decline message request
- [ ] Block user
- [ ] Test offline (airplane mode)
- [ ] Test poor connection (network link conditioner)
- [ ] Test memory usage (Instruments)
- [ ] Test with VoiceOver
- [ ] Test with Dynamic Type
- [ ] Test rapid tapping (no crashes)

---

## 🎯 SUMMARY

**Critical Fixes (Do First):**
1. ✅ Add LinkPreview type
2. ✅ Add notification names  
3. ✅ Fix memory leaks
4. ✅ Fix Task.detached pattern

**This Week:**
5. ✅ Error handling infrastructure
6. ✅ Input validation
7. ✅ Search debouncing
8. ✅ Typing indicator fixes

**Next Week:**
9. ✅ Image compression
10. ✅ Offline support
11. ✅ Network monitoring

After these fixes, the app will be **significantly more stable and production-ready** (~75% complete).
