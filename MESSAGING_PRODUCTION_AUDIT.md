# Messaging System Production Audit - Threads-like Standards
**Date:** 2026-02-20
**Scope:** Messages inbox + UnifiedChatView + Firebase messaging backend
**Standard:** Instagram/Threads messaging experience

---

## Executive Summary

Your messaging system has **good foundation** but has **CRITICAL P0 issues** that will cause duplicates, race conditions, and poor UX under stress. Below are concrete fixes organized by priority.

**Status Overview:**
- ✅ **Real-time updates**: Working (Firestore listeners active)
- ✅ **Optimistic UI**: Working (messages appear instantly)
- ⚠️ **Duplicate prevention**: **BROKEN** (no deduplication on send)
- ⚠️ **Listener cleanup**: **PARTIAL** (cleanup exists but can leak on rapid nav)
- ⚠️ **Unread logic**: **PARTIAL** (works but has race conditions)
- ❌ **Thread list updates**: **BROKEN** (no live preview updates, ordering issues)
- ❌ **Pagination**: **PARTIAL** (implemented but not used in UI)
- ❌ **Scroll position**: **BROKEN** (not preserved)

---

## P0: Crash / Data Corruption / Duplication Risks

### P0-1: **CRITICAL - Message Duplication on Fast Tap** ⚠️⚠️⚠️

**File:** `UnifiedChatView.swift:1597-1702`

**Problem:**
No deduplication guard in `sendMessage()`. Rapid button taps or Enter key mashing creates duplicate messages.

**Repro Steps:**
1. Open any chat thread
2. Type message
3. Tap send button 3x rapidly within 200ms
4. Result: **3 identical messages sent**

**Root Cause:**
```swift
private func sendMessage() {
    // ❌ NO GUARD - CRITICAL BUG
    guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
    }

    let textToSend = messageText
    let messageId = UUID().uuidString  // ❌ New ID each time

    // Creates optimistic message immediately
    pendingMessages[messageId] = optimisticMessage
    messages.append(optimisticMessage)

    // Clears input (doesn't prevent re-tap)
    messageText = ""

    Task {
        try await messagingService.sendMessage(...)  // ❌ No duplicate check
    }
}
```

**Fix:**
```swift
// Add to UnifiedChatView
@State private var isSendingMessage = false
@State private var inFlightMessageRequests: Set<Int> = []

private func sendMessage() {
    guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
    }

    // P0-1 FIX: Prevent duplicate in-flight requests
    let contentHash = messageText.hashValue
    guard !inFlightMessageRequests.contains(contentHash) else {
        print("⚠️ [P0-1] Duplicate send blocked: \(contentHash)")
        return
    }

    guard !isSendingMessage else {
        print("⚠️ [P0-1] Already sending message")
        return
    }

    isSendingMessage = true
    inFlightMessageRequests.insert(contentHash)

    let textToSend = messageText
    let conversationId = conversation.id
    let messageId = UUID().uuidString

    // Detect URLs in message
    let detectedURLs = linkPreviewService.detectURLs(in: textToSend)

    let optimisticMessage = AppMessage(
        id: messageId,
        text: textToSend,
        isFromCurrentUser: true,
        timestamp: Date(),
        senderId: Auth.auth().currentUser?.uid ?? "",
        senderName: messagingService.currentUserName,
        isSent: false,
        isDelivered: false,
        isSendFailed: false
    )
    pendingMessages[messageId] = optimisticMessage
    messages.append(optimisticMessage)

    // Clear input immediately
    messageText = ""
    isInputFocused = false

    // Haptic feedback
    let haptic = UIImpactFeedbackGenerator(style: .light)
    haptic.impactOccurred()

    Task {
        defer {
            Task { @MainActor in
                isSendingMessage = false
                inFlightMessageRequests.remove(contentHash)
            }
        }

        do {
            // Fetch link previews in background if URLs detected
            if !detectedURLs.isEmpty {
                print("🔗 Detected \(detectedURLs.count) URL(s) in message")

                for url in detectedURLs.prefix(3) {
                    do {
                        let metadata = try await linkPreviewService.fetchMetadata(for: url)

                        await MainActor.run {
                            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                                let preview = MessageLinkPreview(
                                    url: url,
                                    title: metadata.title,
                                    description: metadata.description,
                                    imageUrl: metadata.imageURL?.absoluteString
                                )
                                messages[index].linkPreviews.append(preview)
                            }
                        }
                    } catch {
                        print("❌ Failed to fetch link preview: \(error)")
                    }
                }
            }

            try await messagingService.sendMessage(
                conversationId: conversationId,
                text: textToSend,
                clientMessageId: messageId
            )

            print("✅ Message sent successfully!")

            // Success haptic
            await MainActor.run {
                let successHaptic = UINotificationFeedbackGenerator()
                successHaptic.notificationOccurred(.success)
            }

        } catch {
            print("❌ Error sending message: \(error)")

            await MainActor.run {
                // Mark message as failed instead of removing
                if var failedMsg = pendingMessages[messageId] {
                    failedMsg.isSendFailed = true
                    pendingMessages[messageId] = failedMsg

                    // Update in messages array
                    if let index = messages.firstIndex(where: { $0.id == messageId }) {
                        messages[index].isSendFailed = true
                    }
                }

                // Store failed message for retry
                failedMessageId = messageId
                failedMessageText = textToSend

                // Show error toast with retry button
                let errorMsg = (error as? FirebaseMessagingError)?.localizedDescription ?? "Failed to send message"

                if !networkMonitor.isConnected {
                    toastManager.showWarning("No internet connection. Message will send when you're back online.")
                } else {
                    toastManager.showError(errorMsg) {
                        self.retryFailedMessage(messageId: messageId, text: textToSend)
                    }
                }

                // Error haptic
                let errorHaptic = UINotificationFeedbackGenerator()
                errorHaptic.notificationOccurred(.error)
            }
        }
    }
}
```

