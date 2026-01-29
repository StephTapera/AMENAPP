# 📋 Copy-Paste Terminal Commands

## 🚀 Method 1: Automated Script (Recommended)

### Make script executable and run:
```bash
chmod +x start-genkit.sh
./start-genkit.sh
```

---

## 🔧 Method 2: Manual Commands

### First Time Setup:

```bash
# 1. Navigate to genkit directory
cd genkit

# 2. Install dependencies
npm install

# 3. Create .env file
cp .env.example .env

# 4. Edit .env and add your API key
nano .env
# Add: GOOGLE_AI_API_KEY=your_actual_key_here
# Save: Ctrl+X, then Y, then Enter

# 5. Install Genkit CLI globally (one time only)
npm install -g genkit
```

### Every Time You Start Development:

```bash
# 1. Go to genkit directory
cd genkit

# 2. Start server
npm run dev
```

**Done!** Server is now running.

---

## 🧪 Test Commands

### Test in Terminal:
```bash
# Health check
curl http://localhost:3400/health

# Test bibleChat flow
curl -X POST http://localhost:3400/bibleChat \
  -H "Content-Type: application/json" \
  -d '{"message": "What does John 3:16 mean?", "history": []}'
```

### Open Developer UI:
```bash
# In your browser
open http://localhost:4000
```

---

## 🚀 Deploy to Production

```bash
# Login to Google Cloud
gcloud auth login

# Set your project
gcloud config set project YOUR_FIREBASE_PROJECT_ID

# Deploy to Cloud Run
genkit deploy --project YOUR_FIREBASE_PROJECT_ID
```

After deployment, you'll get a URL like:
```
https://berean-genkit-xxxxx.run.app
```

Update your iOS `Info.plist`:
```xml
<key>GENKIT_ENDPOINT</key>
<string>https://berean-genkit-xxxxx.run.app</string>
```

---

## 🛑 Stop Server

```bash
# Press Ctrl+C in the terminal where server is running
```

---

## 🔄 Restart Server

```bash
# Stop with Ctrl+C, then:
npm run dev
```

---

## 🐛 Troubleshooting Commands

### Port already in use:
```bash
# Kill process on port 3400
lsof -ti:3400 | xargs kill -9

# Kill process on port 4000
lsof -ti:4000 | xargs kill -9

# Then restart
npm run dev
```

### Reinstall everything:
```bash
cd genkit
rm -rf node_modules package-lock.json
npm install
npm run dev
```

### Check if API key is set:
```bash
cd genkit
cat .env | grep GOOGLE_AI_API_KEY
```

### Find your Mac's IP (for iOS testing):
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

### View npm logs:
```bash
npm run dev --verbose
```

---

## 📱 iOS App Configuration

### Local Development (Info.plist):
```xml
<key>GENKIT_ENDPOINT</key>
<string>http://localhost:3400</string>
```

### If iOS can't connect to localhost, use your Mac's IP:
```xml
<key>GENKIT_ENDPOINT</key>
<string>http://YOUR_MAC_IP:3400</string>
```

### Production (Info.plist):
```xml
<key>GENKIT_ENDPOINT</key>
<string>https://berean-genkit-xxxxx.run.app</string>
```

---

## 🎯 Quick Reference

| Command | Purpose |
|---------|---------|
| `npm run dev` | Start development server |
| `npm run build` | Build for production |
| `npm test` | Run tests |
| `genkit deploy` | Deploy to Cloud Run |
| `Ctrl+C` | Stop server |

| URL | Purpose |
|-----|---------|
| `http://localhost:3400` | API endpoint |
| `http://localhost:4000` | Developer UI |

---

## 📂 Where to Run Commands

All commands should be run from the `genkit` directory:

```bash
cd /path/to/your/AMENAPP/genkit
```

Or use the automated script from project root:

```bash
cd /path/to/your/AMENAPP
./start-genkit.sh
```

---

## ✅ Complete Workflow

### Development Session:
```bash
# Terminal 1: Start Genkit
cd genkit
npm run dev

# Terminal 2: Run iOS app (in Xcode)
# Press Cmd+R

# Test in app
# Open Berean AI → Type message → Get response
```

### Deploy Update:
```bash
# 1. Stop local server (Ctrl+C)

# 2. Deploy to production
genkit deploy --project YOUR_PROJECT_ID

# 3. Update iOS Info.plist with new URL (if changed)

# 4. Restart local dev server
npm run dev
```

---

## 🎉 You're Ready!

**Start now:**
```bash
cd genkit
npm run dev
```

Then open: http://localhost:4000 and test your flows! 🚀
