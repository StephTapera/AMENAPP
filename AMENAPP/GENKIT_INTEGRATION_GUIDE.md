# Genkit Integration for Berean AI - Complete Guide

## 🎯 Overview

This integration replaces the Firebase Vertex AI implementation with **Firebase Genkit**, which provides:

- ✅ **Better structure**: Flows are organized and reusable
- ✅ **Local testing**: Test AI features before deploying
- ✅ **Observability**: Built-in traces and debugging
- ✅ **Type safety**: Full TypeScript support
- ✅ **Easy deployment**: One command to deploy to Cloud Run
- ✅ **Cost monitoring**: Track API usage and costs

## 📁 Files Created

### Swift (iOS)
- `BereanGenkitService.swift` - Service for calling Genkit flows from iOS

### TypeScript (Backend)
- `genkit/berean-flows.ts` - All AI flows for Berean
- `genkit/package.json` - Dependencies
- `genkit/tsconfig.json` - TypeScript config
- `genkit/.env.example` - Environment variables template
- `genkit/README.md` - Detailed setup guide

## 🚀 Quick Start (5 Minutes)

### 1. Install Genkit CLI
```bash
npm install -g genkit
```

### 2. Set Up Backend
```bash
cd genkit
npm install
cp .env.example .env
# Edit .env and add your GOOGLE_AI_API_KEY
```

### 3. Start Development Server
```bash
npm run dev
```

This starts:
- Genkit server at `http://localhost:3400`
- Developer UI at `http://localhost:4000`

### 4. Test in Developer UI

Open `http://localhost:4000` and test the `bibleChat` flow:

**Input:**
```json
{
  "message": "What does John 3:16 mean?",
  "history": []
}
```

**Expected Output:**
```json
{
  "response": "John 3:16 is one of the most well-known verses..."
}
```

### 5. Configure iOS App

Add to your `Info.plist`:

```xml
<key>GENKIT_ENDPOINT</key>
<string>http://localhost:3400</string>
```

### 6. Update BereanViewModel

Replace the old AI service calls with Genkit service:

```swift
@StateObject private var genkitService = BereanGenkitService.shared

// Send a message
Task {
    for try await chunk in genkitService.sendMessage(text, conversationHistory: messages) {
        response += chunk
    }
}
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        iOS App (Swift)                       │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           BereanAIAssistantView                      │  │
│  │                                                      │  │
│  │  • User types message                               │  │
│  │  • Display chat interface                           │  │
│  │  • Handle streaming responses                       │  │
│  └────────────────┬─────────────────────────────────────┘  │
│                   │                                         │
│                   ▼                                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │          BereanGenkitService                        │  │
│  │                                                      │  │
│  │  • sendMessage()                                    │  │
│  │  • generateDevotional()                             │  │
│  │  • analyzeScripture()                               │  │
│  │  • generateStudyPlan()                              │  │
│  └────────────────┬─────────────────────────────────────┘  │
└───────────────────┼──────────────────────────────────────────┘
                    │ HTTP/JSON
                    │
┌───────────────────▼──────────────────────────────────────────┐
│              Genkit Backend (TypeScript)                     │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  Genkit Flows                        │  │
│  │                                                      │  │
│  │  • bibleChat                                        │  │
│  │  • generateDevotional                               │  │
│  │  • analyzeScripture                                 │  │
│  │  • generateStudyPlan                                │  │
│  │  • generateMemoryAid                                │  │
│  │  • generateInsights                                 │  │
│  └────────────────┬─────────────────────────────────────┘  │
└───────────────────┼──────────────────────────────────────────┘
                    │
                    ▼
            ┌───────────────┐
            │   Gemini AI   │
            │ (Google AI)   │
            └───────────────┘
```

## 📊 Available Flows

### 1. Bible Chat (Main Conversational AI)

**Purpose**: General Bible Q&A with context awareness

**Swift Usage:**
```swift
let stream = genkitService.sendMessage(
    "What does John 3:16 mean?",
    conversationHistory: messages
)

for try await chunk in stream {
    response += chunk
}
```

**Genkit Flow:**
```typescript
export const bibleChat = ai.defineFlow({
  name: 'bibleChat',
  inputSchema: z.object({
    message: z.string(),
    history: z.array(...).optional()
  }),
  outputSchema: z.object({
    response: z.string()
  })
}, async ({ message, history }) => {
  // AI logic here
});
```

### 2. Generate Devotional

