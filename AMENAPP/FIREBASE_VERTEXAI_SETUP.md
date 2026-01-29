# Firebase VertexAI Setup Guide - AI Bible Study

## ❌ Current Status: NOT Hooked Up Yet

Firebase VertexAI (Gemini) is **not yet integrated** but I've created everything you need!

## ✅ What I've Created for You

1. **`BibleAIService.swift`** - Complete AI service with:
   - Chat functionality (streaming & non-streaming)
   - Devotional generation
   - Study plan creation
   - Scripture analysis
   - Memory verse helpers
   - AI insights
   - Configured with biblical system instructions

2. **Updated `AMENAPPApp.swift`** - Added `import FirebaseVertexAI`

## 🚀 Quick Setup (3 Steps)

### Step 1: Add Firebase VertexAI Package (5 minutes)

In Xcode:
1. **File > Add Package Dependencies**
2. Paste: `https://github.com/firebase/firebase-ios-sdk`
3. Select latest version (11.0+)
4. Add package: **`FirebaseVertexAI`**

### Step 2: Enable in Firebase Console (2 minutes)

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. **Build > Vertex AI in Firebase**
4. Click **Get Started** → **Activate**

**Free Tier:**
- ✅ 1,500 requests/day FREE
- ✅ Gemini 2.0 Flash model
- ✅ Perfect for development

### Step 3: Connect to AIBibleStudyView (10 minutes)

Add this to the top of `AIBibleStudyView.swift`:

```swift
@StateObject private var aiService = BibleAIService.shared
```

Replace `sendMessage()` function:

```swift
private func sendMessage() {
    guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    
    // Add user message
    let message = AIStudyMessage(text: userInput, isUser: true)
    messages.append(message)
    let questionText = userInput
    userInput = ""
    
    isProcessing = true
    
    // Get AI response (REAL Gemini AI!)
    Task {
        do {
            var fullResponse = ""
            
            // Stream the response
            for try await chunk in aiService.sendMessage(questionText) {
                fullResponse += chunk
                
                // Update last message with streaming text
                if let lastIndex = messages.lastIndex(where: { !$0.isUser }) {
                    messages[lastIndex] = AIStudyMessage(
                        text: fullResponse,
                        isUser: false
                    )
                } else {
                    messages.append(AIStudyMessage(
                        text: fullResponse,
                        isUser: false
                    ))
                }
            }
            
            isProcessing = false
        } catch {
            print("❌ AI Error: \(error)")
            messages.append(AIStudyMessage(
                text: "I'm having trouble connecting right now. Please try again.",
                isUser: false
            ))
            isProcessing = false
        }
    }
}
```

## 🎨 What You Get

### Chat Features
- ✨ **Real Gemini AI** responses
- 📖 Biblical knowledge & context
- 🔍 Scripture understanding
- 💬 Natural conversation
- 📚 Theological accuracy

### Pro Features (when enabled)
- 📖 **Daily Devotionals** - AI-generated, personalized
- 📚 **Study Plans** - Custom Bible study roadmaps  
- 🔬 **Scripture Analysis** - Deep contextual insights
- 🧠 **Memory Aids** - Verse memorization helpers
- 💡 **Insights** - Daily biblical wisdom

## 📝 Example Usage

### In Chat:
```swift
// User asks: "What does John 3:16 mean?"
// AI responds with contextual explanation + related verses
```

### Generate Devotional:
```swift
Task {
    let devotional = try await aiService.generateDevotional(topic: "Faith")
    // Returns formatted devotional with Scripture, reflection, prayer
}
```

### Create Study Plan:
```swift
Task {
    let plan = try await aiService.generateStudyPlan(
        topic: "Gospel of John",
        duration: 30
    )
    // Returns 30-day study plan with daily readings
}
```

## 🔒 Security Notes

1. **API Key Security**: Firebase VertexAI uses your Firebase project credentials (no separate API key needed!)
2. **Safety Settings**: Already configured to block harmful content
3. **Cost Control**: Free tier has daily limits to prevent unexpected charges
4. **System Instructions**: AI is pre-configured for biblical responses

## 🧪 Testing

After setup:

1. **Build** your app (Cmd+B)
2. **Run** on simulator or device
3. Go to **AI Bible Study** (from Resources)
4. Ask: "What is the meaning of faith?"
5. Watch **real Gemini AI** respond! 🎉

## ⚠️ Common Issues

### "Module 'FirebaseVertexAI' not found"
**Fix:** Add FirebaseVertexAI package (Step 1)

### "Vertex AI not enabled"
**Fix:** Enable in Firebase Console (Step 2)

### "Invalid API key"
**Fix:** Make sure `GoogleService-Info.plist` is in your project

### "Rate limit exceeded"
**Fix:** Wait for daily limit to reset or upgrade to paid tier

## 💰 Pricing (Optional Upgrade)

**Free Tier:**
- 1,500 requests/day
- Perfect for development & testing

**Paid Tier (Pay As You Go):**
- Input: $0.075 per 1M tokens (~750,000 words)
- Output: $0.30 per 1M tokens (~750,000 words)
- Example: 10,000 chats/month ≈ $5-10

## 📚 Resources

- [Firebase VertexAI Docs](https://firebase.google.com/docs/vertex-ai)
- [Gemini AI Docs](https://ai.google.dev/gemini-api/docs)
- [Pricing Calculator](https://cloud.google.com/vertex-ai/pricing)

## ✨ Next Steps

After integration works:

1. **Customize System Instructions** in `BibleAIService.swift`
2. **Add More Features**:
   - Greek/Hebrew word studies
   - Cross-reference finding
   - Sermon notes generation
   - Prayer request insights
3. **Implement Pro Features** for paid users
4. **Add Caching** to reduce API calls
5. **Track Usage** for analytics

## 🎉 You're Ready!

Once you complete Steps 1-3, your AI Bible Study will use **real Gemini AI** powered by Google's most advanced language model, trained on biblical knowledge and ready to help your users grow in faith!

---

**Questions?** The `BibleAIService.swift` file has extensive comments and examples.

**Need Help?** Check the Firebase VertexAI documentation or reach out to Firebase support.
