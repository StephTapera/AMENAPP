# 🎯 Genkit Architecture & Hosting Overview

## 📊 System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          YOUR MAC                                │
│                                                                  │
│  ┌────────────────────┐         ┌──────────────────────┐       │
│  │   iOS Simulator    │         │   Terminal           │       │
│  │   or Device        │         │                      │       │
│  │                    │         │  $ cd genkit         │       │
│  │  ┌──────────────┐  │  HTTP   │  $ npm run dev       │       │
│  │  │ AMEN App     │  │ ◄────►  │                      │       │
│  │  │              │  │         │  ✓ Genkit Server     │       │
│  │  │ Berean AI    │  │         │    Port 3400         │       │
│  │  └──────────────┘  │         │                      │       │
│  └────────────────────┘         │  ✓ Developer UI      │       │
│                                  │    Port 4000         │       │
│                                  └──────────────────────┘       │
│                                           │                      │
│                                           │ API Calls            │
│                                           ▼                      │
│                                  ┌──────────────────────┐       │
│                                  │ Google AI (Gemini)   │       │
│                                  │ via API Key          │       │
│                                  └──────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Local Development Flow

```
1. Start Terminal
   │
   ├─► Navigate to genkit/
   │   $ cd genkit
   │
   ├─► Start Server
   │   $ npm run dev
   │
   ├─► Server Starts
   │   ✓ API at http://localhost:3400
   │   ✓ UI at http://localhost:4000
   │
   └─► Ready for iOS App!
       │
       ├─► Open Xcode
       ├─► Press Cmd+R
       ├─► App connects to localhost:3400
       └─► Berean AI works! ✨
```

## 🌐 Production Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        PRODUCTION                                │
│                                                                  │
│  ┌────────────────────┐                                         │
│  │  User's iPhone     │                                         │
│  │                    │                                         │
│  │  ┌──────────────┐  │  HTTPS                                 │
│  │  │  AMEN App    │──┼────────────────┐                       │
│  │  │  (TestFlight │  │                │                       │
│  │  │   or Store)  │  │                │                       │
│  │  └──────────────┘  │                │                       │
│  └────────────────────┘                │                       │
│                                         ▼                       │
│                              ┌─────────────────────┐            │
│                              │  Google Cloud Run   │            │
│                              │                     │            │
│                              │  ┌───────────────┐  │            │
│                              │  │ Genkit Server │  │            │
│                              │  │ (Docker)      │  │            │
│                              │  │               │  │            │
│                              │  │ - Auto-scale  │  │            │
│                              │  │ - HTTPS       │  │            │
│                              │  │ - Rate limit  │  │            │
│                              │  └───────────────┘  │            │
│                              │                     │            │
│                              │  URL: https://      │            │
│                              │  berean-genkit-     │            │
│                              │  xxxxx.run.app      │            │
│                              └─────────────────────┘            │
│                                         │                       │
│                                         │ API Key Auth          │
│                                         ▼                       │
│                              ┌─────────────────────┐            │
│                              │  Google AI API      │            │
│                              │  (Gemini Models)    │            │
│                              └─────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

## 📁 File Structure

```
AMENAPP/
│
├── start-genkit.sh                    # ◄─ Run this to start!
├── GENKIT_QUICK_START.md              # Quick start guide
├── GENKIT_HOSTING_PRODUCTION_GUIDE.md # Full production guide
├── TERMINAL_COMMANDS.md               # Copy-paste commands
│
├── AMENAPP/                           # iOS App
│   ├── Info.plist                     # Has GENKIT_ENDPOINT
│   ├── BereanGenkitService.swift      # Calls Genkit API
│   └── BereanAIAssistantView.swift    # UI
│
└── genkit/                            # ◄─ Your backend is here!
    ├── src/
    │   └── berean-flows.ts            # AI flows (bibleChat, etc.)
    │
    ├── package.json                   # Dependencies
    ├── tsconfig.json                  # TypeScript config
    │
    ├── .env                           # ◄─ Your API keys (local)
    ├── .env.example                   # Template
    │
    └── README.md                      # Documentation
```

## 🔄 Data Flow

```
User Types Message in iOS
        │
        ├─► BereanAIAssistantView
        │
        ├─► BereanGenkitService.sendMessage()
        │
        ├─► HTTP POST to Genkit
        │   URL: http://localhost:3400/bibleChat
        │   Body: { message: "...", history: [...] }
        │
        ├─► Genkit Server (genkit/src/berean-flows.ts)
        │   - Validates input
        │   - Calls Google AI with prompt
        │   - Streams response
        │
        ├─► Google Gemini API
        │   - Processes with AI model
        │   - Returns biblical insights
        │
        ├─► Response Streams Back
        │   - Chunk by chunk
        │   - Real-time display
        │
        └─► User Sees AI Response! ✨
```

## 🎯 Two Environments

### **Local Development**
```
┌──────────────────┐       ┌──────────────────┐
│   Your Mac       │       │   Terminal       │
│                  │       │                  │
│  iOS Simulator   │ ◄───► │  Genkit Server   │
│  localhost:3400  │       │  Port 3400       │
└──────────────────┘       └──────────────────┘

✅ Fast iteration
✅ Full debugging
✅ No deployment needed
✅ Free (uses your API key)
```