**Purpose**: Create personalized daily devotionals

**Swift Usage:**
```swift
let devotional = try await genkitService.generateDevotional(topic: "Faith")

print(devotional.title)
print(devotional.scripture)
print(devotional.content)
print(devotional.prayer)
```

**Output Format:**
```swift
Devotional(
  title: "Walking by Faith",
  scripture: "2 Corinthians 5:7",
  content: "Faith is not about seeing...",
  prayer: "Lord, help us trust You..."
)
```

### 3. Generate Study Plan

**Purpose**: Create multi-day Bible study plans

**Swift Usage:**
```swift
let plan = try await genkitService.generateStudyPlan(
    topic: "Prayer",
    duration: 7
)

// Use the plan in your UI
Text(plan.title)
Text(plan.description)
```

### 4. Analyze Scripture

**Purpose**: Deep analysis of Scripture passages

**Swift Usage:**
```swift
let analysis = try await genkitService.analyzeScripture(
    reference: "John 3:16",
    analysisType: .contextual
)

// Display analysis
Text(analysis)
```

**Analysis Types:**
- `.contextual` - Historical and cultural context
- `.thematic` - Theme exploration
- `.linguistic` - Greek/Hebrew word studies
- `.crossReference` - Related passages

### 5. Generate Memory Aid

**Purpose**: Help users memorize verses

**Swift Usage:**
```swift
let aid = try await genkitService.generateMemoryAid(
    verse: "For God so loved the world...",
    reference: "John 3:16"
)

Text(aid.techniques)
```

### 6. Generate Insights

**Purpose**: Get quick biblical insights

**Swift Usage:**
```swift
let insights = try await genkitService.generateInsights(topic: "Grace")

ForEach(insights) { insight in
    InsightCard(insight)
}
```

## 🔧 Configuration

### Development (Local Testing)

**Info.plist:**
```xml
<key>GENKIT_ENDPOINT</key>
<string>http://localhost:3400</string>
```

### Production (Cloud Run)

**Info.plist:**
```xml
<key>GENKIT_ENDPOINT</key>
<string>https://berean-genkit-xxxxx.run.app</string>
<key>GENKIT_API_KEY</key>
<string>your_secure_api_key</string>
```

## 🚀 Deployment

### Deploy to Cloud Run

```bash
cd genkit
npm run deploy
```

This command will:
1. Build your TypeScript flows
2. Create a Docker container
3. Deploy to Cloud Run
4. Output your production URL

### Set Environment Variables

```bash
gcloud run services update berean-genkit \
  --update-env-vars GOOGLE_AI_API_KEY=your_key \
  --update-env-vars GENKIT_API_KEY=your_api_key
```

## 🔒 Security Best Practices

### 1. Never Hardcode API Keys

❌ **Bad:**
```swift
let apiKey = "abc123..."
```

✅ **Good:**
```swift
let apiKey = Bundle.main.object(forInfoPlistKey: "GENKIT_API_KEY") as? String
```

### 2. Use Environment Variables

```bash
# In .env
GOOGLE_AI_API_KEY=your_real_key
GENKIT_API_KEY=generate_secure_random_key
```

### 3. Enable HTTPS Only

Cloud Run automatically provides HTTPS. Never use HTTP in production.

### 4. Implement Rate Limiting

Add rate limiting to your Genkit flows:

```typescript
// In genkit/berean-flows.ts
import { rateLimit } from '@genkit-ai/core';

export const bibleChat = ai.defineFlow({
  // ... config
}, async (input) => {
  // Rate limit: 10 requests per minute per user
  await rateLimit(input.userId, 10, '1m');
  
  // ... rest of flow
});
```

## 📊 Monitoring & Observability

### View Traces in Developer UI

1. Start dev server: `npm run dev`
2. Open `http://localhost:4000`
3. Click on any flow execution
4. See detailed trace with:
   - Input/output
   - Execution time
   - API costs
   - Errors (if any)

### Production Monitoring

Genkit automatically sends traces to Google Cloud Trace when deployed.

**View in Cloud Console:**
1. Go to Cloud Console
2. Select your project
3. Navigate to "Trace" → "Trace List"
4. Filter by service: `berean-genkit`

## 💰 Cost Monitoring

### Track API Usage

Genkit tracks:
- Number of tokens used
- API calls made
- Estimated costs

**View in Developer UI:**
1. Click on a flow execution
2. See "Cost" section
3. Review token usage

### Set Budget Alerts

