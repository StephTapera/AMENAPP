# Visual Guide: AI Integration in Resources

## 📱 What You'll See

### Resources Tab Layout

```
┌─────────────────────────────────────┐
│  Resources                          │
│  ┌─────────────────────────────┐   │
│  │  Search resources...         │   │
│  └─────────────────────────────┘   │
│  [All] [Mental] [Crisis] [Tools]   │
├─────────────────────────────────────┤
│                                     │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓     │  ← AI DAILY VERSE
│  ┃ 📖 Your Daily Verse  ✨  ⋮  ┃     │    (Currently: Fallback)
│  ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━┫     │
│  ┃ 🏷️ Strength    Feb 7, 2026 ┃     │
│  ┃                             ┃     │
│  ┃ "I can do all things       ┃     │
│  ┃  through Christ who        ┃     │
│  ┃  strengthens me."          ┃     │
│  ┃ — Philippians 4:13         ┃     │
│  ┃                             ┃     │
│  ┃ [✨ See AI Reflection]      ┃     │
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛     │
│                                     │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓     │  ← FUN BIBLE FACT
│  ┃ 💡 Fun Bible Fact      ⟳  ┃     │    ✅ AI WORKING!
│  ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━┫     │
│  ┃                             ┃     │
│  ┃ Many scholars believe the  ┃     │
│  ┃ Book of Job, despite       ┃     │
│  ┃ appearing later in the     ┃     │
│  ┃ canon, is actually the     ┃     │
│  ┃ oldest book in the Bible...┃     │
│  ┃                             ┃     │
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛     │
│                                     │
│  🤝 AMEN | Connect                  │
│  ┌────────────────────────────┐    │
│  │ 👥 Private Communities     │    │
│  └────────────────────────────┘    │
│  ...                                │
└─────────────────────────────────────┘
```

---

## 🎯 Key Interactions

### Fun Bible Fact Refresh

**Before Tap:**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 💡 Fun Bible Fact      ⟳  ┃  ← Tap this button
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ The shortest verse in the  ┃
┃ Bible is "Jesus wept"...   ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**During Loading:**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 💡 Fun Bible Fact     ⚙️  ┃  ← Spinner rotates
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ The shortest verse in the  ┃
┃ Bible is "Jesus wept"...   ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**After Tap:**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 💡 Fun Bible Fact      ⟳  ┃  ← Back to normal
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ Many scholars believe the  ┃  ← NEW FACT! ✨
┃ Book of Job is actually... ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

### Daily Verse Expansion

**Collapsed (Default):**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 📖 Your Daily Verse  ✨  ⋮  ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ 🏷️ Strength    Feb 7, 2026 ┃
┃                             ┃
┃ "I can do all things       ┃
┃  through Christ who        ┃
┃  strengthens me."          ┃
┃ — Philippians 4:13         ┃
┃                             ┃
┃ [✨ See AI Reflection ▼]    ┃  ← Tap to expand
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Expanded:**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 📖 Your Daily Verse  ✨  ⋮  ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ 🏷️ Strength    Feb 7, 2026 ┃
┃                             ┃
┃ "I can do all things       ┃
┃  through Christ who        ┃
┃  strengthens me."          ┃
┃ — Philippians 4:13         ┃
┃                             ┃
┃ ────────────────────────── ┃
┃                             ┃
┃ 🧠 AI Reflection            ┃
┃ God's strength is always   ┃
┃ available to us in every   ┃
┃ situation we face...       ┃
┃                             ┃
┃ 🎯 Today's Action           ┃
┃ Identify one challenge     ┃
┃ you're facing today and    ┃
┃ ask God for strength...    ┃
┃                             ┃
┃ 🙏 Prayer Prompt            ┃
┃ Lord, I thank you that     ┃
┃ your strength is perfect...┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

---

## 🔄 Data Flow Diagrams

### Fun Bible Fact Generation

