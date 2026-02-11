# Genkit Service - Quick Reference Card

## 🔗 Service URL
```
https://genkit-amen-78278013543.us-central1.run.app
```

## 📡 Endpoints

### Health Check
```bash
GET /
GET /health
```

### Bible Chat
```bash
POST /bibleChat
Content-Type: application/json

{
  "message": "Your question here",
  "history": []  // Optional conversation history
}

Response: { "response": "AI answer..." }
```

### Fun Bible Fact
```bash
POST /generateFunBibleFact
Content-Type: application/json

{
  "data": {
    "category": "Old Testament"  // or "New Testament", "Prophets", etc.
  }
}

Response: { "result": { "fact": "Interesting fact..." } }
```

## 📱 Swift Integration (Copy & Paste)

```swift
// 1. Update base URL
private let baseURL = "https://genkit-amen-78278013543.us-central1.run.app"

// 2. Send Bible chat message
func sendMessage(_ message: String, history: [[String: String]] = []) async throws -> String {
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

## 🧪 Quick Test

```bash
# Test in Terminal
curl https://genkit-amen-78278013543.us-central1.run.app/

# Test Bible Chat
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat \
  -H "Content-Type: application/json" \
  -d '{"message":"What is faith?"}'
```

## 🚀 Deployment Command

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

## 📊 Monitoring

```bash
# View logs
~/google-cloud-sdk/bin/gcloud run services logs read genkit-amen \
  --region us-central1 --limit 50

# Or visit:
# https://console.cloud.google.com/run/detail/us-central1/genkit-amen
```

## ⚙️ Configuration

- **Model:** Gemini 2.5 Flash
- **Memory:** 1GB
- **Timeout:** 60 seconds
- **Region:** us-central1
- **Authentication:** Public (no auth required)

## 📝 Files

- **Source:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/genkit-deploy/`
- **Main file:** `index.js`
- **Dependencies:** `package.json`
- **Container:** `Dockerfile`

## ✅ Status
- [x] Deployed successfully
- [x] Health check passing
- [x] Bible chat working
- [x] Fun facts working
- [x] Swift integration ready
- [x] Production ready

## 📚 Documentation

See complete guides:
- `GENKIT_DEPLOYMENT_SUCCESS.md` - Full deployment details
- `SWIFT_INTEGRATION_UPDATE.md` - iOS integration guide

---
**Last Updated:** February 7, 2026 | **Status:** ✅ LIVE
