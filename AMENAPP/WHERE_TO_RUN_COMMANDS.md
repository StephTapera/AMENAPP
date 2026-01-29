# 🖥️ VISUAL GUIDE: Where to Run Commands

```
╔════════════════════════════════════════════════════════════════╗
║                        YOUR MAC SCREEN                          ║
║                                                                 ║
║  ┌─────────────────────────┐  ┌──────────────────────────┐   ║
║  │                          │  │                           │   ║
║  │      XCODE (iOS App)     │  │    TERMINAL (Server)     │   ║
║  │                          │  │                           │   ║
║  │  ├── AMENAPP             │  │  $ cd genkit             │   ║
║  │  │   ├── Views           │  │  $ npm install           │   ║
║  │  │   │   ├── Berean...   │  │  $ npm run dev           │   ║
║  │  │   │   └── ...         │  │                           │   ║
║  │  │   └── ...             │  │  ✓ Server running at:    │   ║
║  │  └── genkit/             │  │    http://localhost:3400 │   ║
║  │                          │  │                           │   ║
║  │  [▶ Build & Run]         │  │  (Leave this running!)   │   ║
║  │                          │  │                           │   ║
║  └─────────────────────────┘  └──────────────────────────┘   ║
║        ↑ You are here            ↑ Open Terminal here         ║
║                                                                 ║
╚════════════════════════════════════════════════════════════════╝
```

---

## Step 1: Open Terminal (Separate App)

```
Press Cmd + Space (⌘ + Space)
      ↓
Type "Terminal"
      ↓
Press Enter
      ↓
Terminal window opens
```

---

## Step 2: Navigate to Your Project

### Find your project folder:

```
Your Computer
└── Desktop (or Documents, or Downloads)
    └── AMEN
        └── AMENAPP  ← Your project
            ├── BereanAIAssistantView.swift
            ├── BereanGenkitService.swift
            └── genkit/  ← We need to go here!
                ├── berean-flows.ts
                ├── package.json
                └── .env (create this)
```

### In Terminal, type:

```bash
cd ~/Desktop/AMEN/AMENAPP/genkit
```

**💡 Easy way:** Drag the `genkit` folder into Terminal!

```
1. Open Finder
2. Navigate to your AMENAPP project
3. Find the "genkit" folder
4. In Terminal, type: cd 
5. Drag the genkit folder into Terminal (it will auto-fill the path!)
6. Press Enter
```

---

## Step 3: Install & Start (In Terminal)

```bash
# First time only
npm install

# Every time you want to start Berean AI
npm run dev
```

### What you'll see:

```
Terminal Window
┌─────────────────────────────────────────────────────┐
│ % cd ~/Desktop/AMEN/AMENAPP/genkit                  │
│ % npm run dev                                       │
│                                                     │
│ > genkit@1.0.0 dev                                 │
│ > genkit start                                      │
│                                                     │
│ ✓ Genkit developer UI running at:                 │
│   http://localhost:4000                            │
│                                                     │
│ ✓ Genkit server running at:                       │
│   http://localhost:3400                            │
│                                                     │
│ ← LEAVE THIS RUNNING!                              │
│    Don't close Terminal                             │
└─────────────────────────────────────────────────────┘
```

---

## Step 4: Build Your iOS App (In Xcode)

```
Xcode Window
┌─────────────────────────────────────────────────────┐
│  [▶ Play Button] ← Click this (or press Cmd + R)   │
│                                                     │
│  BereanAIAssistantView.swift                       │
│  ┌─────────────────────────────────────────────┐  │
│  │ import SwiftUI                               │  │
│  │                                              │  │
│  │ struct BereanAIAssistantView: View {        │  │
│  │   ...                                        │  │
│  │ }                                            │  │
│  └─────────────────────────────────────────────┘  │
│                                                     │
│  ← You edit code here                              │
└─────────────────────────────────────────────────────┘
```

---

## Step 5: Test It!

### In Your iOS App (Simulator or Device):

```
┌─────────────────────────────────────┐
│  ✨ Berean AI                        │
│                                     │
│  What does John 3:16 mean?         │
│  ┌────────────────────────────┐    │
│  │ Continue conversation      │    │
│  └────────────────────────────┘    │
│                                     │
│  Type your question here ↑          │
│                                     │
│  Watch AI response stream in!      │
│  "John" → "3:16" → "is" → "one"... │
└─────────────────────────────────────┘
```

---

## 🎯 The Complete Picture