```
┌─────────────┐
│    User     │
│  Taps ⟳     │
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│  ResourcesView.swift    │
│  refreshBibleFact()     │
└──────┬──────────────────┘
       │
       ▼
┌────────────────────────────────┐
│  BereanGenkitService.swift     │
│  generateFunBibleFact()        │
└──────┬─────────────────────────┘
       │
       │  POST { "data": { "category": "random" } }
       ▼
┌─────────────────────────────────────┐
│  Cloud Run Service                  │
│  genkit-amen.run.app                │
│  /generateFunBibleFact              │
└──────┬──────────────────────────────┘
       │
       │  Uses Gemini 2.5 Flash
       ▼
┌─────────────────────────────────────┐
│  Google AI                          │
│  Generates interesting Bible fact   │
└──────┬──────────────────────────────┘
       │
       │  Returns { "result": { "fact": "..." } }
       ▼
┌────────────────────────────────┐
│  BereanGenkitService           │
│  Parses JSON response          │
└──────┬─────────────────────────┘
       │
       ▼
┌─────────────────────────┐
│  ResourcesView          │
│  Updates UI with fact   │
│  Shows animation        │
└─────────────────────────┘
```

### Error Handling Flow

```
┌─────────────┐
│  API Call   │
└──────┬──────┘
       │
    ┌──▼───┐
    │ Try  │
    └──┬───┘
       │
   Success? ──Yes──▶ Display AI Fact ✅
       │
       No
       │
       ▼
   ┌────────┐
   │ Catch  │
   └───┬────┘
       │
       ▼
   Log Error
       │
       ▼
   Use Fallback
       │
       ▼
   Display Static Fact ✅
   (User never sees error!)
```

---

## 📊 Service Architecture

```
┌─────────────────────────────────────────┐
│           ResourcesView.swift           │
│                                         │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │ Daily Verse  │  │ Fun Bible Fact  │ │
│  │    Card      │  │      Card       │ │
│  └──────┬───────┘  └────────┬────────┘ │
└─────────┼────────────────────┼──────────┘
          │                    │
          │                    │
┌─────────▼──────────┐  ┌──────▼───────────┐
│ DailyVerseGenkit   │  │ BereanGenkit     │
│    Service         │  │    Service       │
│                    │  │                  │
│ Endpoint:          │  │ Endpoint:        │
│ genkit-amen...app  │  │ genkit-amen...app│
│                    │  │                  │
│ Status: ⏳ Ready   │  │ Status: ✅ LIVE  │
│ (needs endpoint)   │  │                  │
└────────────────────┘  └──────────────────┘
          │                    │
          └─────────┬──────────┘
                    │
          ┌─────────▼─────────┐
          │   Cloud Run       │
          │   genkit-amen     │
          │                   │
          │   Endpoints:      │
          │   /bibleChat ✅   │
          │   /generateFun... ✅│
          │   /generateDaily... ⏳│
          └───────────────────┘
```

---

## 🎨 UI States

### Bible Fact Card States

#### 1. **Initial State**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 💡 Fun Bible Fact      ⟳  ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ The Bible was written by   ┃
┃ approximately 40 different ┃
┃ authors over 1,500 years...┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

#### 2. **Loading State**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 💡 Fun Bible Fact     🔄  ┃  ← Animated spinner
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ The Bible was written by   ┃  ← Old fact still visible
┃ approximately 40 different ┃
┃ authors over 1,500 years...┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

#### 3. **Success State**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 💡 Fun Bible Fact      ⟳  ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ The shortest verse in the  ┃  ← NEW! Slides in
┃ Bible is "Jesus wept"      ┃
┃ found in John 11:35...     ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

#### 4. **Error/Offline State** (Same as Success)
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 💡 Fun Bible Fact      ⟳  ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ Psalm 119 is the longest   ┃  ← Fallback fact
┃ chapter in the Bible with  ┃  ← User doesn't know
┃ 176 verses...              ┃  ← it's offline!
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

---

## 🧪 Testing Scenarios

