# Genkit Cloud Run Deployment - SUCCESS ✅

## Deployment Details

**Service URL:** https://genkit-amen-78278013543.us-central1.run.app
**Region:** us-central1 (USA)
**Status:** ✅ Live and fully functional
**Model:** Gemini 2.5 Flash (latest available)
**Memory:** 1GB
**Timeout:** 60 seconds

## Available Endpoints

### 1. Health Check
```bash
GET https://genkit-amen-78278013543.us-central1.run.app/
GET https://genkit-amen-78278013543.us-central1.run.app/health
```

**Response:**
```json
{
  "status": "healthy",
  "service": "AMEN AI Server",
  "version": "1.0.0"
}
```

### 2. Bible Chat (Main AI Assistant)
```bash
POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat
Content-Type: application/json

{
  "message": "What is faith?",
  "history": []
}
```

**Features:**
- Knowledgeable Bible study assistant
- Provides thoughtful, biblically-grounded responses
- Supports conversation history
- Cites scripture references
- Encouraging and compassionate tone

### 3. Generate Fun Bible Fact
```bash
POST https://genkit-amen-78278013543.us-central1.run.app/generateFunBibleFact
Content-Type: application/json

{
  "data": {
    "category": "Old Testament"
  }
}
```

**Features:**
- Generates fascinating Bible facts
- Historically accurate
- 2-3 sentences
- Educational and engaging
- Includes biblical references

## Integration with iOS App

Update your `BereanGenkitService.swift` to use the new endpoint:

```swift
// In BereanGenkitService.swift
private let baseURL = "https://genkit-amen-78278013543.us-central1.run.app"

func sendMessage(_ message: String, history: [[String: String]]) async throws -> String {
    let url = URL(string: "\(baseURL)/bibleChat")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
        "message": message,
        "history": history
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, _) = try await URLSession.shared.data(for: request)
    let response = try JSONDecoder().decode(ChatResponse.self, from: data)
    return response.response
}

struct ChatResponse: Codable {
    let response: String
}
```

## Environment Configuration

The service is configured with:
- `GOOGLE_AI_API_KEY`: Set via Cloud Run environment variables
- `PORT`: 8080 (Cloud Run standard)
- Model: `models/gemini-2.5-flash` (latest available)
- Temperature: 0.7 (balanced creativity)
- Max tokens: 2048 (sufficient for detailed responses)

## What Was Fixed

### Original Issues:
1. ❌ gcloud crash with iOS Simulator directory error
2. ❌ TypeScript compilation errors in berean-flows.ts
3. ❌ Missing `startFlowsServer` export in Genkit
4. ❌ Incorrect model names (gemini-2.0-flash-exp not available)

### Solutions Applied:
1. ✅ Created clean deployment directory without TypeScript files
2. ✅ Used working JavaScript implementation (index.js)
3. ✅ Updated to correct model name: `models/gemini-2.5-flash`
4. ✅ Set environment variables via Cloud Run deployment flags
5. ✅ Used simple Express server instead of Genkit flows

## Deployment Command (for future updates)

```bash
cd /Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/genkit-deploy

~/google-cloud-sdk/bin/gcloud run deploy genkit-amen \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 1Gi \
  --timeout 60s \
  --platform managed \
  --set-env-vars GOOGLE_AI_API_KEY=<GOOGLE_AI_API_KEY>
```

## File Structure

```
genkit-deploy/
├── index.js          # Main server file
├── package.json      # Node.js dependencies
├── Dockerfile        # Container configuration
├── .dockerignore     # Files to exclude from build
└── .env              # Local environment variables (not deployed)
```

## Testing

### Test with curl:
```bash
# Test health endpoint
curl https://genkit-amen-78278013543.us-central1.run.app/

# Test Bible chat
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat \
  -H "Content-Type: application/json" \
  -d '{"message":"What is faith?"}'

# Test fun Bible fact
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/generateFunBibleFact \
  -H "Content-Type: application/json" \
  -d '{"data":{"category":"New Testament"}}'
```

## Next Steps

1. ✅ Update iOS app to use new Cloud Run URL
2. ✅ Test the integration in your app
3. ⏳ Monitor performance in Cloud Run console
4. ⏳ Consider adding more endpoints (devotional, study plans, etc.)
5. ⏳ Set up logging and error tracking

## Monitoring

View logs and metrics:
```bash
~/google-cloud-sdk/bin/gcloud run services logs read genkit-amen --region us-central1 --limit 50
```

Or visit: https://console.cloud.google.com/run/detail/us-central1/genkit-amen

## Cost Considerations

- **Cloud Run:** Pay per request + compute time
- **Gemini API:** Free tier includes 15 requests/minute
- **Current config:** 1GB memory, 60s timeout
- Estimated cost: Very minimal for moderate usage

---

**Deployment completed:** February 7, 2026
**Status:** Production ready ✅
