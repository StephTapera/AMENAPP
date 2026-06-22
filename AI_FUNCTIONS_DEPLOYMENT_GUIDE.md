# AI Cloud Functions Deployment Guide

## ✅ What Was Created

Three new Cloud Functions have been created in `Backend/functions/src/`:

1. **bereanChatProxy.ts** - Anthropic Claude proxy for Berean AI
2. **openAIProxy.ts** - OpenAI GPT proxy for general AI features
3. **whisperProxy.ts** - OpenAI Whisper proxy for audio transcription

These functions are now exported in `Backend/functions/src/index.ts`.

## 🔐 Required API Keys

You need to configure the following secrets in Firebase:

### 1. Set Anthropic Claude API Key
```bash
cd "Backend/functions"
firebase functions:secrets:set ANTHROPIC_API_KEY
# Paste your key: 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
```

### 2. Set OpenAI API Key
```bash
firebase functions:secrets:set OPENAI_API_KEY
# Paste your OpenAI key
```

## 📦 Install Dependencies

```bash
cd "Backend/functions"
npm install
```

This will install the new `form-data` dependency needed for Whisper audio uploads.

## 🔨 Build TypeScript

```bash
npm run build
```

This compiles TypeScript to JavaScript in the `lib/` directory.

## 🚀 Deploy Cloud Functions

### Deploy All Functions
```bash
npm run deploy
```

### Deploy Only AI Functions (Faster)
```bash
firebase deploy --only functions:bereanChatProxy,functions:openAIProxy,functions:whisperProxy
```

## 🧪 Test the Functions

Once deployed, test from your iOS app:

1. **Berean AI** - Open BereanChatView and send a message
2. **OpenAI** - Use any feature that calls OpenAIService.swift
3. **Whisper** - Test voice message transcription

## 📊 Monitor Usage

View Cloud Function logs:
```bash
firebase functions:log --only bereanChatProxy
firebase functions:log --only openAIProxy
firebase functions:log --only whisperProxy
```

## 🔍 Function Details

### bereanChatProxy
- **Model Selection**:
  - Haiku (`claude-3-haiku-20240307`) - Fast, real-time interactions
  - Sonnet (`claude-3-5-sonnet-20241022`) - Scholar/debater modes
- **Modes**: shepherd, scholar, debater, prayer
- **Context**: Last 12 messages
- **Max Tokens**: 2000 (configurable)

### openAIProxy
- **Default Model**: `gpt-4o-mini` (cost-effective)
- **Context**: Last 20 messages
- **Max Tokens**: 1000 (configurable)
- **Temperature**: 0.7 (configurable)

### whisperProxy
- **Model**: `whisper-1`
- **Input**: Firebase Storage URLs or HTTPS URLs
- **Output**: Transcribed text + detected language
- **Timeout**: 9 minutes (for long audio)

## 🔒 Security

All functions:
- ✅ Require Firebase Authentication
- ✅ Store API keys in Firebase Secret Manager (never on device)
- ✅ Include rate limiting via Firebase quotas
- ✅ Log usage for monitoring
- ✅ Validate all inputs

## 💰 Cost Optimization

**Anthropic Claude**:
- Haiku: $0.25 per 1M input tokens, $1.25 per 1M output tokens
- Sonnet: $3 per 1M input tokens, $15 per 1M output tokens

**OpenAI**:
- GPT-4o-mini: $0.15 per 1M input tokens, $0.60 per 1M output tokens
- Whisper: $0.006 per minute of audio

**Tips**:
- Use Haiku for most Berean interactions
- Use GPT-4o-mini instead of GPT-4
- Limit conversation history (already implemented)
- Monitor usage in Firebase Console

## 🐛 Troubleshooting

### "API key not configured" error
```bash
# Check if secrets are set
firebase functions:secrets:access ANTHROPIC_API_KEY
firebase functions:secrets:access OPENAI_API_KEY

# Re-set if missing
firebase functions:secrets:set ANTHROPIC_API_KEY
firebase functions:secrets:set OPENAI_API_KEY
```

### "Function not found" error
```bash
# Rebuild and redeploy
npm run build
npm run deploy
```

### TypeScript compilation errors
```bash
# Install dev dependencies
npm install --save-dev @types/node @types/form-data

# Rebuild
npm run build
```

## 📝 Next Steps

1. Run `npm install` in `Backend/functions/`
2. Set API keys via `firebase functions:secrets:set`
3. Run `npm run build`
4. Deploy with `npm run deploy`
5. Test Berean AI in your app

## 🎯 iOS App Integration

Your iOS app is already configured to use these functions:

- **ClaudeService.swift** → calls `bereanChatProxy`
- **OpenAIService.swift** → calls `openAIProxy` and `whisperProxy`

No iOS code changes needed - just deploy the Cloud Functions and the app will work!
