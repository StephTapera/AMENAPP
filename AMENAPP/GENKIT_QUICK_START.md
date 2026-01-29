# 🚀 Quick Start: Run Genkit in Terminal

## One-Command Start

```bash
# From your AMENAPP project root:
./start-genkit.sh
```

That's it! The script will:
- ✅ Check dependencies
- ✅ Install if needed
- ✅ Verify API key
- ✅ Start server
- ✅ Open Developer UI

---

## Manual Start (3 Commands)

```bash
# 1. Go to genkit directory
cd genkit

# 2. Install dependencies (first time only)
npm install

# 3. Start server
npm run dev
```

**Done!** Server runs at:
- API: http://localhost:3400
- Developer UI: http://localhost:4000

---

## First Time Setup

### 1. Get Google AI API Key
1. Go to: https://makersuite.google.com/app/apikey
2. Click "Create API Key"
3. Copy the key

### 2. Add to .env File
```bash
cd genkit
nano .env
```

Paste your key:
```env
GOOGLE_AI_API_KEY=your_actual_key_here
FIREBASE_PROJECT_ID=your_firebase_project
```

Save and exit (Ctrl+X, then Y, then Enter)

### 3. Start Server
```bash
npm run dev
```

---

## Test It Works

### Test in Browser
1. Open: http://localhost:4000
2. Click "bibleChat" flow
3. Input:
```json
{
  "message": "What does John 3:16 mean?",
  "history": []
}
```
4. Click "Run"
5. See AI response! ✨

### Test from iOS App
1. Make sure Genkit is running (`npm run dev`)
2. Run your iOS app in Xcode
3. Open Berean AI Assistant
4. Type: "Explain John 3:16"
5. Get instant AI response!

---

## Common Commands

```bash
# Start development server
npm run dev

# Start on different port
npm run dev -- --port 3500

# Check if server is running
curl http://localhost:3400/health

# View logs
npm run dev --verbose

# Stop server
Press Ctrl+C
```

---

## Deploy to Production

```bash
# Deploy to Cloud Run
genkit deploy --project YOUR_FIREBASE_PROJECT_ID

# You'll get a URL like:
# https://berean-genkit-xxxxx.run.app
```

Then update your iOS app's `Info.plist`:
```xml
<key>GENKIT_ENDPOINT</key>
<string>https://berean-genkit-xxxxx.run.app</string>
```

---

## Troubleshooting

### "Port already in use"
```bash
# Kill process on port 3400
lsof -ti:3400 | xargs kill -9

# Then restart
npm run dev
```

### "Module not found"
```bash
# Reinstall dependencies
rm -rf node_modules package-lock.json
npm install
```

### "Invalid API key"
```bash
# Check your .env file
cat .env

# Make sure GOOGLE_AI_API_KEY is set correctly
```

### "Cannot connect from iOS"
```bash
# Use your Mac's IP instead of localhost
# Find IP:
ifconfig | grep "inet "

# In iOS Info.plist:
# <string>http://YOUR_IP:3400</string>
```

---

## 📁 File Structure

```
genkit/
├── src/
│   └── berean-flows.ts    # Your AI flows
├── package.json            # Dependencies
├── .env                    # Your API keys (local only)
├── .env.example            # Template
└── README.md               # This file
```

---

## 🎯 What's Running

When you run `npm run dev`:

1. **Genkit Server** (Port 3400)
   - Hosts your AI flows
   - Accepts requests from iOS app
   - Streams responses

2. **Developer UI** (Port 4000)
   - Visual flow testing
   - Debug traces
   - Performance monitoring

---

## 📚 Full Documentation

For detailed guides, see:
- `GENKIT_HOSTING_PRODUCTION_GUIDE.md` - Complete production guide
- `genkitREADME.md` - Full setup instructions
- `GENKIT_INTEGRATION_GUIDE.md` - Integration details

---

## ✅ Quick Checklist

- [ ] Node.js 20+ installed
- [ ] Genkit folder exists
- [ ] `.env` file created with API key
- [ ] `npm install` completed
- [ ] `npm run dev` works
- [ ] http://localhost:4000 opens
- [ ] iOS app can connect

**All set?** You're ready to develop! 🎉

---

## 💡 Pro Tips

**Keep It Running:**
```bash
# Use tmux to keep server running
tmux new -s genkit
cd genkit && npm run dev
# Detach: Ctrl+B then D
# Reattach: tmux attach -t genkit
```

**Auto-restart:**
The dev server automatically reloads when you save files!

**Debug Mode:**
```bash
GENKIT_LOG_LEVEL=debug npm run dev
```

---

**Need help?** Check `GENKIT_HOSTING_PRODUCTION_GUIDE.md` for detailed troubleshooting!
