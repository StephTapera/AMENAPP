# 🚀 Quick Reference Card - Messaging Features

## Import Required Files
```swift
import MessagingEnhancedFeatures
import MemeGenerator
import ScrollViewHelpers
```

## 1️⃣ Delivery Status (1 line)
```swift
DeliveryStatusView(status: message.deliveryStatus, timestamp: message.timestamp)
```

## 2️⃣ Failed Message Retry (3 lines)
```swift
if message.isSendFailed {
    FailedMessageBanner(message: message, onRetry: { retry() }, onDelete: { delete() })
}
```

## 3️⃣ Scroll to Bottom (4 lines)
```swift
if showScrollButton {
    ScrollToBottomButton(unreadCount: count) { scrollToBottom() }
        .padding()
}
```

## 4️⃣ Disappearing Messages (2 lines)
```swift
.sheet(isPresented: $showDisappear) {
    DisappearingMessageSettingsView(duration: $duration)
}
```

## 5️⃣ Quick Replies (2 lines)
```swift
.sheet(isPresented: $showQuickReplies) {
    QuickReplyPickerView(selectedText: $messageText)
}
```

## 6️⃣ Link Previews (3 lines)
```swift
if let preview = message.linkPreviews.first {
    LinkPreviewCard(preview: preview)
}
```

## 7️⃣ @Mentions (3 lines)
```swift
EnhancedChatInputBar(
    conversationParticipants: participants, // Enables mentions
    ...
)
```

## 8️⃣ Meme Generator (2 lines)
```swift
.sheet(isPresented: $showMeme) {
    MemeGeneratorView { meme in sendImage(meme) }
}
```

## 📋 AppMessage Properties Added
```swift
var isSent: Bool = false
var isDelivered: Bool = false  
var isSendFailed: Bool = false
var disappearAfter: TimeInterval? = nil
var linkPreviews: [LinkPreview] = []
var mentionedUserIds: [String] = []
```

## 🎯 Common Patterns

### Send Message with Status
```swift
func sendMessage() async {
    message.isSent = false
    do {
        try await service.send(message)
        message.isSent = true
        message.isDelivered = true
    } catch {
        message.isSendFailed = true
    }
}
```

### Detect Links
```swift
let urls = MentionParser.detectLinks(in: message.text)
for url in urls {
    let loader = LinkPreviewLoader()
    loader.loadPreview(for: url)
}
```

### Parse Mentions
```swift
let mentions = MentionParser.detectMentions(in: message.text)
message.mentionedUserIds = mentions.compactMap { username in
    participants.first { $0.username == username }?.id
}
```

### Schedule Disappearing Message
```swift
if let duration = conversation.disappearDuration?.rawValue, duration > 0 {
    timer.scheduleDisappear(messageId: message.id, after: duration) {
        deleteMessage(message)
    }
}
```

## 🎨 UI Integration Points

**Message Bubble:**
```swift
ModernMessageBubble(...)
    // Add delivery status
    DeliveryStatusView(...)
    
    // Add link previews
    if !message.linkPreviews.isEmpty {
        ForEach(message.linkPreviews) { preview in
            LinkPreviewCard(preview: preview)
        }
    }
```

**Input Bar:**
```swift
// Replace old input with enhanced version
EnhancedChatInputBar(
    messageText: $text,
    selectedImages: $images,
    conversationParticipants: participants, // For mentions
    onSend: { send() },
    onPhotoPicker: { showPicker = true }
)
```

**Message List:**
```swift
ScrollableMessageList(
    messages: $messages,
    showScrollButton: $showButton,
    scrollProxy: proxy
) { message, prev, next in
    // Your message view
}
```

**Conversation Settings Menu:**
```swift
Menu {
    Button("Quick Replies") { showQuickReplies = true }
    Button("Disappearing Messages") { showDisappear = true }
    Button("Meme Generator") { showMeme = true }
}
```

## 🔥 One-Liners

```swift
// Highlight mentions
Text(MentionParser.highlightMentions(in: text))

// Get delivery status
let status = message.deliveryStatus

// Check if should show scroll button
showButton = scrollOffset < -500

// Format disappearing duration
Text(duration.displayName) // "10 seconds", "1 hour", etc.

// Get quick reply categories
QuickReplyCategory.allCases.forEach { ... }
```

## 📱 Button Icons

| Feature | System Image |
|---------|-------------|
| Quick Replies | `text.bubble` |
| Meme Generator | `face.smiling` |
| Disappearing | `timer` |
| Scroll Down | `arrow.down` |
| Link | `link` |
| Mention | `at` |
| Retry | `arrow.clockwise` |

## ⌨️ Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Send | Return |
| New Line | Shift+Return |
| Quick Replies | ⌘K |
| @ Mention | @ |
| Emoji | ⌘⌃Space |

---

**Pro Tip:** Keep this card open while integrating! 🎯
