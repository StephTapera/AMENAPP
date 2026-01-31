# ChatView & Messaging Issues - Debugging Guide

## 🐛 Issues Reported

1. **Cannot send messages in ChatView**
2. **ChatView doesn't open when starting new conversation**

---

## 🔍 Diagnostic Steps

### Issue 1: Can't Send Messages

#### Symptom:
Messages typed in ChatView don't get sent when pressing send button.

#### Possible Causes & Solutions:

**1. Check Firebase Authentication**
```swift
// Add this to ChatView.onAppear to debug:
print("🔐 Current User ID: \(currentUserId)")
print("🔐 Is Authenticated: \(Auth.auth().currentUser != nil)")
```

**Expected Output:**
```
🔐 Current User ID: abc123...
🔐 Is Authenticated: true
```

**If you see empty user ID or false:**
- User is not logged in
- Sign in again

---

**2. Check Conversation ID**
```swift
// Add this to ChatView.onAppear:
print("💬 Conversation ID: \(conversation.id)")
print("💬 Conversation Name: \(conversation.name)")
```

**Expected Output:**
```
💬 Conversation ID: conv_abc123...
💬 Conversation Name: John Doe
```

**If you see weird format or empty:**
- Conversation wasn't created properly
- Check `getOrCreateDirectConversation` logs

---

**3. Check Send Function Execution**
Add debug logs to `sendMessage()` in ChatView:

```swift
private func sendMessage() {
    guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        print("⚠️ Message text is empty, aborting")
        return
    }
    
    let textToSend = messageText
    let conversationId = conversation.id
    
    print("📤 Attempting to send message:")
    print("  - Text: \(textToSend)")
    print("  - Conversation ID: \(conversationId)")
    print("  - Current User: \(currentUserId)")
    
    // Clear input immediately for better UX
    messageText = ""
    
    Task {
        do {
            print("🚀 Calling messagingService.sendMessage...")
            try await messagingService.sendMessage(
                conversationId: conversationId,
                text: textToSend
            )
            
            print("✅ Message sent successfully!")
            
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
        } catch {
            print("❌ Error sending message: \(error)")
            print("❌ Error type: \(type(of: error))")
            print("❌ Error description: \(error.localizedDescription)")
            
            await MainActor.run {
                // Restore message text on error
                messageText = textToSend
                
                // Show error to user
                errorAlertMessage = "Failed to send message. Please check your connection and try again."
                showError = true
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
}
```

**Look for these logs:**
- ✅ "Attempting to send message" - Function called
- ✅ "Calling messagingService.sendMessage..." - Service called
- ✅ "Message sent successfully!" - All good!
- ❌ Error logs - Check Firestore rules, network, etc.

---

**4. Check Firestore Rules**
Your Firestore security rules might be blocking writes.

Go to Firebase Console → Firestore Database → Rules

**Check if you have:**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Conversations
    match /conversations/{conversationId} {
      allow read: if request.auth != null && 
                     request.auth.uid in resource.data.participantIds;
      allow create: if request.auth != null;
      allow update: if request.auth != null && 
                       request.auth.uid in resource.data.participantIds;
      
      // Messages in conversations
      match /messages/{messageId} {
        allow read: if request.auth != null;
        allow create: if request.auth != null;
        allow update: if request.auth != null;
        allow delete: if request.auth != null && 
                         request.auth.uid == resource.data.senderId;
      }
    }
  }
}
```

**If your rules are too restrictive:**
- Messages won't send
- You'll see permission denied errors in console

---

**5. Check Network Connection**
```swift
// Add to ChatView:
import Network