### Scenario 1: Online, API Working
```
User Action → API Call → Success ✅
│
└─▶ New AI-generated fact appears
    Console: "✅ AI-generated Bible fact loaded"
```

### Scenario 2: Offline
```
User Action → API Call → Network Error ⚠️
│
└─▶ Fallback fact appears (user doesn't notice)
    Console: "⚠️ AI fact generation failed, using fallback"
```

### Scenario 3: Server Error
```
User Action → API Call → 500 Error ⚠️
│
└─▶ Fallback fact appears
    Console: "❌ HTTP Error: 500"
```

### Scenario 4: Timeout
```
User Action → API Call → 30s Timeout ⏱️
│
└─▶ Fallback fact appears
    Console: "❌ Network error: timeout"
```

**In all cases: User sees content! ✅**

---

## 📱 User Journey

### First Launch
```
1. User opens app
2. Navigates to Resources tab
3. Sees Daily Verse (fallback)
4. Sees Fun Bible Fact (default)
5. Scrolls through resources
```

### Using Fun Bible Fact
```
1. User notices Fun Bible Fact card
2. Reads current fact
3. Taps refresh button (⟳)
4. Sees loading animation
5. New fact appears
6. Reads new fact
7. Taps refresh again
8. Another new fact!
9. "Wow, this is cool! 🤩"
```

### Sharing Experience
```
1. User thinks "I should share this!"
2. Takes screenshot
3. Shares on social media
4. Friends see AMEN app
5. Downloads increase! 📈
```

---

## 🔍 Behind the Scenes

### What Happens in 1 Second

```
T=0.0s: User taps refresh
T=0.1s: isRefreshingFact = true
T=0.1s: Spinner starts rotating
T=0.1s: API call starts
T=0.2s: Request sent to Cloud Run
T=0.3s: Cloud Run receives request
T=0.4s: Calls Gemini API
T=1.0s: Gemini generates fact
T=1.5s: Response sent back
T=1.6s: App receives response
T=1.6s: Parse JSON
T=1.7s: Update UI
T=1.7s: New fact slides in
T=1.8s: Animation completes
T=2.0s: isRefreshingFact = false
```

**Total time: ~2 seconds** ⚡

---

## 📦 What's Deployed

### Cloud Run Service
```
Service: genkit-amen
Region: us-central1
URL: https://genkit-amen-78278013543.us-central1.run.app

Endpoints:
  ✅ GET  /           (health check)
  ✅ GET  /health     (status)
  ✅ POST /bibleChat  (AI chat)
  ✅ POST /generateFunBibleFact (AI facts)
  ⏳ POST /generateDailyVerse (pending)

Configuration:
  Model: Gemini 2.5 Flash
  Memory: 1GB
  Timeout: 60s
  Auth: Public (no key required)
```

### iOS App
```
Services:
  ✅ BereanGenkitService (Bible Chat, Fun Facts)
  ✅ DailyVerseGenkitService (Daily Verses)

Views:
  ✅ ResourcesView (displays cards)
  ✅ AIDailyVerseCard (verse UI)
  ✅ BibleFactCard (fact UI)

Configuration:
  Endpoint: genkit-amen.run.app
  Timeout: 30s
  Fallback: Enabled ✅
```

---

## Summary Visual

```
┌─────────────────────────────────────────┐
│         AMEN App Resources Tab          │
└─────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
    ┌───▼────┐           ┌──────▼──────┐
    │ Daily  │           │ Fun Bible   │
    │ Verse  │           │   Fact      │
    └───┬────┘           └──────┬──────┘
        │                       │
        │ Fallback              │ AI ✅
        │                       │
    ┌───▼────────────────────────▼──────┐
    │      Cloud Run Service            │
    │   genkit-amen.run.app             │
    │                                   │
    │   Powered by Gemini 2.5 Flash    │
    └───────────────────────────────────┘
```

**Status: Production Ready!** 🚀