In Google Cloud Console:
1. Go to "Billing" → "Budgets & alerts"
2. Create a new budget
3. Set alert threshold (e.g., $10/month)
4. Add your email for notifications

## 🧪 Testing

### Unit Testing Flows

```typescript
// genkit/tests/berean-flows.test.ts
import { test } from '@genkit-ai/testing';
import { bibleChat } from './berean-flows';

test('bibleChat responds to John 3:16', async () => {
  const result = await bibleChat({
    message: 'What does John 3:16 mean?',
    history: []
  });
  
  expect(result.response).toContain('God');
  expect(result.response).toContain('love');
});
```

### Integration Testing

Test from iOS app:

```swift
import XCTest

class BereanGenkitTests: XCTestCase {
    let service = BereanGenkitService.shared
    
    func testSendMessage() async throws {
        let response = try await service.sendMessageSync("What is faith?")
        XCTAssertFalse(response.isEmpty)
        XCTAssertTrue(response.contains("faith") || response.contains("Faith"))
    }
}
```

## 🐛 Common Issues & Solutions

### Issue: Connection refused (ECONNREFUSED)

**Cause**: Genkit server not running

**Solution**:
```bash
cd genkit
npm run dev
```

### Issue: Invalid API key

**Cause**: Missing or incorrect GOOGLE_AI_API_KEY

**Solution**:
1. Check `.env` file
2. Get key from https://makersuite.google.com/app/apikey
3. Restart Genkit server

### Issue: iOS app can't connect to localhost

**Cause**: iOS simulator can't reach localhost:3400

**Solution**: Use your Mac's local IP
```bash
# Find your IP
ifconfig | grep "inet " | grep -v 127.0.0.1

# Update Info.plist
<key>GENKIT_ENDPOINT</key>
<string>http://192.168.1.xxx:3400</string>
```

### Issue: Slow AI responses

**Solutions**:
1. Use `gemini15Flash` instead of `gemini20FlashExp`
2. Reduce `maxOutputTokens`
3. Implement response caching

### Issue: "Flow not found" error

**Cause**: Flow name mismatch

**Solution**: Check flow names match exactly:
```swift
// Swift
try await callGenkitFlow(flowName: "bibleChat", ...)

// TypeScript
export const bibleChat = ai.defineFlow({ name: 'bibleChat', ... })
```

## 📚 Next Steps

### 1. Add More Flows

Create custom flows for your needs:

```typescript
export const verseOfTheDay = ai.defineFlow({
  name: 'verseOfTheDay',
  outputSchema: z.object({
    verse: z.string(),
    reference: z.string(),
    reflection: z.string()
  })
}, async () => {
  // Your logic here
});
```

### 2. Implement Caching

Cache common queries to reduce costs:

```typescript
import { cache } from '@genkit-ai/core';

export const bibleChat = ai.defineFlow({
  // ... config
}, async ({ message, history }) => {
  const cacheKey = `chat:${message}`;
  
  // Check cache first
  const cached = await cache.get(cacheKey);
  if (cached) return cached;
  
  // Generate new response
  const result = await ai.generate(...);
  
  // Cache for 1 hour
  await cache.set(cacheKey, result, { ttl: 3600 });
  
  return result;
});
```

### 3. Add User Feedback

Let users rate AI responses:

```swift
struct AIResponseView: View {
    let response: String
    @State private var rating: Int?
    
    var body: some View {
        VStack {
            Text(response)
            
            HStack {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                        submitFeedback(rating: star)
                    } label: {
                        Image(systemName: rating ?? 0 >= star ? "star.fill" : "star")
                    }
                }
            }
        }
    }
}
```

### 4. Implement Voice Input

Add speech-to-text for voice queries:

```swift
import Speech

class VoiceInputManager: ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer()
    
    func startRecording() {
        // Implement speech recognition
    }
}
```

## 📖 Resources

- **Genkit Documentation**: https://firebase.google.com/docs/genkit
- **Google AI Studio**: https://makersuite.google.com
- **Cloud Run Docs**: https://cloud.google.com/run/docs
- **Gemini API**: https://ai.google.dev/docs

## 🎉 Success!

You've successfully integrated Genkit with your Berean AI Bible study feature! Your users can now:

✅ Ask questions about Scripture
✅ Generate personalized devotionals
✅ Create custom study plans
✅ Analyze Bible passages
✅ Get memory aids for verses
✅ Receive daily insights

Happy coding and God bless! 🙏
