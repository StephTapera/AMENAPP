# Berean AI - Genkit Integration Setup Guide

## ✅ What's Been Integrated

Your Berean AI Assistant now uses **Firebase Genkit** for real AI responses! Here's what was added:

### New Files
- ✅ `BereanGenkitService.swift` - Service for calling Genkit AI flows
- ✅ Updated `BereanAIAssistantView.swift` - Now uses Genkit with streaming responses

### Features Added
- ✅ **Real AI Chat** with streaming word-by-word responses
- ✅ **Automatic verse reference extraction** from AI responses
- ✅ **Fallback to mock responses** if Genkit is unavailable
- ✅ **Error handling** with user feedback
- ✅ **Conversation history context** (last 10 messages sent to AI)

---

## 🚀 Quick Start (3 Steps)

### Step 1: Start Your Genkit Server

Open Terminal and run:

```bash
cd genkit
npm install
npm run dev
```

You should see:
```
✓ Genkit developer UI running at http://localhost:4000
✓ Genkit server running at http://localhost:3400
```

### Step 2: Add Your Google AI API Key

Create a `.env` file in the `genkit` folder:

```bash
cd genkit
cp .env.example .env
```

Edit `.env` and add your API key:
```
GOOGLE_AI_API_KEY=your_api_key_here
```

**Get a free API key:** https://aistudio.google.com/app/apikey

### Step 3: Run Your iOS App

Build and run in Xcode. That's it! Your Berean AI is now powered by Gemini 2.0 Flash.

---

## 🧪 Testing

### Test 1: Check Genkit Server
Open http://localhost:4000 in your browser to see the Genkit Developer UI.

### Test 2: Test a Flow
In the Developer UI, select `bibleChat` and run:

**Input:**
```json
{
  "message": "What does John 3:16 mean?",
  "history": []
}
```

You should get a detailed biblical explanation.

### Test 3: Test in iOS App
1. Launch the app
2. Open Berean AI Assistant
3. Ask: "What does John 3:16 mean?"
4. Watch the AI response stream in word-by-word!

---

## 📱 How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    iOS App (Swift)                           │
│                                                              │
│  User types: "What does John 3:16 mean?"                    │
│           ↓                                                  │
│  BereanViewModel.generateResponseStreaming()                │
│           ↓                                                  │
│  BereanGenkitService.sendMessage()                          │
│           ↓                                                  │
└─────────────────────────────────────────────────────────────┘
                        ↓ HTTP POST
┌─────────────────────────────────────────────────────────────┐
│             Genkit Server (TypeScript)                       │
│                                                              │
│  Receives: { message, history }                             │
│           ↓                                                  │
│  bibleChat flow executes                                    │
│           ↓                                                  │
│  Calls Gemini 2.0 Flash API                                 │
│           ↓                                                  │
│  Returns: { response: "John 3:16 is..." }                   │
└─────────────────────────────────────────────────────────────┘
                        ↓ HTTP Response
┌─────────────────────────────────────────────────────────────┐
│                    iOS App (Swift)                           │
│                                                              │
│  BereanGenkitService receives response                      │
│           ↓                                                  │
│  Streams words to UI with typing effect                     │
│           ↓                                                  │
│  Extracts verse references automatically                    │
│           ↓                                                  │
│  Displays with chips: [John 3:16] [John 3:17]              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎨 User Experience Improvements

### Before (Mock Responses)
- ❌ Limited to hardcoded responses
- ❌ No context awareness
- ❌ Fixed delay, no streaming
- ❌ Only 12 topics covered

### After (Genkit AI)
- ✅ **Unlimited knowledge** - Can answer any Bible question
- ✅ **Context-aware** - Remembers last 10 messages
- ✅ **Streaming responses** - Words appear naturally
- ✅ **Auto verse detection** - Extracts references automatically
- ✅ **Graceful fallback** - Mock responses if server is down

---

## 🔧 Advanced Configuration

### Change Genkit Endpoint (Production)

When you deploy Genkit to Cloud Run, update the endpoint:

```swift
// In BereanGenkitService.swift
#if DEBUG
self.endpoint = "http://localhost:3400"
#else
self.endpoint = "https://your-cloud-run-url.run.app"
#endif
```

### Adjust AI Temperature

Higher = more creative, Lower = more factual

```typescript
// In genkit/berean-flows.ts
config: {
  temperature: 0.7,  // Change to 0.5 for more factual, 0.9 for more creative
  maxOutputTokens: 2048,
}
```

### Change AI Model

Want a different Gemini model?

```typescript
// In genkit/berean-flows.ts
import { gemini20FlashExp, gemini15Pro } from '@genkit-ai/googleai';

// Then use:
model: gemini15Pro, // More capable but slower
```

---

## 🐛 Troubleshooting

### Error: "Connection refused"
**Problem:** Genkit server isn't running  
**Solution:** Run `npm run dev` in the genkit folder

### Error: "Invalid API key"
**Problem:** Missing or wrong Google AI API key  
**Solution:** Check your `.env` file has `GOOGLE_AI_API_KEY=...`

### Responses are slow
**Problem:** Free tier rate limiting  
**Solution:** 
1. Check quotas at https://aistudio.google.com/
2. Consider upgrading to paid tier
3. Reduce conversation history: `suffix(5)` instead of `suffix(10)`

### Mock responses appearing
**Problem:** Genkit server unreachable  
**Solution:** Check server logs in Terminal where you ran `npm run dev`

---

## 📊 Available Genkit Flows

Your app can now use these AI flows:

| Flow | Description | Example Use |
|------|-------------|-------------|
| `bibleChat` | Main conversational AI | Ask any Bible question |
| `generateDevotional` | Daily devotionals | Create custom devotionals |
| `generateStudyPlan` | Multi-day study plans | "7-day study on faith" |
| `analyzeScripture` | Deep verse analysis | Context, themes, linguistics |
| `generateMemoryAid` | Memory techniques | Help memorize verses |
| `generateInsights` | Quick insights | Daily biblical insights |

---

## 🚢 Deployment (Optional)

When ready for production:

### 1. Deploy Genkit to Cloud Run
```bash
cd genkit
genkit deploy
```

### 2. Update iOS endpoint
```swift
#else
self.endpoint = "https://your-cloud-run-url.run.app"
#endif
```

### 3. Add URL to Info.plist
```xml
<key>GENKIT_ENDPOINT</key>
<string>https://your-cloud-run-url.run.app</string>
```

---

## 💡 Tips

1. **Test in Developer UI first** - Debug flows before testing in iOS
2. **Monitor costs** - Check API usage at https://aistudio.google.com/
3. **Keep history short** - Only send last 10 messages to save tokens
4. **Use caching** - Store common responses locally
5. **Handle errors gracefully** - Always have fallback responses

---

## 📚 Next Steps

- ✅ Berean AI is working!
- ⏭️ Test all the quick action buttons
- ⏭️ Try the smart features panel
- ⏭️ Explore verse analysis
- ⏭️ Generate custom devotionals
- ⏭️ Deploy to production

**Need help?** Check the logs in Terminal or Xcode console for detailed error messages.

---

🎉 **Congratulations!** Your Berean AI Assistant is now powered by real AI!