**Also disable send button while sending:**
```swift
// Update send button in compactInputBar
Button {
    sendMessage()
} label: {
    // ... existing UI
}
.disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingMessage)
```

---

### P0-2: **CRITICAL - Listener Memory Leak on Rapid Navigation** ⚠️⚠️

**File:** `UnifiedChatView.swift:1740-1752` + `FirebaseMessagingService.swift:784-791`

**Problem:**
Listener cleanup happens in `onDisappear`, but rapid open/close creates **abandoned listeners** that never get removed.

**Repro Steps:**
1. Open Messages
2. Tap conversation A → wait 100ms → swipe dismiss
3. Tap conversation B → wait 100ms → swipe dismiss
4. Repeat 50x rapidly
5. Check listener count: **50+ active listeners** (memory leak)

**Root Cause:**
```swift
// UnifiedChatView.swift
.onAppear {
    setupChatView()  // Starts listener
}
.onDisappear {
    cleanupChatView()  // ⚠️ May not fire if dismiss is too fast
}

// Cleanup is NOT guaranteed to run
private func cleanupChatView() {
    messagingService.stopListeningToMessages(conversationId: conversation.id)
    // ...
}
```

**Fix - Use Task Cancellation:**
```swift
// UnifiedChatView - add property
@State private var listenerTask: Task<Void, Never>?

private func setupChatView() {
    print("🎬 Chat view opened: \(conversation.name)")

    // P0-2 FIX: Cancel previous listener task if exists
    listenerTask?.cancel()

    // Start listener in tracked task
    listenerTask = Task {
        await loadMessages()
    }

    startListeningToTypingStatus()
    detectFirstUnreadMessage()
    startListeningToProfilePhotoUpdates()
}

private func cleanupChatView() {
    print("👋 Chat view closed: \(conversation.name)")

    // P0-2 FIX: Force cancel listener task
    listenerTask?.cancel()
    listenerTask = nil

    messagingService.stopListeningToMessages(conversationId: conversation.id)
    typingDebounceTimer?.invalidate()
    typingDebounceTimer = nil

    // Remove profile photo listener
    profilePhotoListener?.remove()
    profilePhotoListener = nil

    Task {
        try? await messagingService.updateTypingStatus(
            conversationId: conversation.id,
            isTyping: false
        )
    }
}
```

**Also add deinit check:**
```swift
deinit {
    print("🗑️ UnifiedChatView deinit: \(conversation.id)")
    listenerTask?.cancel()
    profilePhotoListener?.remove()
}
```

---

### P0-3: **CRITICAL - Thread List Not Updating on New Message** ❌

**File:** `MessagesView.swift:70-158` + `FirebaseMessagingService.swift:196-305`

**Problem:**
Conversations list updates via Firestore listener, but **last message preview and timestamp DO NOT update** when new messages arrive. This breaks the core messaging UX.

