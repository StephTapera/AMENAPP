# 🔔 AI-Powered Notifications Implementation Guide

## ✅ What I Created

### 1. **NotificationGenkitService.swift** - Main Service
Complete AI notification service with:
- Smart notification text generation
- Notification summarization (batch)
- Timing optimization
- Full integration with your existing `PushNotificationManager`

### 2. **NotificationExamples.swift** - Usage Examples & Test UI
Ready-to-use examples for:
- New message notifications
- Match notifications
- Prayer request notifications
- Event reminders
- Batch summaries
- **Test View** to try everything!

### 3. **BACKEND_GENKIT_NOTIFICATIONS.ts** - Backend Flows
Complete Genkit flows for:
- Notification text generation
- Notification summarization
- Timing optimization
- Cloud Functions for delivery

---

## 🚀 Quick Start - Test It Now!

### Step 1: Add Test View to Your App

Add this anywhere in your app (like ContentView):

```swift
NavigationLink("Test AI Notifications") {
    NotificationTestView()
}
```

Or show it directly:
```swift
NotificationTestView()
```

### Step 2: Try the Examples!

The test view includes 5 pre-built notification types:
1. **New Message** - AI personalizes based on message content
2. **New Match** - Highlights shared interests
3. **Prayer Request** - Marks urgent requests as high priority
4. **Event Reminder** - Optimizes timing
5. **Daily Summary** - Combines multiple notifications

**Just tap any button to see it work!**

---

## 📱 How to Use in Your Real App

### Example 1: Send Message Notification

```swift
import FirebaseAuth

// When someone sends a message
func handleNewMessage(from sender: User, to recipient: User, messageText: String) {
    Task {
        let senderProfile = UserProfile(
            id: sender.id,
            name: sender.name,
            interests: sender.interests ?? [],
            denomination: sender.denomination,
            location: sender.location
        )
        
        try await NotificationGenkitService.shared.sendSmartNotification(
            eventType: .message,
            senderName: sender.name,
            senderProfile: senderProfile,
            recipientId: recipient.id,
            context: messageText,
            customData: [
                "senderId": sender.id,
                "conversationId": "\(sender.id)_\(recipient.id)"
            ]
        )
        
        print("✅ AI notification sent!")
    }
}
```

### Example 2: Send Match Notification

```swift
// When users match
func handleNewMatch(user1: User, user2: User) {
    Task {
        // Find shared interests
        let sharedInterests = Set(user1.interests ?? [])
            .intersection(Set(user2.interests ?? []))
        
        let context = sharedInterests.isEmpty
            ? "You have a new match!"
            : "You both love: \(sharedInterests.joined(separator: ", "))"
        
        try await NotificationGenkitService.shared.sendSmartNotification(
            eventType: .match,
            senderName: user2.name,
            senderProfile: UserProfile(
                id: user2.id,
                name: user2.name,
                interests: user2.interests ?? [],
                denomination: user2.denomination,
                location: user2.location
            ),
            recipientId: user1.id,
            context: context,
            metadata: ["sharedInterests": Array(sharedInterests)],
            customData: ["matchId": user2.id]
        )
    }
}
```

### Example 3: Prayer Request (High Priority)

```swift
// Urgent prayer request
func sendPrayerRequest(from requester: User, to prayerCircle: [User], message: String) {
    Task {
        for member in prayerCircle {
            try await NotificationGenkitService.shared.sendSmartNotification(
                eventType: .prayerRequest,
                senderName: requester.name,
                senderProfile: UserProfile(
                    id: requester.id,
                    name: requester.name,
                    interests: requester.interests ?? [],
                    denomination: requester.denomination,
                    location: requester.location
                ),
                recipientId: member.id,
                context: "URGENT: \(message)",
                metadata: ["urgent": true],
                customData: [
                    "requesterId": requester.id,
                    "priority": "high"
                ]
            )
        }
    }
}
```

### Example 4: Daily Summary (Batch)

