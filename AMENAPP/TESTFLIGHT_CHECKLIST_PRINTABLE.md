# TestFlight Upload Checklist - Print This!

**Date:** ___________ **Build #:** ___________

---

## ☑️ PRE-FLIGHT (Do These First)

### Infrastructure
- [ ] **Genkit server deployed**
  ```bash
  curl https://genkit-amen-78278013543.us-central1.run.app/health
  ```
  Expected: `{"status": "ok"}`

- [ ] **Test AI endpoint**
  ```bash
  curl -X POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat \
    -H "Content-Type: application/json" \
    -d '{"message":"test","history":[]}'
  ```
  Expected: JSON response with "response" field

### Code Changes (Already Done ✅)
- [x] Removed DEBUG mock responses from BereanAIAssistantView.swift
- [x] Added network checks to BereanDataManager.swift
- [x] Added offline handling to PostCard.swift

### Firebase Setup
- [ ] **Add to app init** (AMENAPPApp.swift or AppDelegate):
  ```swift
  Database.database().isPersistenceEnabled = true
  Database.database().persistenceCacheSizeBytes = 50 * 1024 * 1024
  ```

### Info.plist Verification
- [ ] **GENKIT_ENDPOINT** exists and is correct
  Value should be: `https://genkit-amen-78278013543.us-central1.run.app`

---

## ☑️ DEVICE TESTING (On Real Device, Not Simulator!)

### Test 1: Basic Functionality
- [ ] Open Berean AI tab
- [ ] Type: "What does John 3:16 mean?"
- [ ] Response appears (not "mock" response)
- [ ] Response makes sense
- [ ] Can read full response

### Test 2: Offline Mode
- [ ] Enable Airplane Mode
- [ ] Try to send a message  
- [ ] Error banner appears (not crash)
- [ ] Error says "offline" or "no connection"
- [ ] Disable Airplane Mode
- [ ] Try same message again
- [ ] Response works now

### Test 3: Stop Generation
- [ ] Send a message
- [ ] Tap Stop button immediately
- [ ] Generation stops
- [ ] No crash
- [ ] Send another message
- [ ] New message works

### Test 4: Error Recovery
- [ ] Disconnect WiFi mid-request
- [ ] Error banner appears
- [ ] Reconnect WiFi
- [ ] Tap Retry
- [ ] Response works

### Test 5: Share to Feed
- [ ] Get an AI response
- [ ] Tap share button
- [ ] Add personal note
- [ ] Share to OpenTable
- [ ] Check OpenTable feed
- [ ] Post appears

### Test 6: Saved Messages
- [ ] Get an AI response
- [ ] Open menu (...)
- [ ] Tap "Save for Later"
- [ ] Go to Settings → Saved Messages
- [ ] Message appears

---

## ☑️ XCODE CONFIGURATION

### Build Settings
- [ ] **Build Configuration**: Release (not Debug)
- [ ] **Code Signing**: Automatic
- [ ] **Team**: Selected

### Version & Build
- [ ] **Version** number is correct (e.g., 1.0.0)
- [ ] **Build** number incremented from last build

### Clean Build
- [ ] Product → Clean Build Folder (Shift+Cmd+K)
- [ ] Quit Xcode
- [ ] Reopen Xcode
- [ ] Open your project

---

## ☑️ ARCHIVE & UPLOAD

### Archive
- [ ] Product → Archive
- [ ] Wait for archive to complete (~2-5 min)
- [ ] Organizer window opens
- [ ] Select your archive

### Validate
- [ ] Click "Validate App"
- [ ] Select distribution method: App Store Connect
- [ ] Fix any errors/warnings
- [ ] Validation succeeds

### Upload
- [ ] Click "Distribute App"
- [ ] Select: App Store Connect
- [ ] Select: Upload
- [ ] Wait for upload (~5-15 min)
- [ ] Upload succeeds

---

## ☑️ APP STORE CONNECT