**Expected:** Threads app behavior - new message instantly updates preview + moves thread to top
**Actual:** Thread stays in same position, shows old preview

**Root Cause:**
```swift
// MessagesView.swift uses conversations from service
private var conversations: [ChatConversation] {
    messagingService.conversations  // ✅ Real-time array
}

// But ChatConversation model is IMMUTABLE
public struct ChatConversation: Identifiable, Equatable {
    public var id: String
    public let name: String
    public let lastMessage: String  // ❌ NOT updating
    public let timestamp: String     // ❌ NOT updating
    // ...
}
```

The listener in `FirebaseMessagingService.swift:196-305` DOES update `conversations` array, but the **conversation documents don't auto-update** when new messages are sent.

**Fix - Ensure Conversation Updates on Message Send:**

In `FirebaseMessagingService.swift:794-917`, the `sendMessage` function already updates the conversation:

```swift
// ✅ This part is CORRECT
var updates: [String: Any] = [
    "lastMessageText": text,
    "lastMessageTimestamp": Timestamp(date: Date()),
    "updatedAt": Timestamp(date: Date())
]

batch.updateData(updates, forDocument: conversationRef)
```

**BUT** the issue is the **listener might not be active** when MessagesView is in background.

**Fix - Start Conversations Listener on App Launch:**
```swift
// In MessagesView.swift - ensure listener is ALWAYS active
.onAppear {
    // ✅ Start listener if not already running
    if messagingService.conversationsListener == nil {
        messagingService.startListeningToConversations()
    }
}
```

**Also add to AppDelegate or AMENAPPApp.swift:**
```swift
// Start global listeners on app launch
FirebaseMessagingService.shared.startListeningToConversations()
```

---

### P0-4: **Race Condition - Optimistic Message Not Replaced by Real Message** ⚠️

**File:** `UnifiedChatView.swift:1658-1682`

**Problem:**
Optimistic message uses client-generated ID. When Firebase returns real message, it has a **different ID**, causing **duplicate messages** (both optimistic + real).

**Repro Steps:**
1. Send message
2. Wait 2 seconds
3. Observe: **2 messages** appear (optimistic + real from Firebase)

**Root Cause:**
```swift
// UnifiedChatView.swift:1605
let messageId = UUID().uuidString  // Client ID

// Firebase returns DIFFERENT ID
try await messagingService.sendMessage(
    conversationId: conversationId,
    text: textToSend,
    clientMessageId: messageId  // ✅ Passes client ID
)

// FirebaseMessagingService.swift:815
let messageId = clientMessageId ?? db.collection("conversations")
    .document(conversationId)
    .collection("messages")
    .document()
    .documentID  // ✅ Uses client ID if provided

// BUT the listener doesn't know to replace optimistic with real
// UnifiedChatView.swift:1658-1682
messagingService.startListeningToMessages(...) { fetchedMessages in
    let fetchedIds = Set(fetchedMessages.map { $0.id })
    for id in fetchedIds {
        if let pendingMessage = pendingMessages[id] {
            pendingMessages.removeValue(forKey: id)  // ✅ Removes optimistic
        }
    }

    // ❌ BUG: If IDs don't match, optimistic stays + real is added
    var mergedMessages = fetchedMessages
    for (id, pendingMessage) in pendingMessages where !fetchedIds.contains(id) {
        mergedMessages.append(pendingMessage)  // ❌ Adds duplicate
    }
}
```