```swift
// Send daily summary if user has 3+ pending notifications
func sendDailySummary(for userId: String) {
    Task {
        // Fetch pending notifications from Firestore
        let pending = try await fetchPendingNotifications(userId: userId)
        
        if pending.count >= 3 {
            try await NotificationGenkitService.shared.sendBatchNotificationSummary(
                userId: userId,
                pendingNotifications: pending
            )
        }
    }
}
```

---

## 🎯 What Makes These Notifications "AI-Powered"?

### Before AI (Generic):
```
"John sent you a message"
"You have a new match"
"Someone liked your post"
```

### After AI (Personalized):
```
"John wants to discuss your favorite Bible verse! 📖"
"Sarah shares your love for worship music and serves at her local church! ❤️"
"David and 3 others loved your post about prayer - 2 left thoughtful comments 💬"
```

### Key AI Features:

1. **Personalization**
   - Uses recipient's interests
   - Highlights shared connections
   - Contextual language

2. **Smart Timing**
   - Won't send at 3 AM
   - Waits for user's active hours
   - Batches low-priority notifications

3. **Priority Detection**
   - HIGH: Prayer emergencies, event starting now
   - MEDIUM: Messages, matches, likes
   - LOW: Daily verse, recommendations

4. **Intelligent Batching**
   - Combines 3+ notifications
   - Creates engaging summaries
   - Reduces notification fatigue

---

## 🔧 Setup Requirements

### iOS Side (Already Done ✅)

All files are created and ready to use:
- `NotificationGenkitService.swift` - Main service
- `NotificationExamples.swift` - Examples & test UI
- Integrates with your existing `PushNotificationManager.swift`

### Backend Side (Need to Set Up)

#### Option 1: Use Mock/Fallback (Quick Testing)

The service will work with fallback notifications if backend isn't ready:

```swift
// In NotificationGenkitService.swift, modify init():
init() {
    self.genkitEndpoint = "http://localhost:3400" // Mock endpoint
    // Service will use fallback templates if Genkit unavailable
}
```

#### Option 2: Deploy Real Genkit Backend

1. **Copy Backend Code**
   - File: `BACKEND_GENKIT_NOTIFICATIONS.ts`
   - Location: Your Firebase project at `functions/src/notificationFlows.ts`

2. **Install Dependencies**
   ```bash
   cd functions
   npm install genkit @genkit-ai/firebase @genkit-ai/google-ai
   npm install firebase-admin firebase-functions
   ```

3. **Set Environment Variables**
   ```bash
   firebase functions:config:set genkit.api_key="YOUR_GOOGLE_AI_API_KEY"
   ```

4. **Deploy**
   ```bash
   firebase deploy --only functions
   ```

5. **Update iOS App**
   ```swift
   // In Info.plist, add:
   <key>GENKIT_ENDPOINT</key>
   <string>https://YOUR-PROJECT.cloudfunctions.net</string>
   ```

---

## 📊 Notification Types Supported

| Type | Priority | AI Enhancement | Example |
|------|----------|----------------|---------|
| **Message** | Medium | Personalizes based on content & interests | "Sarah wants to pray with you about your mission trip! 🙏" |
| **Match** | Medium | Highlights shared interests | "David loves worship music just like you! ❤️" |
| **Prayer Request** | High | Marks urgency, sends immediately | "⚡ URGENT: John needs prayer for his father's surgery" |
| **Prayer Answer** | High | Celebrates with community | "🎉 Your prayer for Sarah was answered!" |
| **Event Reminder** | High | Context-aware timing | "Bible study starts in 30 min - 8 friends are coming!" |
| **Like** | Low | Groups together | "Sarah and 4 others loved your post about faith 💙" |
| **Comment** | Medium | Highlights thoughtful responses | "David left a meaningful comment on your prayer post" |
| **Group Invite** | Medium | Emphasizes shared interests | "Join 'Prayer Warriors' - 12 believers near you!" |

---

## 🎨 Customization

### Adjust AI Tone

In backend (`notificationFlows.ts`), modify the prompt:

```typescript
const prompt = `You are a notification writer for a Christian dating app.

