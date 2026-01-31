# 🔧 Fix Sheet Presentation - Step by Step

## The Problem

You have **4 separate sheet modifiers** on MessagesView:
1. `showChatView` - for opening conversations
2. `showNewMessage` - for user search
3. `showCreateGroup` - for group creation
4. `showSettings` - for settings

When multiple sheets try to present, SwiftUI gets confused and **none of them work**.

## The Solution

Use **ONE sheet modifier** with an enum to control which content shows.

---

## Step-by-Step Fix

### ✅ Step 1: Add the Enum

Add this at the TOP of MessagesView.swift (after the imports, before struct MessagesView):

```swift
// MARK: - Sheet Type Enum

enum MessageSheetType: Identifiable {
    case chat(ChatConversation)
    case newMessage
    case createGroup
    case settings
    
    var id: String {
        switch self {
        case .chat(let conversation):
            return "chat_\(conversation.id)"
        case .newMessage:
            return "newMessage"
        case .createGroup:
            return "createGroup"
        case .settings:
            return "settings"
        }
    }
}
```

---

### ✅ Step 2: Replace State Variables

FIND these lines in MessagesView:

```swift
@State private var selectedConversation: ChatConversation?
@State private var showNewMessage = false
@State private var showCreateGroup = false
@State private var showChatView = false
@State private var showSettings = false
```

REPLACE with:

```swift
@State private var activeSheet: MessageSheetType?
```

**Note:** Keep `showDeleteConfirmation` - that's separate!

---

### ✅ Step 3: Remove Old Modifiers

FIND these lines in your `body` var:

```swift
.modifier(ChatSheetModifier(
    showChatView: $showChatView,
    selectedConversation: $selectedConversation
))
.modifier(SheetsModifier(
    showNewMessage: $showNewMessage,
    showCreateGroup: $showCreateGroup,
    showSettings: $showSettings,
    startConversation: startConversation
))
```

REMOVE them completely!

---

### ✅ Step 4: Add Single Sheet Modifier

ADD this right after `.navigationBarHidden(true)` in your body:

```swift
.sheet(item: $activeSheet) { sheetType in
    switch sheetType {
    case .chat(let conversation):
        ModernConversationDetailView(conversation: conversation)
            .onAppear {
                print("\n🎬 SHEET OPENED: Chat with \(conversation.name)")
            }
    
    case .newMessage:
        MessagingUserSearchView { firebaseUser in
            let selectedUser = SearchableUser(from: firebaseUser)
            Task {
                await startConversation(with: selectedUser)
            }
        }
        .onAppear {
            print("\n🎬 SHEET OPENED: New Message Search")
        }
    
    case .createGroup:
        CreateGroupView()
            .onAppear {
                print("\n🎬 SHEET OPENED: Create Group")
            }
    
    case .settings:
        MessageSettingsView()
            .onAppear {
                print("\n🎬 SHEET OPENED: Settings")
            }
    }
}
```

---

### ✅ Step 5: Update Conversation Row Taps

FIND where conversations are tapped (look for `.onTapGesture` or similar with conversation rows).

REPLACE code like this:

```swift
selectedConversation = conversation
showChatView = true
```

WITH:

```swift
activeSheet = .chat(conversation)
```

**Full example:**

```swift
.onTapGesture {
    print("\n💬 CONVERSATION TAPPED: \(conversation.name)")
    activeSheet = .chat(conversation)
}
```

---

### ✅ Step 6: Update New Message Button

FIND the "+" or "New Message" button tap handler.

REPLACE:

```swift
showNewMessage = true
```

WITH:

```swift
activeSheet = .newMessage
```

---

### ✅ Step 7: Update Create Group Button

FIND the "Create Group" button.

REPLACE:

```swift
showCreateGroup = true
```

WITH:

```swift
activeSheet = .createGroup
```

---

### ✅ Step 8: Update Settings Button

FIND the settings gear icon or button.

REPLACE:

```swift
showSettings = true
```

WITH:

```swift
activeSheet = .settings
```

---

### ✅ Step 9: Update startConversation Function

FIND your `startConversation` function.

UPDATE the part where it sets `selectedConversation` and `showChatView`:

**FIND:**
```swift
await MainActor.run {
    showNewMessage = false
}

// ... later ...

await MainActor.run {
    selectedConversation = conversation
    showChatView = true
}
```

**REPLACE WITH:**
```swift
await MainActor.run {
    activeSheet = nil  // Dismiss search sheet
}

// ... later ...

await MainActor.run {
    activeSheet = .chat(conversation)  // Open chat
}
```

**Full updated function:**