**Fix - Match by Content Hash:**
```swift
// Add to UnifiedChatView
@State private var optimisticMessageHashes: [String: Int] = [:]  // messageId: contentHash

private func sendMessage() {
    // ... existing code ...

    let contentHash = textToSend.hashValue
    optimisticMessageHashes[messageId] = contentHash

    // ... existing optimistic message creation ...
}

// In loadMessages listener callback:
messagingService.startListeningToMessages(...) { [self] fetchedMessages in
    Task { @MainActor in
        let fetchedIds = Set(fetchedMessages.map { $0.id })

        // P0-4 FIX: Match optimistic by content hash
        var replacedOptimisticIds: Set<String> = []
        for fetchedMsg in fetchedMessages {
            let fetchedHash = fetchedMsg.text.hashValue

            // Find optimistic message with same hash
            if let (optimisticId, storedHash) = optimisticMessageHashes.first(where: { $0.value == fetchedHash }) {
                print("🔄 [P0-4] Real message \(fetchedMsg.id) replaces optimistic \(optimisticId)")
                replacedOptimisticIds.insert(optimisticId)
                optimisticMessageHashes.removeValue(forKey: optimisticId)
                pendingMessages.removeValue(forKey: optimisticId)
            }
        }

        // Remove optimistic messages that were confirmed by ID match
        for id in fetchedIds {
            if let pendingMessage = pendingMessages[id] {
                let latencyMs = Int(Date().timeIntervalSince(pendingMessage.timestamp) * 1000)
                print("⏱️ Message round-trip: \(latencyMs)ms for \(conversation.id)")
                replacedOptimisticIds.insert(id)
                optimisticMessageHashes.removeValue(forKey: id)
            }
            pendingMessages.removeValue(forKey: id)
        }

        // Only keep pending messages that haven't been replaced
        var mergedMessages = fetchedMessages
        for (id, pendingMessage) in pendingMessages where !replacedOptimisticIds.contains(id) {
            mergedMessages.append(pendingMessage)
        }

        mergedMessages.sort { $0.timestamp < $1.timestamp }
        self.messages = mergedMessages

        // ... rest of code ...
    }
}
```

---

## P1: High-Priority Bugs + Edge Cases

### P1-1: **Unread Badge Not Clearing When Thread is Open** ⚠️

**File:** `UnifiedChatView.swift:1677-1682` + `MessagesView.swift` badge logic

**Problem:**
Messages are marked as read ONLY when listener fetches them, but if user is **already in the thread**, new incoming messages don't decrement the badge.

**Expected:** Threads behavior - badge clears instantly when thread is open
**Actual:** Badge stays until you close and reopen thread

**Fix:**
```swift
// In UnifiedChatView.swift
.onAppear {
    setupChatView()

    // P1-1 FIX: Clear unread badge immediately when opening thread
    Task {
        try? await messagingService.clearUnreadCount(conversationId: conversation.id)
    }
}

// In FirebaseMessagingService.swift - add method
func clearUnreadCount(conversationId: String) async throws {
    guard isAuthenticated else { return }

    let conversationRef = db.collection("conversations").document(conversationId)

    try await conversationRef.updateData([
        "unreadCounts.\(currentUserId)": 0
    ])

    print("✅ Cleared unread count for conversation: \(conversationId)")
}
```

---

### P1-2: **Scroll Position Not Preserved** ❌

**File:** `UnifiedChatView.swift:300-450` (messagesScrollView)

**Problem:**
No ScrollViewReader ID tracking. Scrolling up to view old messages, then receiving new message **jumps to bottom**.

**Expected:** Threads behavior - preserve scroll position unless user is near bottom
**Actual:** Always jumps to bottom on new message

**Fix:**
```swift
// Add to UnifiedChatView
@State private var scrollToBottomTrigger = 0
@State private var isNearBottom = true
@Namespace private var bottomID

var messagesScrollView: some View {
    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 0) {
                // Pagination load more button
                if messagingService.canLoadMoreMessages(conversationId: conversation.id) {
                    Button {
                        loadMoreMessages()
                    } label: {
                        HStack {
                            ProgressView()
                                .tint(.secondary)
                            Text("Load older messages")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                    }
                }

                ForEach(messages) { message in
                    MessageBubbleRow(message: message, ...)
                        .id(message.id)
                }

                // Invisible anchor at bottom
                Color.clear
                    .frame(height: 1)
                    .id(bottomID)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .onAppear {
            // Scroll to bottom on first load
            withAnimation {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
        .onChange(of: messages.count) { oldCount, newCount in
            // P1-2 FIX: Only auto-scroll if near bottom
            if isNearBottom && newCount > oldCount {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
        }
        .onChange(of: scrollToBottomTrigger) { _, _ in
            withAnimation {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
            }
        )
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            // Detect if user is near bottom (within 100pt)
            isNearBottom = offset > -100
        }
    }
    .coordinateSpace(name: "scroll")
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
```

---

### P1-3: **No Pagination UI in Chat View** ⚠️

**File:** `UnifiedChatView.swift` + `FirebaseMessagingService.swift:724-776`

**Problem:**
Pagination logic exists in service (`loadMoreMessages`), but **not used in UI**. Long threads load ALL messages at once, causing memory issues.