Tone: ${customTone} // warm, professional, casual, encouraging
Target Age: ${targetAge} // young adults, all ages
Language Style: ${style} // modern, traditional, mixed

...
`;
```

### Change Priority Rules

In `NotificationGenkitService.swift`:

```swift
func optimizeTiming(...) async throws -> TimingRecommendation {
    // Customize priority logic
    if priority == .high || notificationType == .prayerRequest {
        return TimingRecommendation(
            sendImmediately: true,
            delayMinutes: 0,
            reasoning: "Custom high priority logic"
        )
    }
    
    // Your custom timing rules...
}
```

### Add New Notification Types

1. Add to enum:
```swift
enum NotificationEventType: String {
    case customType = "custom_type"
}
```

2. Add example:
```swift
func sendCustomNotification() async {
    try await NotificationGenkitService.shared.sendSmartNotification(
        eventType: .customType,
        senderName: "System",
        senderProfile: nil,
        recipientId: userId,
        context: "Your custom message"
    )
}
```

---

## 📈 Benefits Summary

### User Experience
- ✅ **More relevant** notifications (personalized)
- ✅ **Less annoying** (smart timing & batching)
- ✅ **Higher engagement** (better open rates)
- ✅ **Context-aware** (knows what matters)

### Technical
- ✅ **Scalable** (Genkit handles AI calls)
- ✅ **Observable** (Genkit provides monitoring)
- ✅ **Testable** (Built-in test UI)
- ✅ **Maintainable** (Clean service architecture)

### Business
- ✅ **Differentiation** (unique AI features)
- ✅ **Retention** (better notifications = more engagement)
- ✅ **Conversion** (smart timing increases actions)
- ✅ **Satisfaction** (users appreciate relevance)

---

## 🐛 Troubleshooting

### "No FCM token" error
**Solution:** Make sure user has granted notification permissions:
```swift
await PushNotificationManager.shared.requestNotificationPermissions()
```

### Notifications not appearing
**Check:**
1. ✅ Notification permissions granted
2. ✅ FCM token saved to Firestore
3. ✅ Cloud Functions deployed
4. ✅ Check console logs for errors

### AI not working (using fallbacks)
**This is OK for testing!** Fallback notifications still work great.

**To enable AI:**
1. Deploy backend Genkit flows
2. Set GENKIT_ENDPOINT in Info.plist
3. Verify Google AI API key is set

---

## 🎯 Next Steps

### Phase 1: Testing (Now)
1. ✅ Run `NotificationTestView()` in your app
2. ✅ Try each notification type
3. ✅ Check console logs for details
4. ✅ Verify notifications appear

### Phase 2: Integration (This Week)
1. ✅ Replace generic notifications with AI ones
2. ✅ Add to message sending flow
3. ✅ Add to match creation flow
4. ✅ Add to prayer request flow

### Phase 3: Backend (Next Week)
1. ✅ Deploy Genkit flows to Firebase
2. ✅ Set up environment variables
3. ✅ Monitor Cloud Function logs
4. ✅ Optimize prompts based on results

### Phase 4: Analytics (Ongoing)
1. ✅ Track notification open rates
2. ✅ A/B test different AI prompts
3. ✅ Monitor user feedback
4. ✅ Iterate and improve

---

## 💡 Pro Tips

1. **Start with fallbacks** - Test UI now, add AI backend later
2. **Batch low-priority** - Don't spam users with every like
3. **Respect quiet hours** - Never send between 11 PM - 7 AM
4. **A/B test prompts** - Find what resonates with your users
5. **Monitor costs** - Genkit AI calls cost money (but cheap!)
6. **Use caching** - Cache AI responses for similar notifications

---

## 📞 Support

If you need help:
1. Check console logs (lots of debugging info)
2. Use test view to verify setup
3. Start with fallbacks, add AI gradually
4. Review backend deployment steps

---

## 🎉 You're Ready!

**Everything is implemented and ready to test!**

Just run:
```swift
NotificationTestView()
```

And start tapping buttons to see AI-powered notifications in action! 🚀