### **Production**
```
┌──────────────────┐       ┌──────────────────┐
│  User's iPhone   │       │  Cloud Run       │
│                  │       │                  │
│  AMEN App        │ ◄───► │  Genkit Server   │
│  HTTPS URL       │       │  Auto-scaled     │
└──────────────────┘       └──────────────────┘

✅ Always available
✅ Auto-scaling
✅ HTTPS secure
✅ Pay per request
```

## 🚦 Request Flow Diagram

```
iOS App Request:
┌─────────────────────────────────────────────────────┐
│ POST /bibleChat                                      │
│ {                                                    │
│   "message": "What does John 3:16 mean?",          │
│   "history": []                                      │
│ }                                                    │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│ Genkit Server (berean-flows.ts)                     │
│                                                      │
│ 1. Validate input ✓                                 │
│ 2. Build prompt with context                        │
│ 3. Call Gemini API                                  │
│ 4. Stream response                                  │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│ Google AI API                                        │
│                                                      │
│ - Process with Gemini 2.0 Flash                     │
│ - Generate biblical insights                        │
│ - Return streamed response                          │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│ iOS App Response:                                    │
│ {                                                    │
│   "response": "John 3:16 is one of the most..."    │
│ }                                                    │
│                                                      │
│ ✨ User sees AI response in real-time!              │
└─────────────────────────────────────────────────────┘
```

## 🔐 Security Layers

```
┌─────────────────────────────────────────────────────┐
│ Production Security Stack                            │
├─────────────────────────────────────────────────────┤
│                                                      │
│  1. HTTPS Only                                       │
│     └─► All traffic encrypted                       │
│                                                      │
│  2. API Key Authentication                           │
│     └─► X-API-Key header required                   │
│                                                      │
│  3. Rate Limiting                                    │
│     └─► 100 requests per 15 min per IP              │
│                                                      │
│  4. CORS Policy                                      │
│     └─► Only your iOS app can call                  │
│                                                      │
│  5. Firebase App Check                               │
│     └─► Verify requests from real app               │
│                                                      │
│  6. Input Validation                                 │
│     └─► TypeScript schemas enforce types            │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## 💰 Cost Structure

```
Local Development:
┌──────────────────────────────────────┐
│ Free!                                 │
│ - Runs on your Mac                    │
│ - Only pays Google AI API costs       │
│ - ~$0.10 per 1000 requests            │
└──────────────────────────────────────┘

Production (Cloud Run):
┌──────────────────────────────────────┐
│ Pay per request                       │
│ - First 2M requests/month: FREE       │
│ - Then: $0.40 per million requests    │
│ - Plus Google AI API costs            │
│                                       │
│ Example: 10,000 users                 │
│ - Each sends 10 messages/month        │
│ - = 100,000 requests                  │
│ - = FREE (under 2M)                   │
│ - AI cost: ~$10/month                 │
└──────────────────────────────────────┘
```

## 📊 Performance Metrics

```
Local Development:
├─► Response Time: 1-2 seconds
├─► Cold Start: None (always warm)
├─► Scalability: Limited to Mac
└─► Debugging: Full access

Production (Cloud Run):
├─► Response Time: 0.5-1.5 seconds
├─► Cold Start: <1 second (first request)
├─► Scalability: Auto (0 to infinite)
└─► Debugging: Cloud logs + traces
```

## 🎯 Quick Decision Guide

**When to use Local:**
- ✅ Development
- ✅ Testing new features
- ✅ Debugging
- ✅ Learning Genkit

**When to use Production:**
- ✅ TestFlight testing
- ✅ App Store release
- ✅ Real users
- ✅ Always available

## 🔄 Deployment Workflow

```
Development:
    │
    ├─► Write Code
    │   (berean-flows.ts)
    │
    ├─► Test Locally
    │   (npm run dev)
    │
    ├─► Verify in iOS
    │   (Run in simulator)
    │
    ├─► All Good?
    │
    └─► Deploy to Production
        (genkit deploy)
        │
        ├─► Update iOS Info.plist
        │   with production URL
        │
        ├─► Test on TestFlight
        │
        └─► Release to App Store ✨
```

## 🎉 Summary

**What You Have:**
- ✅ Genkit backend in `genkit/` folder
- ✅ Ready to run on your Mac
- ✅ Ready to deploy to Cloud Run
- ✅ Connected to iOS app
- ✅ Powered by Google Gemini AI

**How to Run:**
```bash
cd genkit
npm run dev
```

**Where It Runs:**
- 🖥️ Local: `http://localhost:3400`
- 🌐 Production: `https://berean-genkit-xxxxx.run.app`

**What It Does:**
- 💬 Bible chat
- 📖 Scripture analysis
- 🙏 Prayer guidance
- ✨ Spiritual insights

**Ready to start?**
```bash
./start-genkit.sh
```

🚀 **Let's go!**