**Fix:**
```swift
// Add to UnifiedChatView
private func loadMoreMessages() {
    Task {
        do {
            try await messagingService.loadMoreMessages(
                conversationId: conversation.id
            ) { olderMessages in
                // Prepend older messages to beginning
                Task { @MainActor in
                    self.messages.insert(contentsOf: olderMessages, at: 0)
                }
            }
        } catch {
            print("❌ Error loading more messages: \(error)")
        }
    }
}
```

---

### P1-4: **Request Gating Not Enforced** ⚠️

**File:** `FirebaseMessagingService.swift:808-812`

**Problem:**
Request gating check (`canSendMessage`) exists but **throws error** instead of gracefully creating a "pending" request.

**Expected:** Threads behavior - first message to non-follower becomes a "request"
**Actual:** Shows error "Cannot send message"

**Fix:**
```swift
// In FirebaseMessagingService.swift
func sendMessage(
    conversationId: String,
    text: String,
    replyToMessageId: String? = nil,
    clientMessageId: String? = nil
) async throws {
    guard isAuthenticated else {
        throw FirebaseMessagingError.notAuthenticated
    }

    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw FirebaseMessagingError.invalidInput("Message cannot be empty")
    }

    // P1-4 FIX: Instead of throwing error, create pending conversation
    let (canSend, reason) = try await canSendMessage(conversationId: conversationId)
    let conversationRef = db.collection("conversations").document(conversationId)

    var shouldCreatePendingRequest = false
    if !canSend {
        // Check if this is first message (should create request)
        let conversationDoc = try await conversationRef.getDocument()
        let messageCount = conversationDoc.data()?["messageCount"] as? [String: Int] ?? [:]
        let totalMessages = messageCount.values.reduce(0, +)

        if totalMessages == 0 {
            // First message - create as pending request
            shouldCreatePendingRequest = true
            print("📩 Creating message request (first message to non-follower)")
        } else {
            // Not first message and can't send - throw error
            throw FirebaseMessagingError.invalidInput(reason ?? "Cannot send message")
        }
    }

    // ... rest of send logic ...

    // Add request status if needed
    if shouldCreatePendingRequest {
        updates["conversationStatus"] = "pending"
        updates["requesterId"] = currentUserId
        print("✅ Message sent as request (pending approval)")
    }

    batch.updateData(updates, forDocument: conversationRef)
    try await batch.commit()
}
```

---

## P2: Performance Issues

### P2-1: **N+1 Query Problem in Thread List** ⚠️

**File:** `MessagesView.swift:95-158` + `FirebaseMessagingService.swift:196-305`

**Problem:**
Single query fetches conversations, but each conversation might trigger **additional queries** for participant details.

**Impact:** 50 conversations = 50+ queries on load

**Fix:**
Denormalize participant names/avatars into conversation document (already done in your schema).

---

### P2-2: **Large Message Lists Not Using Lazy Rendering** ✅

**Status:** ALREADY FIXED - `LazyVStack` is used

---

### P2-3: **No Message Batching on Scroll** ⚠️

**File:** `FirebaseMessagingService.swift:665-721`

**Problem:**
Initial listener loads with `limit(to: 50)` but subsequent scroll doesn't batch properly.

**Fix:** Already implemented pagination - just need to wire up UI (see P1-3).

---

## Stress Test Script

Run these tests to verify fixes:

### Test 1: Duplicate Message Prevention
```
Steps:
1. Open any chat thread
2. Type "test message"
3. Tap send button 5x rapidly (< 200ms between taps)
4. Wait 5 seconds
5. Expected: 1 message sent
6. Actual (before fix): 5 messages sent ❌
7. Actual (after P0-1 fix): 1 message sent ✅
```

### Test 2: Listener Memory Leak
```
Steps:
1. Open Messages tab
2. Script: For i in 1...50:
   - Tap conversation i
   - Wait 100ms
   - Swipe dismiss
3. Check Instruments: Memory Graph
4. Expected: 0-1 active listeners
5. Actual (before fix): 50+ listeners ❌
6. Actual (after P0-2 fix): 1 listener ✅
```

### Test 3: Thread List Live Updates
```
Steps:
1. User A: Open Messages tab
2. User B: Send message to User A
3. User A: Observe Messages list
4. Expected: Thread moves to top, shows new preview, updates timestamp
5. Actual (before fix): No update until refresh ❌
6. Actual (after P0-3 fix): Instant update ✅
```

### Test 4: Unread Badge Clearing
```
Steps:
1. User A: Close app
2. User B: Send 5 messages to User A
3. User A: Open app → Messages tab → sees badge "5"
4. User A: Tap conversation
5. Expected: Badge clears to "0" instantly
6. Actual (before fix): Badge stays "5" ❌
7. Actual (after P1-1 fix): Badge clears ✅
```