```
╔════════════════════════════════════════════════════════════════════╗
║                    HOW IT ALL WORKS TOGETHER                        ║
╠════════════════════════════════════════════════════════════════════╣
║                                                                     ║
║  XCODE (iOS App)                     TERMINAL (Genkit Server)      ║
║  ┌─────────────────────┐            ┌─────────────────────┐       ║
║  │                      │            │                      │       ║
║  │  User asks question  │            │  npm run dev         │       ║
║  │         ↓            │            │         ↓            │       ║
║  │  BereanViewModel     │   HTTP     │  genkit server       │       ║
║  │         ↓            │  ------→   │         ↓            │       ║
║  │  GenkitService       │   POST     │  berean-flows.ts     │       ║
║  │         ↓            │   3400     │         ↓            │       ║
║  │  [Send message]      │            │  Calls Gemini AI     │       ║
║  │                      │            │         ↓            │       ║
║  │  [Receive response]  │  ←------   │  Returns response    │       ║
║  │         ↓            │  Response  │                      │       ║
║  │  Stream to UI        │            │                      │       ║
║  │         ↓            │            │                      │       ║
║  │  User sees answer!   │            │  (Keep running!)     │       ║
║  │                      │            │                      │       ║
║  └─────────────────────┘            └─────────────────────┘       ║
║                                                                     ║
║  Both need to be running at the same time!                         ║
║                                                                     ║
╚════════════════════════════════════════════════════════════════════╝
```

---

## 📋 Daily Workflow

### Every time you work on Berean AI:

**1. Open Terminal**
```bash
cd ~/Desktop/AMEN/AMENAPP/genkit
npm run dev
```
**Keep this window open!**

**2. Open Xcode**
```bash
Open your project
Press Cmd + R to run
```

**3. Done!**
Test Berean AI in your app.

---

## ⚠️ Common Mistakes

### ❌ WRONG: Running commands in Xcode console
```
(lldb) npm run dev  ← This won't work!
```

### ✅ RIGHT: Running commands in Terminal app
```
% npm run dev  ← This works!
```

---

### ❌ WRONG: Closing Terminal after starting server
```
Terminal running... → Close window → Server stops → App breaks
```

### ✅ RIGHT: Keep Terminal open in background
```
Terminal running... → Minimize → Switch to Xcode → App works!
```

---

## 🎓 Understanding the Tools

### Xcode
- **What:** IDE for building iOS apps
- **Language:** Swift
- **Runs:** Your iOS app code
- **Purpose:** Build the user interface

### Terminal
- **What:** Command-line interface
- **Language:** Bash/Shell commands
- **Runs:** Your AI server (Node.js)
- **Purpose:** Process AI requests

### They Talk to Each Other
```
iOS App (Xcode) ←--HTTP--→ AI Server (Terminal)
```

Both must be running!

---

## ✅ Success Checklist

```
Terminal:
├─ [✓] Terminal app is open
├─ [✓] Navigated to genkit folder
├─ [✓] Ran npm install (first time)
├─ [✓] Created .env file
├─ [✓] Added GOOGLE_AI_API_KEY
├─ [✓] Ran npm run dev
└─ [✓] Sees "Server running at http://localhost:3400"

Xcode:
├─ [✓] Project is open
├─ [✓] BereanGenkitService.swift exists
├─ [✓] No build errors
├─ [✓] Pressed Cmd + R to run
└─ [✓] App launches successfully

Testing:
├─ [✓] Opened Berean AI in app
├─ [✓] Typed a question
├─ [✓] Saw "Thinking..." indicator
├─ [✓] AI response streamed in
└─ [✓] Verse references appeared as chips

Result:
└─ [🎉] Berean AI is working with real AI!
```

---

## 📞 Quick Help

### Q: "I don't see Terminal app"
**A:** Press `Cmd + Space`, type "Terminal", press Enter

### Q: "command not found: npm"
**A:** Install Node.js from https://nodejs.org/ first

### Q: "No such file or directory"
**A:** Wrong path - try dragging the genkit folder into Terminal

### Q: "Port 3400 already in use"
**A:** Server is already running! Check other Terminal windows

### Q: "Invalid API key"
**A:** Check your .env file has the correct GOOGLE_AI_API_KEY

---

## 🎯 TL;DR (Too Long; Didn't Read)

1. **Open Terminal** (Cmd + Space → "Terminal")
2. **Go to genkit folder:** `cd path/to/your/genkit`
3. **Start server:** `npm run dev`
4. **Keep Terminal open**
5. **Build app in Xcode:** Cmd + R
6. **Test Berean AI**
7. **Done! 🎉**

---

Need more help? See **START_HERE.md** for detailed instructions!