let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    if path.status == .satisfied {
        print("✅ Network is connected")
    } else {
        print("❌ No network connection!")
    }
}
let queue = DispatchQueue(label: "NetworkMonitor")
monitor.start(queue: queue)
```

---

### Issue 2: ChatView Doesn't Open for New Conversations

#### Symptom:
When you tap a user in MessagingUserSearchView, the ChatView doesn't appear.

#### Debug the Flow:

**1. Check if `startConversation` is called**

Add logs to `MessagingUserSearchView`:

```swift
// In the onTap or selection handler:
MessagingUserSearchView { firebaseUser in
    print("👤 User selected: \(firebaseUser.displayName)")
    print("👤 User ID: \(firebaseUser.id)")
    
    let selectedUser = SearchableUser(from: firebaseUser)
    
    Task {
        print("🚀 Starting conversation task...")
        await startConversation(with: selectedUser)
        print("✅ Conversation task complete")
    }
}
```

---

**2. Add comprehensive logging to `startConversation`**

```swift
private func startConversation(with user: SearchableUser) async {
    print("\n=== START CONVERSATION DEBUG ===")
    print("👤 User: \(user.displayName)")
    print("🆔 User ID: \(user.id)")
    
    do {
        print("📞 Calling getOrCreateDirectConversation...")
        
        let conversationId = try await messagingService.getOrCreateDirectConversation(
            withUserId: user.id,
            userName: user.displayName
        )
        
        print("✅ Got conversation ID: \(conversationId)")
        print("📋 Current conversations count: \(conversations.count)")
        
        // Dismiss the search sheet
        await MainActor.run {
            print("🚪 Dismissing search sheet...")
            showNewMessage = false
        }
        
        // Small delay for sheet dismissal
        print("⏳ Waiting for sheet dismissal...")
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Check if conversation exists in list
        print("🔍 Searching for conversation in list...")
        if let conversation = conversations.first(where: { $0.id == conversationId }) {
            print("✅ Found existing conversation in list")
            print("   - Name: \(conversation.name)")
            print("   - Last Message: \(conversation.lastMessage)")
            
            await MainActor.run {
                selectedConversation = conversation
                print("✅ Set selectedConversation")
                showChatView = true
                print("✅ Set showChatView = true")
            }
        } else {
            print("⚠️ Conversation not found in list, creating temporary one")
            
            // Create temporary conversation to open immediately
            await MainActor.run {
                let tempConversation = ChatConversation(
                    id: conversationId,
                    name: user.displayName,
                    lastMessage: "",
                    timestamp: "Just now",
                    isGroup: false,
                    unreadCount: 0,
                    avatarColor: .blue
                )
                
                print("📝 Created temp conversation:")
                print("   - ID: \(tempConversation.id)")
                print("   - Name: \(tempConversation.name)")
                
                selectedConversation = tempConversation
                print("✅ Set selectedConversation to temp")
                showChatView = true
                print("✅ Set showChatView = true")
            }
        }
        
        print("=== END CONVERSATION DEBUG ===\n")
        
    } catch {
        print("❌ ERROR in startConversation:")
        print("   - Error: \(error)")
        print("   - Type: \(type(of: error))")
        print("   - Description: \(error.localizedDescription)")
        print("=== END CONVERSATION DEBUG (ERROR) ===\n")
        
        await MainActor.run {
            // Show error to user
            let alert = UIAlertController(
                title: "Error",
                message: "Failed to start conversation: \(error.localizedDescription)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            // You'll need to present this from your view controller
            print("⚠️ Should show error alert to user")
        }
    }
}
```

---

**3. Check Sheet Presentation**

Make sure the sheet modifier is present in MessagesView:

```swift
.sheet(isPresented: $showChatView) {
    if let conversation = selectedConversation {
        NavigationStack {
            ChatView(conversation: conversation)
        }
    } else {
        // This shouldn't happen, but let's log it
        Text("Error: No conversation selected")
            .onAppear {
                print("❌ showChatView is true but selectedConversation is nil!")
            }
    }
}
```

---

**4. Check State Variables**

Add debug info to MessagesView:

```swift
var body: some View {
    NavigationStack {
        // ... your UI
    }
    .onChange(of: showChatView) { oldValue, newValue in
        print("📊 showChatView changed: \(oldValue) → \(newValue)")
        print("📊 selectedConversation: \(selectedConversation?.name ?? "nil")")
    }
    .onChange(of: selectedConversation) { oldValue, newValue in
        print("📊 selectedConversation changed:")
        print("   - Old: \(oldValue?.name ?? "nil")")
        print("   - New: \(newValue?.name ?? "nil")")
    }
}
```

---

## 🔧 Quick Fixes to Try

### Fix 1: Ensure User Name is Cached

Add this to your app's login flow:

```swift
// After successful login:
Task {
    await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
    print("✅ User name cached for messaging")
}
```

---

### Fix 2: Force Refresh Conversations

If conversations aren't loading:

```swift
// In MessagesView.onAppear:
.onAppear {
    print("📱 MessagesView appeared")
    
    // Force stop and restart listener
    messagingService.stopListeningToConversations()
    messagingService.startListeningToConversations()
    
    // ... rest of your code
}
```

---

### Fix 3: Check if FirebaseMessagingService is Initialized

```swift
// In your app's main entry point or ContentView:
init() {
    print("🔥 Initializing Firebase services...")
    let _ = FirebaseMessagingService.shared
    print("✅ FirebaseMessagingService ready")
}
```

---

## 📱 Testing Checklist

### Test Sending Messages:
- [ ] User is logged in
- [ ] Conversation exists
- [ ] Network is connected
- [ ] Firestore rules allow writes
- [ ] Message text is not empty
- [ ] Check Xcode console for errors

### Test Opening New Conversations:
- [ ] User selection triggers callback
- [ ] `getOrCreateDirectConversation` succeeds
- [ ] Conversation ID is returned
- [ ] Search sheet dismisses
- [ ] `selectedConversation` is set
- [ ] `showChatView` becomes true
- [ ] ChatView sheet appears
- [ ] ChatView shows correct user name

---

## 🚨 Common Issues & Solutions

### "Permission denied" Error
**Problem:** Firestore rules are too restrictive
**Solution:** Update Firestore rules (see above)

### "User not authenticated" Error
**Problem:** User is not logged in
**Solution:** Check `Auth.auth().currentUser != nil`

### ChatView opens but is blank
**Problem:** Messages aren't loading
**Solution:** Check `loadMessages()` and Firestore rules for reads

### Send button does nothing
**Problem:** Function not being called
**Solution:** Check button's disabled state and `messageText` binding

### Conversation doesn't appear in list
**Problem:** Real-time listener not set up
**Solution:** Call `startListeningToConversations()` in onAppear

---

## 📞 Next Steps

1. **Add all the debug logs** from this guide
2. **Run the app** and try to:
   - Send a message in existing chat
   - Start a new conversation
3. **Copy ALL console output** and review it
4. **Look for** ❌ errors or ⚠️ warnings
5. **Check** which step fails:
   - Does function get called?
   - Does API call succeed?
   - Does sheet appear?

---

## 🎯 Expected Console Output for Success

### Sending Message:
```
📤 Attempting to send message:
  - Text: Hello!
  - Conversation ID: conv_abc123
  - Current User: user_xyz789
🚀 Calling messagingService.sendMessage...
✅ Message sent successfully!
```

### Starting New Conversation:
```
=== START CONVERSATION DEBUG ===
👤 User: John Doe
🆔 User ID: user_abc123
📞 Calling getOrCreateDirectConversation...
✅ Got conversation ID: conv_xyz789
📋 Current conversations count: 5
🚪 Dismissing search sheet...
⏳ Waiting for sheet dismissal...
🔍 Searching for conversation in list...
✅ Found existing conversation in list
   - Name: John Doe
   - Last Message: 
✅ Set selectedConversation
✅ Set showChatView = true
=== END CONVERSATION DEBUG ===

📊 showChatView changed: false → true
📊 selectedConversation: John Doe
```

---

## 💡 Still Not Working?

If you've tried everything above and it still doesn't work:

1. **Check Firebase Console:**
   - Go to Firestore Database
   - Look at your `conversations` collection
   - Verify conversations are being created
   - Check `messages` subcollection

2. **Check Xcode Console:**
   - Look for Firebase errors
   - Look for network errors
   - Look for auth errors

3. **Try Clean Build:**
   ```bash
   # In Xcode:
   # Product → Clean Build Folder (Shift + Cmd + K)
   # Then rebuild (Cmd + B)
   ```

4. **Verify Firebase Setup:**
   - `GoogleService-Info.plist` is in project
   - Firebase is initialized in AppDelegate or @main
   - All Firebase packages are installed

---

Let me know what you see in the console after adding these debug logs! 🚀