```swift
private func startConversation(with user: SearchableUser) async {
    print("\n🚀 START CONVERSATION: \(user.displayName)")
    
    do {
        let conversationId = try await messagingService.getOrCreateDirectConversation(
            withUserId: user.id,
            userName: user.displayName
        )
        
        print("✅ Got conversation ID: \(conversationId)")
        
        // Dismiss search sheet
        await MainActor.run {
            activeSheet = nil
        }
        
        // Wait for dismissal
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // Open chat
        if let conversation = conversations.first(where: { $0.id == conversationId }) {
            print("✅ Found conversation in list")
            await MainActor.run {
                activeSheet = .chat(conversation)
            }
        } else {
            print("⚠️ Creating temp conversation")
            let tempConversation = ChatConversation(
                id: conversationId,
                name: user.displayName,
                lastMessage: "",
                timestamp: "Just now",
                isGroup: false,
                unreadCount: 0,
                avatarColor: .blue
            )
            await MainActor.run {
                activeSheet = .chat(tempConversation)
            }
        }
        
        print("✅ Chat opened!")
        
    } catch {
        print("❌ Error: \(error)")
        await MainActor.run {
            activeSheet = nil
        }
    }
}
```

---

### ✅ Step 10: Update Coordinator Handler

FIND `handleCoordinatorRequest` or similar (where `messagingCoordinator.conversationToOpen` is used).

UPDATE to use `activeSheet`:

```swift
private func handleCoordinatorRequest(conversationId: String) {
    print("\n📞 COORDINATOR: Opening conversation \(conversationId)")
    
    if let conversation = conversations.first(where: { $0.id == conversationId }) {
        activeSheet = .chat(conversation)
    }
    
    messagingCoordinator.conversationToOpen = nil
}
```

---

### ✅ Step 11: Remove Old Modifier Structs

At the BOTTOM of MessagesView.swift, FIND and DELETE these entire structs:

```swift
struct ChatSheetModifier: ViewModifier {
    // ... delete entire struct
}

struct SheetsModifier: ViewModifier {
    // ... delete entire struct
}
```

These are no longer needed!

---

### ✅ Step 12: Add Debug Logging (Optional)

Add this to help debug:

```swift
.onChange(of: activeSheet) { oldValue, newValue in
    print("\n🔄 SHEET STATE CHANGED")
    print("   - Old: \(oldValue?.id ?? "nil")")
    print("   - New: \(newValue?.id ?? "nil")")
}
```

---

## 🧪 Testing

### Test 1: Existing Conversation

1. Run the app
2. Tap an existing conversation
3. Check console for:
   ```
   💬 CONVERSATION TAPPED: [Name]
   🔄 SHEET STATE CHANGED
      - Old: nil
      - New: chat_[id]
   🎬 SHEET OPENED: Chat with [Name]
   ```
4. **Does the chat open?** ✅

### Test 2: New Conversation

1. Tap the "+" button
2. Check console for:
   ```
   🔄 SHEET STATE CHANGED
      - Old: nil
      - New: newMessage
   🎬 SHEET OPENED: New Message Search
   ```
3. Select a user
4. Check for:
   ```
   🚀 START CONVERSATION: [Name]
   ✅ Got conversation ID: [id]
   ✅ Chat opened!
   🔄 SHEET STATE CHANGED
      - New: chat_[id]
   🎬 SHEET OPENED: Chat with [Name]
   ```
5. **Does the chat open?** ✅

---

## ✅ Checklist

Before you test, make sure you've done ALL steps:

- [ ] Added `MessageSheetType` enum
- [ ] Replaced 5 @State vars with 1 `activeSheet`
- [ ] Removed old `.modifier()` calls
- [ ] Added single `.sheet(item:)` modifier
- [ ] Updated conversation tap to set `activeSheet`
- [ ] Updated new message button
- [ ] Updated create group button
- [ ] Updated settings button
- [ ] Updated `startConversation` function
- [ ] Updated coordinator handler
- [ ] Deleted old modifier structs
- [ ] Clean build (Cmd+Shift+K, then Cmd+B)

---

## 🚨 Common Mistakes

### ❌ Forgot to remove old modifiers
If you keep both old and new sheet modifiers, it still won't work!

### ❌ Didn't update all button handlers
Every place that used to set `showChatView = true` must now set `activeSheet = .chat(...)`

### ❌ Didn't delete old structs
The `ChatSheetModifier` and `SheetsModifier` structs will cause errors if not deleted

### ❌ Forgot to clean build
Old code might be cached. Always clean build after major changes!

---

## 📊 Expected Results

**BEFORE:**
- Test button: ❌ Nothing happens
- Tap conversation: ❌ Nothing happens
- New message: ❌ Nothing happens

**AFTER:**
- Test button: ✅ Chat opens
- Tap conversation: ✅ Chat opens
- New message: ✅ Search opens, then chat opens
- Settings: ✅ Settings opens
- Create group: ✅ Group creation opens

---

## Still Not Working?

If after all these steps it STILL doesn't work:

1. **Copy your entire MessagesView.swift file**
2. **Copy all console output when testing**
3. **Tell me:**
   - Did you complete all 12 steps?
   - Do you see the sheet state change logs?
   - Any compiler errors?
   - What platform (iOS simulator vs device)?

I'll help you debug further!

---

## Quick Recovery

If you mess something up, you can revert:

1. **Git:** `git checkout MessagesView.swift`
2. **No Git:** Use Xcode's version history (Editor → Show Change)

Then try again carefully! 🙂