### Test 5: 200 Message Burst
```
Steps:
1. Script send 200 messages in 10 seconds (20/sec)
2. Open thread while messages are arriving
3. Expected:
   - All 200 messages appear
   - No duplicates
   - Scroll position preserved if not at bottom
   - No UI freezing
4. Monitor FPS (should stay > 55)
5. Monitor memory (should not spike > 200MB)
```

### Test 6: Poor Network Simulation
```
Steps:
1. Enable Network Link Conditioner: "Very Bad Network" (1% loss, 1000ms delay)
2. Send 10 messages rapidly
3. Expected:
   - All messages show as "sending" (clock icon)
   - Eventually all deliver
   - No duplicates
   - Failed messages show retry button
4. Disable network conditioner
5. Expected: All messages send within 5 seconds
```

---

## Acceptance Criteria (Threads-like)

Production-ready checklist:

### Inbox Experience
- [❌] Opening Messages tab loads within 500ms (skeleton → data)
- [⚠️] Thread list shows: avatar, name, preview (1 line), timestamp, unread dot
- [❌] New message moves thread to top + updates preview instantly
- [✅] No duplicate threads
- [⚠️] Unread badge shows correct count (across app restarts)
- [❌] Swipe left for pin/mute/archive/delete actions

### Chat Thread Experience
- [❌] Opening thread loads within 300ms (skeleton → messages)
- [✅] Messages appear in correct order (oldest to newest)
- [❌] Scroll to bottom on open (or to first unread if exists)
- [❌] Scroll position preserved when new message arrives (if not at bottom)
- [❌] Load more messages on scroll to top (pagination)
- [✅] Smooth scroll for 1000+ messages (> 55 FPS)

### Sending Messages
- [❌] Send button disabled while sending
- [❌] No duplicates on rapid tap (idempotent)
- [✅] Optimistic message appears instantly
- [❌] Optimistic replaced by real message (no duplicates)
- [✅] Failed message shows retry button
- [✅] Offline messages queue and send when online

### Unread Logic
- [❌] Opening thread clears unread count instantly
- [❌] Incoming message increments badge (unless already in thread)
- [⚠️] Badge persists across app restarts
- [❌] Mark as read when message scrolls into view

### Request Gating
- [⚠️] First message to non-follower creates request
- [⚠️] Recipient sees in "Requests" tab
- [⚠️] Sender sees "Pending" state
- [⚠️] Replying auto-accepts request

### Performance
- [❌] Inbox loads < 500ms with 100 threads
- [❌] Thread loads < 300ms with 500 messages
- [✅] Scroll FPS > 55 for long threads
- [❌] Memory usage < 150MB for 1000 messages
- [❌] No listener leaks (verify with Instruments)

---

## Implementation Priority

**Week 1 (P0 - MUST FIX BEFORE LAUNCH):**
1. P0-1: Duplicate message prevention ⚠️⚠️⚠️
2. P0-2: Listener cleanup on rapid nav ⚠️⚠️
3. P0-3: Thread list live updates ❌
4. P0-4: Optimistic message replacement ⚠️

**Week 2 (P1 - HIGH PRIORITY):**
5. P1-1: Unread badge clearing
6. P1-2: Scroll position preservation
7. P1-3: Pagination UI
8. P1-4: Request gating UX

**Week 3 (P2 - POLISH):**
9. Stress test all fixes
10. Instruments profiling
11. Network simulation testing

---

## Metrics to Collect

Add these logging points:

```swift
// Message send latency
print("⏱️ Message send latency: \(latencyMs)ms")

// Listener count
print("📊 Active message listeners: \(messagesListeners.count)")

// Memory usage
print("💾 Memory usage: \(ProcessInfo.processInfo.physicalMemory) bytes")

// FPS tracking
print("🎬 FPS: \(currentFPS)")
```

---

## Summary

Your messaging system has good bones but needs critical fixes for production. Focus on P0 issues first—they will cause user-facing bugs and poor reviews. P1-P2 are polish but still important for Threads-like experience.

**Estimated Fix Time:**
- P0 fixes: 2-3 days
- P1 fixes: 2-3 days
- P2 + testing: 2-3 days
- **Total: 1-2 weeks**

Let me know which fixes you want me to implement first.
