# Berean AI with Genkit - Setup Guide

This guide will help you integrate Firebase Genkit with your Berean Bible Study feature.

## 📋 Prerequisites

- Node.js 20+ installed
- Firebase project set up
- Google AI API key (for Gemini)
- Xcode 15+ for iOS development

## 🚀 Step 1: Install Genkit CLI

```bash
npm install -g genkit
```

## 📦 Step 2: Set Up Genkit Backend

Navigate to the genkit directory:

```bash
cd genkit
npm install
```

## 🔑 Step 3: Configure Environment Variables

Create a `.env` file in the `genkit` directory:

```bash
GOOGLE_AI_API_KEY=your_google_ai_api_key_here
FIREBASE_PROJECT_ID=your_firebase_project_id
```

To get your Google AI API key:
1. Go to [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Create a new API key
3. Copy and paste it into your `.env` file

## 🧪 Step 4: Test Locally

Start the Genkit development server:

```bash
npm run dev
```

This will start the Genkit server at `http://localhost:3400` with:
- Hot reload enabled
- Developer UI at `http://localhost:4000`
- Flow inspection and testing tools

## 🧪 Step 5: Test Flows in Developer UI

Open `http://localhost:4000` in your browser to access the Genkit Developer UI where you can:

1. **View all flows**: See all your AI flows listed
2. **Test flows**: Run flows with sample inputs
3. **Inspect traces**: See detailed execution traces
4. **Debug**: Step through flow execution

Example test for `bibleChat` flow:
```json
{
  "message": "What does John 3:16 mean?",
  "history": []
}
```

## 📱 Step 6: Configure iOS App

### Add Configuration to Info.plist

1. Open your Xcode project
2. Open `Info.plist`
3. Add these keys:

```xml
<key>GENKIT_ENDPOINT</key>
<string>http://localhost:3400</string>
<key>GENKIT_API_KEY</key>
<string>optional_api_key_for_production</string>
```

**Important**: For local development, use `http://localhost:3400`. For production, you'll deploy to Cloud Run (see Step 8).

### Update BereanViewModel to Use Genkit Service

Replace the AI service in your `BereanAIAssistantView.swift`:

```swift
import SwiftUI

struct BereanAIAssistantView: View {
    @StateObject private var genkitService = BereanGenkitService.shared
    @State private var messages: [BereanMessage] = []
    @State private var messageText = ""
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(messages) { message in
                    MessageBubble(message: message)
                }
            }
            
            HStack {
                TextField("Ask about Scripture...", text: $messageText)
                
                Button("Send") {
                    sendMessage()
                }
            }
        }
        .overlay {
            if genkitService.isProcessing {
                ProgressView()
            }
        }
    }
    
    private func sendMessage() {
        let userMessage = BereanMessage(
            content: messageText,
            role: .user,
            timestamp: Date()
        )
        
        messages.append(userMessage)
        messageText = ""
        
        Task {
            var aiResponse = ""
            
            do {
                for try await chunk in genkitService.sendMessage(
                    userMessage.content,
                    conversationHistory: messages
                ) {
                    aiResponse += chunk
                }
                
                let aiMessage = BereanMessage(
                    content: aiResponse,
                    role: .assistant,
                    timestamp: Date()
                )
                
                await MainActor.run {
                    messages.append(aiMessage)
                }
                
            } catch {
                print("Error: \(error)")
            }
        }
    }
}
```

## 🧪 Step 7: Test iOS Integration

1. Start Genkit server: `npm run dev` (in terminal)
2. Run your iOS app in simulator
3. Try sending a message like "What does John 3:16 mean?"
4. You should see the AI respond with biblical insights

## 🚀 Step 8: Deploy to Production

### Option A: Deploy to Cloud Run (Recommended)

```bash
# Build and deploy
npm run deploy

# This will:
# 1. Build your flows
# 2. Deploy to Cloud Run
# 3. Output your production URL
```

Update your iOS app's `Info.plist` with the production URL:

```xml
<key>GENKIT_ENDPOINT</key>
<string>https://your-genkit-service-xxxxx.run.app</string>
```

### Option B: Deploy to Firebase Functions

```bash
# Initialize Firebase Functions
firebase init functions

# Deploy
firebase deploy --only functions
```

## 🔒 Step 9: Secure Your API (Production)

### Add API Key Authentication

1. Generate a secure API key:
```bash
openssl rand -hex 32
```

2. Add to your Cloud Run environment:
```bash
gcloud run services update berean-genkit \
  --update-env-vars GENKIT_API_KEY=your_generated_key
```

3. Update iOS app's `Info.plist`:
```xml
<key>GENKIT_API_KEY</key>
<string>your_generated_key</string>
```

### Enable Firebase App Check (Recommended)

1. Enable App Check in Firebase Console
2. Update Genkit flows to verify App Check tokens
3. Add App Check to your iOS app

## 📊 Step 10: Monitor & Observe

Genkit provides built-in observability:

1. **View traces**: See detailed execution traces in Developer UI
2. **Monitor costs**: Track API usage and costs
3. **Debug errors**: Inspect failed flows
4. **Performance**: Analyze response times

## 🎯 Available Flows

Your Berean AI now has these flows ready to use:

### 1. Bible Chat
```swift
genkitService.sendMessage("What does John 3:16 mean?")
```

### 2. Generate Devotional
```swift
let devotional = try await genkitService.generateDevotional(topic: "Faith")
```

### 3. Generate Study Plan
```swift
let plan = try await genkitService.generateStudyPlan(topic: "Prayer", duration: 7)
```

### 4. Analyze Scripture
```swift
let analysis = try await genkitService.analyzeScripture(
    reference: "John 3:16",
    analysisType: .contextual
)
```

### 5. Generate Memory Aid
```swift
let aid = try await genkitService.generateMemoryAid(
    verse: "For God so loved the world...",
    reference: "John 3:16"
)
```

### 6. Generate Insights
```swift
let insights = try await genkitService.generateInsights(topic: "Grace")
```

## 🐛 Troubleshooting

### Issue: "Connection refused" error

**Solution**: Make sure Genkit server is running:
```bash
cd genkit
npm run dev
```

### Issue: "Invalid API key" error

**Solution**: Check your `.env` file has the correct Google AI API key:
```bash
cat .env
```

### Issue: Slow responses

**Solution**: 
1. Check your internet connection
2. Try a different Gemini model (e.g., `gemini15Flash` instead of `gemini20FlashExp`)
3. Monitor API quota in Google Cloud Console

### Issue: iOS app can't connect to localhost

**Solution**: Use your Mac's local IP instead of `localhost`:
1. Find your IP: `ifconfig | grep inet`
2. Update Info.plist: `http://YOUR_IP:3400`

## 📚 Next Steps

1. **Add more flows**: Create custom flows for your specific needs
2. **Improve prompts**: Refine system prompts for better responses
3. **Add caching**: Cache common responses to reduce API calls
4. **Implement feedback**: Let users rate AI responses
5. **Add voice input**: Integrate speech-to-text for voice queries

## 🆘 Support

- Genkit Docs: https://firebase.google.com/docs/genkit
- Google AI Studio: https://makersuite.google.com
- Firebase Support: https://firebase.google.com/support

## 📄 License

This code is part of the AMEN app and follows the project's license.
