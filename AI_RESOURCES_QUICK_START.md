# AI Resources - Quick Start Guide

## What's Working Now ✅

### 1. Fun Bible Fact
**Location:** Resources Tab → Fun Bible Fact Card (orange card)
- ✅ Generates fresh AI facts on demand
- ✅ Tap refresh (⟳) button to get new facts
- ✅ Falls back to static facts if offline

### 2. Daily Verse
**Location:** Resources Tab → Your Daily Verse Card (top card)
- ✅ Shows daily Bible verse with theme
- ✅ Currently using curated fallback verses
- ⏳ AI generation ready (needs Cloud Run endpoint)

---

## Quick Test

### Test Fun Bible Fact Right Now:

1. Build and run the app
2. Go to **Resources** tab
3. Find the **Fun Bible Fact** card (orange gradient)
4. Tap the **refresh icon** (⟳)
5. Watch the new fact appear!

**Expected Result:**
```
Console Output:
📤 Calling Genkit flow: generateFunBibleFact
✅ Genkit flow completed
✅ AI-generated Bible fact loaded

UI:
- Loading spinner rotates
- New fact slides in
- Different fact each time
```

---

## How It Works

```
User taps refresh button
         ↓
BereanGenkitService.generateFunBibleFact()
         ↓
POST https://genkit-amen-78278013543.us-central1.run.app/generateFunBibleFact
         ↓
Gemini 2.5 Flash generates fact
         ↓
Parse JSON response
         ↓
Display with animation
```

---

## API Format

### Request:
```json
{
  "data": {
    "category": "random"
  }
}
```

### Response:
```json
{
  "result": {
    "fact": "The Bible was written by approximately 40 different authors over a span of 1,500 years..."
  }
}
```

---

## Code Locations

| File | Line | What It Does |
|------|------|--------------|
| `ResourcesView.swift` | 225 | BibleFactCard component |
| `ResourcesView.swift` | 502-533 | refreshBibleFact() function |
| `BereanGenkitService.swift` | 398-420 | generateFunBibleFact() API call |
| `BereanGenkitService.swift` | 38 | Cloud Run endpoint URL |

---

## Configuration

### Cloud Run Endpoint (Default)
```swift
https://genkit-amen-78278013543.us-central1.run.app
```

### Override for Local Development
Add to `Info.plist`:
```xml
<key>GENKIT_ENDPOINT</key>
<string>http://localhost:3400</string>
```

---

## Troubleshooting

### "AI fact generation failed" in console?

**Possible causes:**
- No internet connection
- Cloud Run service down
- API timeout

**What happens:**
- App automatically uses fallback facts
- No error shown to user
- Console shows warning

**To fix:**
1. Check internet connection
2. Test endpoint: `curl https://genkit-amen-78278013543.us-central1.run.app/`
3. Check Cloud Run console for errors

### Facts not changing?

- Make sure you're tapping the refresh button
- Check console for API call logs
- Try restarting the app

---

## Next: Enable AI Daily Verses

**What's needed:**
Add `/generateDailyVerse` endpoint to Cloud Run

**Code location:** See `AI_RESOURCES_INTEGRATION_COMPLETE.md` for full implementation

**Current status:** Using fallback verses (still works great!)

---

## Summary

✅ **Fun Bible Facts** - Working with AI
✅ **Daily Verse** - Working with fallback
✅ **Error Handling** - Automatic fallbacks
✅ **Production Ready** - Ship to TestFlight now!

**Your Resources tab has AI-powered content ready for users!** 🎉

---

**Quick Links:**
- Full documentation: `AI_RESOURCES_INTEGRATION_COMPLETE.md`
- Cloud Run setup: `GENKIT_DEPLOYMENT_SUCCESS.md`
- Swift integration: `SWIFT_INTEGRATION_UPDATE.md`