### Navigate to Build
- [ ] Go to https://appstoreconnect.apple.com
- [ ] Select your app
- [ ] Click TestFlight tab
- [ ] Wait for processing (10-30 min)
- [ ] Build appears

### Configure Build
- [ ] Select the build
- [ ] **Export Compliance**: 
  - Does your app use encryption? **YES**
  - Is it exempt? **NO** (uses HTTPS)
- [ ] Fill "What to Test" (see below)
- [ ] Save changes

### What to Test Template
```
🆕 Berean AI Assistant (Beta)

NEW FEATURES:
• AI-powered Bible study companion
• Ask questions in natural language
• Get detailed Scripture explanations
• Smart Features for guided study
• Share insights to OpenTable feed

HOW TO TEST:
1. Open Berean AI tab
2. Ask: "What does John 3:16 mean?"
3. Try Smart Features (star icon)
4. Share a response to OpenTable
5. Test offline mode (Airplane Mode)

KNOWN LIMITATIONS:
• Requires internet connection
• First response may take 10-30 seconds
• Complex questions take longer

PLEASE REPORT:
• Any incorrect Biblical information
• App crashes or freezes
• Slow or empty responses
• Confusing UI/UX

Thank you for testing! 🙏
```

### Submit for Review
- [ ] Click "Submit for Review"
- [ ] Wait for beta app review (~24 hours)

---

## ☑️ POST-UPLOAD MONITORING

### First Hour
- [ ] Check TestFlight for processing completion
- [ ] Verify build shows up
- [ ] Download and test yourself
- [ ] Check for any immediate crashes

### First Day
- [ ] Monitor Cloud Run logs:
  https://console.cloud.google.com/run/detail/us-central1/genkit-amen/logs
- [ ] Check for error spikes
- [ ] Review TestFlight feedback

### First Week
- [ ] Read tester feedback
- [ ] Track crash rate
- [ ] Monitor AI response times
- [ ] Note feature requests

---

## 📊 SUCCESS METRICS

Track these in TestFlight + Firebase Analytics:

**Adoption:**
- [ ] % of testers who open Berean AI
- [ ] Average sessions per tester
- [ ] Messages sent per session

**Performance:**
- [ ] Average response time
- [ ] Error rate
- [ ] Crash rate (should be < 1%)

**Engagement:**
- [ ] Messages shared to feed
- [ ] Messages saved
- [ ] Return users after 3 days

---

## 🚨 TROUBLESHOOTING

### If AI Returns Empty Responses
```bash
# Check server status
curl https://genkit-amen-78278013543.us-central1.run.app/health

# View logs
gcloud logging read "resource.type=cloud_run_revision" \
  --limit 50 \
  --format json

# Redeploy if needed
cd genkit-flows && npm run deploy
```

### If Build Won't Archive
1. Clean Build Folder
2. Restart Xcode
3. Check code signing
4. Check for syntax errors

### If Upload Fails
1. Check Apple Developer account status
2. Check app agreements are signed
3. Try uploading again (can be flaky)

---

## ✅ FINAL SIGN-OFF

**I confirm:**
- [ ] All tests passed on real device
- [ ] Genkit server is responding
- [ ] Firebase offline mode works
- [ ] No crashes in basic flows
- [ ] Build uploaded successfully
- [ ] What to Test notes added
- [ ] Ready for beta testers

**Signed:** _________________ **Date:** _________

---

## 📞 EMERGENCY CONTACTS

**If server goes down:**
- Redeploy: `cd genkit-flows && gcloud run deploy genkit-amen --source .`
- Check status: Cloud Console → Cloud Run

**If critical bug found:**
- Fix bug
- Increment build number
- Re-upload to TestFlight
- Notify testers via TestFlight

**For help:**
- Check: TESTFLIGHT_DEPLOYMENT_GUIDE.md
- Check: FIREBASE_OFFLINE_FIX_GUIDE.md
- Check: Cloud Run logs

---

**🎉 YOU'VE GOT THIS! 🚀**

TestFlight is the final step before App Store.
Take your time, test thoroughly, and ship with confidence!
