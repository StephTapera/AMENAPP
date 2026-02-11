# UnifiedChatView Implementation Guide

## Quick Start

### Basic Usage
```swift
import SwiftUI

struct MessagesView: View {
    let conversation: ChatConversation
    
    var body: some View {
        NavigationStack {
            UnifiedChatView(conversation: conversation)
        }
    }
}
```

### Creating a Conversation
```swift
let conversation = ChatConversation(
    id: "chat_\(UUID().uuidString)",
    name: "John Doe",
    lastMessage: "Hey there!",
    timestamp: Date().formatted(),
    isGroup: false,
    unreadCount: 0,
    avatarColor: .blue
)
```

---

## Customization Examples

### 1. Custom Media Buttons

Add more media types to the grid:

```swift
// In collapsibleMediaSection
LazyVGrid(columns: [
    GridItem(.flexible()),
    GridItem(.flexible()),
    GridItem(.flexible()),
    GridItem(.flexible())
], spacing: 12) {
    // Existing buttons...
    
    // Add new button
    MediaButton(
        icon: "mic.fill",
        title: "Audio",
        color: Color(red: 0.15, green: 0.15, blue: 0.15)
    ) {
        // Handle audio recording
        startAudioRecording()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isMediaSectionExpanded = false
        }
    }
    
    MediaButton(
        icon: "location.fill",
        title: "Location",
        color: Color(red: 0.15, green: 0.15, blue: 0.15)
    ) {
        // Handle location sharing
        shareLocation()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isMediaSectionExpanded = false
        }
    }
    
    // ... more buttons
}
```

### 2. Custom Message Styling

Create themed message bubbles:

```swift
// Add to LiquidGlassMessageBubble
private func bubbleBackground(for message: AppMessage) -> some View {
    if isFromCurrentUser {
        // Theme 1: Black gradient (current)
        return AnyView(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.15, blue: 0.15),
                            Color(red: 0.05, green: 0.05, blue: 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
    } else {
        // Theme 2: White with border
        return AnyView(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
        )
    }
}
```

### 3. Add Voice Recording

Implement long-press to record:

```swift
// Add state
@State private var isRecording = false
@State private var recordingDuration: TimeInterval = 0

// Replace expand button with recording capability
var recordButton: some View {
    Button {
        if !isRecording {
            // Short press - expand media
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isMediaSectionExpanded.toggle()
            }
        }
    } label: {
        ZStack {
            Circle()
                .fill(isRecording ? Color.red : .white)
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            
            Image(systemName: isRecording ? "mic.fill" : (isMediaSectionExpanded ? "chevron.down" : "plus"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isRecording ? .white : Color(red: 0.15, green: 0.15, blue: 0.15))
        }
    }
    .simultaneousGesture(
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in
                startRecording()
            }
    )
    .simultaneousGesture(
        DragGesture(minimumDistance: 0)
            .onEnded { _ in
                if isRecording {
                    stopRecording()
                }
            }
    )
}

func startRecording() {
    isRecording = true
    let haptic = UIImpactFeedbackGenerator(style: .heavy)
    haptic.impactOccurred()
    // Start audio recording
}

func stopRecording() {
    isRecording = false
    let haptic = UINotificationFeedbackGenerator()
    haptic.notificationOccurred(.success)
    // Stop and send recording
}
```

### 4. Add Message Status Indicators

Show delivered/read status:

```swift
// Extend AppMessage model
extension AppMessage {
    var statusIcon: String {
        if isRead {
            return "checkmark.circle.fill"
        } else if isDelivered {
            return "checkmark.circle"
        } else {
            return "clock"
        }
    }
    
    var statusColor: Color {
        if isRead {
            return .blue
        } else if isDelivered {
            return .gray
        } else {
            return .gray.opacity(0.5)
        }
    }
}

// Add to message bubble
HStack(spacing: 4) {
    Text(message.formattedTimestamp)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    
    if isFromCurrentUser {
        Image(systemName: message.statusIcon)
            .font(.system(size: 10))
            .foregroundColor(message.statusColor)
    }
}
.padding(.horizontal, 12)
```

### 5. Add Rich Link Previews

Detect and preview URLs:

```swift
// Add to message bubble
if let url = message.firstURL {
    LinkPreview(url: url)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
}

struct LinkPreview: View {
    let url: URL
    @State private var metadata: LinkMetadata?
    
    var body: some View {
        if let metadata = metadata {
            VStack(alignment: .leading, spacing: 8) {
                if let image = metadata.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.title ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    
                    Text(metadata.description ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    Text(url.host ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                }
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
    }
}
```

---

## Performance Optimization

### 1. Message Virtualization

Use LazyVStack for efficient scrolling:

