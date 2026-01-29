# Berean AI - Quick Reference

## 🎯 What Just Happened?

Your Berean AI Assistant is now connected to **real AI** via Firebase Genkit!

## ✅ Files Created/Modified

### New Files
1. **BereanGenkitService.swift** - Connects iOS to Genkit server
2. **BEREAN_GENKIT_SETUP.md** - Detailed setup guide
3. **BEREAN_QUICKSTART.md** - This file!

### Modified Files
1. **BereanAIAssistantView.swift** 
   - Now uses streaming AI responses
   - Auto-detects verse references
   - Graceful fallback to mock responses

## 🚀 Start Using It (30 seconds)

### Terminal 1: Start Genkit
```bash
cd genkit
npm install
npm run dev
```

### Terminal 2: Check it's working
```bash
curl http://localhost:3400
```

If you see JSON, you're good! ✅

### Xcode: Build and Run
Your Berean AI now has real intelligence!

## 🧪 Test It

Ask these questions to see real AI in action:

1. **"What does John 3:16 mean?"**
   - Watch it stream word-by-word
   - See verse references appear automatically

2. **"Tell me about the parable of the prodigal son"**
   - Get detailed biblical context
   - Theological insights

3. **"What's the Greek meaning of agape?"**
   - Original language analysis
   - Word studies

## 🎨 New Features

### Streaming Responses
AI responses now appear word-by-word like ChatGPT!

### Automatic Verse Detection
If AI mentions "John 3:16", it automatically becomes a tappable chip:
```
[John 3:16] [Romans 8:28]
```

### Context-Aware
Berean remembers your last 10 messages for natural conversations.

### Graceful Fallback
If Genkit server is down, you still get mock responses (no crashes!)

## 📱 User Flow

```
1. User opens Berean AI
   ↓
2. User types: "What does Romans 8:28 mean?"
   ↓
3. Message appears in chat (YOU)
   ↓
4. Thinking indicator shows (3 animated dots)
   ↓
5. AI response streams in word-by-word (BEREAN)
   ↓
6. Verse references appear as chips: [Romans 8:28]
   ↓
7. User can react (💡 Helpful, 🙏 Amen) or share to feed
```

## 🔧 Quick Fixes

### Problem: No response
**Check:** Is Genkit running? `npm run dev` in genkit folder

### Problem: Mock responses instead of AI
**Check:** Look at Xcode console for error messages
**Solution:** Make sure `.env` has your `GOOGLE_AI_API_KEY`

### Problem: Slow responses
**Check:** Free tier has rate limits
**Solution:** Upgrade at https://aistudio.google.com/ or be patient

## 🎯 Key Code Changes

### BereanViewModel.swift (now in BereanAIAssistantView.swift)

**Before:**
```swift
func generateResponse(for query: String) -> BereanMessage {
    // Hardcoded mock responses only
    return BereanMessage(content: "Mock response", ...)
}
```

**After:**
```swift
func generateResponseStreaming(
    for query: String, 
    onChunk: @escaping (String) -> Void,
    onComplete: @escaping (BereanMessage) -> Void,
    onError: @escaping (Error) -> Void
) {
    // Real AI with streaming + fallback
}
```

### sendMessage() function

**Before:**
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    let response = viewModel.generateResponse(for: text)
    viewModel.messages.append(response)
}
```

**After:**
```swift
viewModel.generateResponseStreaming(
    for: text,
    onChunk: { chunk in
        // Update message as words arrive
    },
    onComplete: { finalMessage in
        // Show complete message
    },
    onError: { error in
        // Handle gracefully
    }
)
```

## 📊 API Usage

Each message to AI costs approximately:
- Input: ~100-500 tokens (conversation history)
- Output: ~500-2000 tokens (AI response)
- **Cost:** ~$0.001-0.005 per conversation (very cheap!)

Free tier includes:
- ✅ 15 requests per minute
- ✅ 1,500 requests per day
- ✅ 1 million tokens per month

## 🎨 UI Improvements

### Streaming Effect
Words appear naturally instead of all at once:
```
"John 3:16 is one of the most..."
         ↓ 30ms delay
"John 3:16 is one of the most profound..."
         ↓ 30ms delay
"John 3:16 is one of the most profound verses..."
```

### Verse References
AI response:
> "As it says in John 3:16 and Romans 8:28, God's love..."

Displays as:
```
As it says in [John 3:16] and [Romans 8:28], God's love...
       (tappable chips appear automatically)
```

## 🔮 Future Enhancements

Want to add more? You already have these Genkit flows ready:

1. **generateDevotional** - Custom daily devotionals
2. **generateStudyPlan** - Multi-day Bible study plans
3. **analyzeScripture** - Deep verse analysis (context, themes, linguistics)
4. **generateMemoryAid** - Help users memorize verses
5. **generateInsights** - Quick biblical insights

Just call them from your UI:
```swift
let devotional = try await genkitService.generateDevotional(topic: "faith")
let plan = try await genkitService.generateStudyPlan(topic: "Prayer", duration: 7)
```

## 📚 Learn More

- **Full Setup Guide:** See `BEREAN_GENKIT_SETUP.md`
- **Genkit Docs:** https://firebase.google.com/docs/genkit
- **Your Flows:** Check `genkit/berean-flows.ts`
- **Test UI:** http://localhost:4000 (when server running)

## 🎉 You're Done!

Your Berean AI is now powered by Google's Gemini 2.0 Flash model. Enjoy having an intelligent Bible study companion!

**Pro Tip:** Open the Genkit Developer UI (http://localhost:4000) to see real-time traces and debug AI responses.

---

Made with ❤️ for AMEN App
