# 🚀 START HERE - Getting Berean AI Running

## Where Am I? Where Do I Run These Commands?

You're currently in Xcode looking at your iOS app code. To start the Genkit AI server, you need to **open Terminal** (a separate app on your Mac).

---

## Step-by-Step Instructions

### Step 1: Open Terminal

**Option A - From Spotlight:**
1. Press `Cmd + Space` (⌘ + Space)
2. Type "Terminal"
3. Press Enter

**Option B - From Applications:**
1. Open Finder
2. Go to Applications → Utilities
3. Double-click "Terminal"

### Step 2: Navigate to Your Project

In Terminal, type these commands **one at a time**, pressing Enter after each:

```bash
# Replace this path with where your AMENAPP project is located
# Common locations:
cd ~/Desktop/AMEN/AMENAPP         # If it's on your Desktop
# OR
cd ~/Documents/AMENAPP             # If it's in Documents
# OR
cd ~/Downloads/AMENAPP             # If it's in Downloads

# Then navigate into the genkit folder
cd genkit
```

**💡 Tip:** You can drag the `genkit` folder from Finder into Terminal to automatically fill in the path!

### Step 3: Install Dependencies (First Time Only)

```bash
npm install
```

This will take 30-60 seconds. You'll see lots of text scroll by - that's normal!

### Step 4: Create Environment File

```bash
cp .env.example .env
```

### Step 5: Add Your API Key

**Get a free API key:**
1. Go to: https://aistudio.google.com/app/apikey
2. Sign in with your Google account
3. Click "Create API Key"
4. Copy the key

**Add it to your project:**
```bash
# Open the .env file in a text editor
open .env
```

This opens the file. Add your key like this:
```
GOOGLE_AI_API_KEY=<GOOGLE_AI_API_KEY> (paste your key here)
```

Save and close the file.

### Step 6: Start the Server!

```bash
npm run dev
```

**✅ Success looks like this:**
```
✓ Genkit developer UI running at http://localhost:4000
✓ Genkit server running at http://localhost:3400
```

**Keep Terminal open!** The server needs to stay running.

---

## Step 7: Test in Your iOS App

1. Go back to Xcode
2. Click the Play button (or press `Cmd + R`)
3. Open Berean AI in your app
4. Ask: "What does John 3:16 mean?"
5. Watch the AI response stream in!

---

## 📍 Visual Guide

```
Your Mac
├── Xcode (already open) ← You are here
│   └── BereanAIAssistantView.swift
│
└── Terminal (need to open) ← Start server here
    └── Run commands:
        cd ~/Desktop/AMEN/AMENAPP/genkit
        npm install
        npm run dev
```

---

## ❓ Troubleshooting

### "command not found: npm"

You need to install Node.js first:
1. Go to: https://nodejs.org/
2. Download the LTS version
3. Install it
4. Restart Terminal
5. Try again

### "No such file or directory"

The path to your project is wrong. Try this:

```bash
# Find your project
cd ~
find . -name "genkit" -type d 2>/dev/null
```

This will show you where your genkit folder is. Then `cd` to that path.

### "EADDRINUSE: address already in use"

The server is already running! Check for another Terminal window, or run:
```bash
killall node
npm run dev
```

### Still stuck?

Look at the full documentation:
- **INTEGRATION_COMPLETE.md** - Complete overview
- **BEREAN_GENKIT_SETUP.md** - Detailed setup guide
- **BEREAN_QUICKSTART.md** - Quick reference

---

## 🎯 Quick Reference

Once everything is working, here's how to start Berean AI each time:

### Terminal Window 1:
```bash
cd ~/Desktop/AMEN/AMENAPP/genkit  # (your path)
npm run dev
```
**Leave this running!**

### Xcode:
```bash
Press Cmd + R to build and run
```

---

## ✅ Checklist

- [ ] Terminal is open
- [ ] Navigated to genkit folder (`cd genkit`)
- [ ] Ran `npm install` (first time only)
- [ ] Created `.env` file (`cp .env.example .env`)
- [ ] Added Google AI API key to `.env`
- [ ] Started server (`npm run dev`)
- [ ] Server shows: "✓ Genkit server running at http://localhost:3400"
- [ ] Built and ran iOS app in Xcode
- [ ] Opened Berean AI in app
- [ ] Asked a question
- [ ] Saw AI response stream in!

---

## 🎉 You're Done!

Once you see the AI responding in your app, you're all set!

**Pro Tip:** Bookmark this page or keep Terminal open in the background. You'll need to run `npm run dev` each time you restart your computer.

---

## 📚 Next Steps

- Try asking different questions
- Test the smart features panel
- Generate a devotional
- Create a study plan
- Share insights to OpenTable feed

**Enjoy your intelligent Bible study companion! 🙏**