```swift
// Already implemented in messagesScrollView
ScrollView(showsIndicators: false) {
    LazyVStack(spacing: 12) {  // ← LazyVStack only loads visible items
        ForEach(messages) { message in
            LiquidGlassMessageBubble(...)
                .id(message.id)
        }
    }
}
```

### 2. Image Caching

Cache downloaded images:

```swift
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSURL, UIImage>()
    
    func get(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }
    
    func set(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

// Usage in message bubble
AsyncImage(url: message.imageURL) { phase in
    if let image = phase.image {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .onAppear {
                ImageCache.shared.set(image, for: message.imageURL)
            }
    } else if let cached = ImageCache.shared.get(message.imageURL) {
        Image(uiImage: cached)
            .resizable()
            .aspectRatio(contentMode: .fill)
    } else {
        ProgressView()
    }
}
```

### 3. Debounced Typing Indicator

Prevent excessive updates:

```swift
// Already implemented in handleTypingIndicator
private func handleTypingIndicator(isTyping: Bool) {
    typingDebounceTimer?.invalidate()
    
    Task {
        try? await messagingService.updateTypingStatus(
            conversationId: conversation.id,
            isTyping: isTyping
        )
    }
    
    if isTyping {
        // Reset after 3 seconds of no typing
        typingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Task {
                try? await messagingService.updateTypingStatus(
                    conversationId: conversation.id,
                    isTyping: false
                )
            }
        }
    }
}
```

---

## Advanced Features

### 1. Message Reactions

Implement emoji reactions:

```swift
// Add to message bubble
.onTapGesture(count: 2) {
    // Double-tap to add heart reaction
    onReact("❤️")
}
.contextMenu {
    Button {
        onReact("❤️")
    } label: {
        Label("Love", systemImage: "heart.fill")
    }
    
    Button {
        onReact("👍")
    } label: {
        Label("Like", systemImage: "hand.thumbsup.fill")
    }
    
    Button {
        onReact("😂")
    } label: {
        Label("Laugh", systemImage: "face.smiling")
    }
    
    // ... more reactions
}
```

### 2. Message Threading

Reply to specific messages:

```swift
// Add reply bar above input
if let replyingTo = replyingTo {
    HStack {
        VStack(alignment: .leading, spacing: 2) {
            Text("Replying to \(replyingTo.senderName ?? "Unknown")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.blue)
            
            Text(replyingTo.text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        
        Spacer()
        
        Button {
            withAnimation {
                replyingTo = nil
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    .padding(12)
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.blue.opacity(0.1))
    )
    .padding(.horizontal, 12)
    .padding(.bottom, 8)
}
```

### 3. Message Search

Add search functionality:

```swift
@State private var searchText = ""
@State private var showSearch = false

var filteredMessages: [AppMessage] {
    if searchText.isEmpty {
        return messages
    } else {
        return messages.filter { message in
            message.text.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// Add search bar in header
if showSearch {
    HStack {
        Image(systemName: "magnifyingglass")
            .foregroundColor(.gray)
        
        TextField("Search messages", text: $searchText)
            .textFieldStyle(.plain)
        
        if !searchText.isEmpty {
            Button {
                searchText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
        }
    }
    .padding(8)
    .background(
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.systemGray6))
    )
}
```

### 4. Media Upload Progress

Show upload progress for images/videos:

```swift
@State private var uploadProgress: [UUID: Double] = [:]

struct MediaUploadView: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            // Thumbnail
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundColor(.white)
                .frame(width: 100, height: 100)
                .background(Color.gray.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Progress overlay
            if progress < 1.0 {
                ZStack {
                    Color.black.opacity(0.5)
                    
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .tint(.white)
                            .frame(width: 60)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
```

---

## Testing Strategies

### 1. Unit Tests

```swift
import Testing

@Suite("UnifiedChatView Tests")
struct UnifiedChatViewTests {
    
    @Test("Message bubble colors match theme")
    func messageBubbleColors() async throws {
        let sentMessage = AppMessage(
            id: UUID(),
            text: "Hello",
            senderId: "user1",
            timestamp: Date()
        )
        
        // Test sent message has black background
        // Test received message has white background
    }
    
    @Test("Media section toggles correctly")
    func mediaSectionToggle() async throws {
        // Test initial state: collapsed
        // Test after tap: expanded
        // Test after second tap: collapsed
    }
    
    @Test("Keyboard dismisses media section")
    func keyboardDismissesMedia() async throws {
        // Test media expanded
        // Test keyboard appears
        // Verify media auto-collapses
    }
}
```

### 2. UI Tests

