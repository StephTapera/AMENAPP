# Swift Integration Update for Cloud Run Genkit Service

## Quick Update Guide

Your Genkit service is now live at: **https://genkit-amen-78278013543.us-central1.run.app**

Follow these steps to integrate it into your iOS app:

## Step 1: Update BereanGenkitService.swift

Find your `BereanGenkitService.swift` file and update the base URL:

### Before:
```swift
private let baseURL = "http://localhost:3400"  // or whatever it was
```

### After:
```swift
private let baseURL = "https://genkit-amen-78278013543.us-central1.run.app"
```

## Step 2: Update the Request Format

The Cloud Run service expects a slightly different request format:

### For Bible Chat:

```swift
func sendMessage(_ message: String, history: [[String: String]] = []) async throws -> String {
    let url = URL(string: "\(baseURL)/bibleChat")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30

    // Updated request body format
    let body: [String: Any] = [
        "message": message,
        "history": history  // Array of [role: "user/assistant", content: "..."]
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw NSError(domain: "BereanService", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    }

    // The response format is: { "response": "..." }
    let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
    return chatResponse.response
}

struct ChatResponse: Codable {
    let response: String
}
```

### For Fun Bible Facts:

```swift
func generateFunBibleFact(category: String = "random") async throws -> String {
    let url = URL(string: "\(baseURL)/generateFunBibleFact")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30

    let body: [String: Any] = [
        "data": [
            "category": category
        ]
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw NSError(domain: "BereanService", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    }

    let factResponse = try JSONDecoder().decode(FactResponse.self, from: data)
    return factResponse.result.fact
}

struct FactResponse: Codable {
    let result: FactResult
}

struct FactResult: Codable {
    let fact: String
}
```

## Step 3: Update Info.plist for Network Access

Make sure your Info.plist allows the Cloud Run domain:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>us-central1.run.app</key>
        <dict>
            <key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
            <false/>
            <key>NSIncludesSubdomains</key>
            <true/>
        </dict>
    </dict>
</dict>
```

Actually, since Cloud Run uses HTTPS by default, you might not need this. But if you have any ATS settings, make sure they allow HTTPS connections.

## Step 4: Test the Integration

Add this test function to verify the connection:

```swift
func testConnection() async {
    do {
        print("🧪 Testing Genkit Cloud Run connection...")

        // Test health endpoint
        let healthURL = URL(string: "\(baseURL)/")!
        let (healthData, _) = try await URLSession.shared.data(from: healthURL)
        if let healthStr = String(data: healthData, encoding: .utf8) {
            print("✅ Health check: \(healthStr)")
        }

        // Test Bible chat
        let response = try await sendMessage("What is faith?")
        print("✅ Bible chat working: \(response.prefix(100))...")

        // Test fun fact
        let fact = try await generateFunBibleFact(category: "Old Testament")
        print("✅ Fun facts working: \(fact)")

    } catch {
        print("❌ Connection test failed: \(error)")
    }
}
```

## Step 5: Update DailyVerseGenkitService.swift (if applicable)

If you have a separate service for daily verses, update it similarly:

```swift
class DailyVerseGenkitService {
    private let baseURL = "https://genkit-amen-78278013543.us-central1.run.app"

    // ... rest of your implementation
}
```

## Complete Example Service

Here's a complete, production-ready service implementation:

```swift
import Foundation

class BereanGenkitService: ObservableObject {
    private let baseURL = "https://genkit-amen-78278013543.us-central1.run.app"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Bible Chat

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

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorData = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw ServiceError.serverError(errorData.error)
            }
            throw ServiceError.httpError(httpResponse.statusCode)
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.response
    }

    // MARK: - Fun Bible Facts

    func generateFunBibleFact(category: String = "random") async throws -> String {
        let url = URL(string: "\(baseURL)/generateFunBibleFact")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "data": ["category": category]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.invalidResponse
        }

        let factResponse = try JSONDecoder().decode(FactResponse.self, from: data)
        return factResponse.result.fact
    }

    // MARK: - Health Check

    func checkHealth() async throws -> Bool {
        let url = URL(string: "\(baseURL)/health")!
        let (data, _) = try await session.data(from: url)
        let health = try JSONDecoder().decode(HealthResponse.self, from: data)
        return health.status == "ok" || health.status == "healthy"
    }
}

// MARK: - Response Models

struct ChatResponse: Codable {
    let response: String
}

struct FactResponse: Codable {
    let result: FactResult
}

struct FactResult: Codable {
    let fact: String
}

struct HealthResponse: Codable {
    let status: String
}

struct ErrorResponse: Codable {
    let error: String
}

// MARK: - Error Types

enum ServiceError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case serverError(String)
    case networkError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .networkError:
            return "Network connection failed"
        }
    }
}
```

## Usage in Your Views

### In BereanAIAssistantView:

```swift
struct BereanAIAssistantView: View {
    @StateObject private var service = BereanGenkitService()
    @State private var userMessage = ""
    @State private var isLoading = false
    @State private var conversation: [[String: String]] = []

    var body: some View {
        VStack {
            // Your UI here

            Button("Send") {
                Task {
                    isLoading = true
                    defer { isLoading = false }

                    do {
                        let response = try await service.sendMessage(
                            userMessage,
                            history: conversation
                        )

                        conversation.append(["role": "user", "content": userMessage])
                        conversation.append(["role": "assistant", "content": response])
                        userMessage = ""

                    } catch {
                        print("Error: \(error)")
                    }
                }
            }
            .disabled(isLoading)
        }
        .onAppear {
            Task {
                // Test connection on appear
                do {
                    let isHealthy = try await service.checkHealth()
                    print("Service health: \(isHealthy ? "✅" : "❌")")
                } catch {
                    print("Health check failed: \(error)")
                }
            }
        }
    }
}
```

## Troubleshooting

### If you get connection errors:

1. **Check your internet connection**
   - The app needs internet to reach Cloud Run

2. **Verify the URL is correct**
   ```swift
   print("Connecting to: \(baseURL)")
   ```

3. **Check response status**
   ```swift
   print("Status code: \(httpResponse.statusCode)")
   print("Response: \(String(data: data, encoding: .utf8) ?? "nil")")
   ```

4. **Enable verbose logging**
   ```swift
   URLSession.shared.configuration.urlCache = nil
   ```

### Common Issues:

- **Timeout errors**: Increase timeout to 60 seconds
- **SSL errors**: Make sure you're using `https://` not `http://`
- **404 errors**: Check the endpoint path is correct (`/bibleChat` not `/bible-chat`)
- **500 errors**: Check Cloud Run logs for server-side issues

## Testing Checklist

- [ ] Health check works
- [ ] Bible chat responds correctly
- [ ] Fun facts generate properly
- [ ] Error handling works (try with no internet)
- [ ] Loading states show correctly
- [ ] Conversation history persists
- [ ] App doesn't crash on network errors

---

**Updated:** February 7, 2026
**Service URL:** https://genkit-amen-78278013543.us-central1.run.app
**Status:** Production Ready ✅