```swift
import XCTest

class UnifiedChatViewUITests: XCTestCase {
    
    func testSendMessage() {
        let app = XCUIApplication()
        app.launch()
        
        let messageField = app.textFields["Message..."]
        messageField.tap()
        messageField.typeText("Hello World")
        
        let sendButton = app.buttons["Send message"]
        sendButton.tap()
        
        XCTAssertTrue(app.staticTexts["Hello World"].exists)
    }
    
    func testMediaSectionExpands() {
        let app = XCUIApplication()
        app.launch()
        
        let expandButton = app.buttons["Expand media options"]
        expandButton.tap()
        
        XCTAssertTrue(app.buttons["Attach photo"].exists)
        XCTAssertTrue(app.buttons["Attach video"].exists)
    }
}
```

### 3. Accessibility Tests

```swift
func testAccessibility() {
    let app = XCUIApplication()
    app.launch()
    
    // Test VoiceOver labels
    XCTAssertTrue(app.buttons["Expand media options"].exists)
    XCTAssertTrue(app.textFields["Message, text field"].exists)
    XCTAssertTrue(app.buttons["Send message"].exists)
    
    // Test minimum touch targets (44x44pt)
    let expandButton = app.buttons["Expand media options"]
    XCTAssertGreaterThanOrEqual(expandButton.frame.width, 44)
    XCTAssertGreaterThanOrEqual(expandButton.frame.height, 44)
}
```

---

## Troubleshooting

### Issue: Keyboard not dismissing properly
```swift
// Solution: Add tap gesture to dismiss
ScrollView(showsIndicators: false) {
    // ... content
}
.simultaneousGesture(
    TapGesture()
        .onEnded {
            isInputFocused = false
        }
)
```

### Issue: Messages not scrolling to bottom
```swift
// Solution: Ensure ID is set and proxy is used correctly
LazyVStack(spacing: 12) {
    ForEach(messages) { message in
        LiquidGlassMessageBubble(...)
            .id(message.id)  // ← Important!
    }
}

// In onChange:
if let lastMessage = messages.last {
    withAnimation(.easeOut(duration: 0.3)) {
        proxy.scrollTo(lastMessage.id, anchor: .bottom)
    }
}
```

### Issue: Media section animation stutters
```swift
// Solution: Use proper transition
if isMediaSectionExpanded {
    collapsibleMediaSection
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
}
```

### Issue: Input bar not at absolute bottom
```swift
// Solution: Use proper spacing calculation
.frame(height: inputBarHeight + keyboardHeight)

// And offset:
.offset(y: -keyboardHeight)
```

---

## Best Practices

### 1. State Management
- Keep state minimal and focused
- Use `@State` for local view state
- Use `@StateObject` for view models
- Use `@Environment` for shared data

### 2. Animations
- Use spring animations for natural feel
- Match timing across related animations
- Add haptic feedback for key interactions
- Test on actual devices (not just simulator)

### 3. Performance
- Use `LazyVStack` for message lists
- Implement image caching
- Debounce typing indicators
- Limit real-time listener scope

### 4. Accessibility
- Provide clear VoiceOver labels
- Support Dynamic Type
- Ensure minimum touch targets (44pt)
- Test with VoiceOver enabled

### 5. Error Handling
- Show user-friendly error messages
- Provide retry mechanisms
- Log errors for debugging
- Handle offline scenarios

---

## Integration Checklist

- [ ] Import UnifiedChatView into your project
- [ ] Set up Firebase messaging service
- [ ] Configure notification permissions
- [ ] Test on multiple device sizes
- [ ] Verify VoiceOver compatibility
- [ ] Test with poor network conditions
- [ ] Validate message persistence
- [ ] Test media upload/download
- [ ] Verify keyboard behavior
- [ ] Test landscape orientation
- [ ] Profile for performance issues
- [ ] Add analytics events
- [ ] Document custom modifications

---

## Support & Resources

### Documentation
- `UNIFIED_CHAT_ENHANCEMENTS.md` - Feature overview
- `UNIFIED_CHAT_VISUAL_GUIDE.md` - Visual specifications
- This file - Implementation guide

### Example Projects
```swift
// Basic chat app structure
struct ChatApp: App {
    var body: some Scene {
        WindowGroup {
            ConversationListView()
        }
    }
}

struct ConversationListView: View {
    @StateObject private var messagingService = FirebaseMessagingService.shared
    
    var body: some View {
        NavigationStack {
            List(messagingService.conversations) { conversation in
                NavigationLink(destination: UnifiedChatView(conversation: conversation)) {
                    ConversationRow(conversation: conversation)
                }
            }
            .navigationTitle("Messages")
        }
    }
}
```

---

**Version:** 2.0
**Last Updated:** February 1, 2026
**Status:** Production Ready ✅
