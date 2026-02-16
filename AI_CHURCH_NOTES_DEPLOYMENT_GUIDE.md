# AI Church Notes Deployment Guide

## Overview

This guide walks you through deploying the AI Church Notes features:
- **Scripture Cross-References**: Automatically find related Bible verses
- **Note Summarization**: AI-powered summaries of sermon notes

## Files Created

### Cloud Functions
1. **`functions/aiChurchNotes.js`** - New Cloud Functions for AI features
   - `findScriptureReferences` - Process scripture reference requests
   - `summarizeNote` - Process note summarization requests

2. **`functions/index.js`** - Updated to export new functions

3. **`functions/package.json`** - Updated lint script

### Deployment Scripts
1. **`deploy-ai-church-notes.sh`** - Automated deployment script

### Documentation
1. **`AI_SERVICES_FIX_COMPLETE.md`** - Complete fix documentation
2. **This file** - Deployment guide

## Prerequisites

### 1. Install Node.js (if not already installed)

If `node --version` doesn't work in your terminal:

```bash
# Install Node.js via Homebrew (recommended)
brew install node

# OR download from: https://nodejs.org/
```

After installation, verify:
```bash
node --version  # Should show v18+ or v20+
npm --version   # Should show v9+ or v10+
```

### 2. Install Firebase CLI

```bash
# Install Firebase CLI globally
npm install -g firebase-tools

# Verify installation
firebase --version
```

### 3. Login to Firebase

```bash
firebase login
```

This will open a browser window to authenticate with your Google account.

## Deployment Steps

### Option 1: Quick Deploy (Automated)

Run the deployment script:

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
./deploy-ai-church-notes.sh
```

This script will:
1. Check prerequisites
2. Deploy only the new AI functions
3. Display success message with testing instructions

### Option 2: Manual Deploy

#### Step 1: Deploy Firestore Rules

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
firebase deploy --only firestore:rules --project amen-5e359
```

This deploys the updated rules that allow the AI service collections.

#### Step 2: Install Dependencies

```bash
cd functions
npm install
```

This ensures all packages (including @google-cloud/vertexai) are installed.

#### Step 3: Deploy Cloud Functions

```bash
# Deploy only the new AI functions
firebase deploy --only functions:findScriptureReferences,functions:summarizeNote --project amen-5e359

# OR deploy all functions
firebase deploy --only functions --project amen-5e359
```

## Verification

### Check Deployment Status

```bash
firebase functions:list --project amen-5e359
```

You should see:
- ✅ `findScriptureReferences(us-central1)`
- ✅ `summarizeNote(us-central1)`

### View Logs

```bash
# Real-time logs
firebase functions:log --project amen-5e359

# Filter for AI functions
firebase functions:log --only findScriptureReferences,summarizeNote --project amen-5e359
```

## Testing

### Test Scripture References

1. Open the app in Xcode
2. Navigate to Church Notes
3. Create a new note with a scripture reference (e.g., "Romans 12:1")
4. The AI should automatically find related verses
5. Check console logs for:
   ```
   📖 [AI SCRIPTURE] Finding related verses for: Romans 12:1
   📤 [AI SCRIPTURE] Sending request to Cloud Function...
   ✅ [AI SCRIPTURE] Found 5 related verses
   ```

### Test Note Summarization

1. Create a church note with sermon content
2. Tap the "Generate Summary" button (if visible in UI)
3. Check console logs for:
   ```
   📝 [AI SUMMARY] Generating summary for note (1234 chars)
   📤 [AI SUMMARY] Sending request to Cloud Function...
   ✅ [AI SUMMARY] Summary generated: "God's grace and redemption"
   ```

## Troubleshooting

### Issue: "Command not found: firebase"

**Solution**: Install Firebase CLI:
```bash
npm install -g firebase-tools
```

If you get permission errors:
```bash
sudo npm install -g firebase-tools
```

### Issue: "Command not found: node"

**Solution**: Install Node.js:
```bash
# Via Homebrew
brew install node

# Or download from https://nodejs.org/
```

### Issue: "Permission denied"

**Solution**: Login to Firebase:
```bash
firebase login
```

### Issue: Functions deploy but timeout

**Possible causes**:
1. Vertex AI API not enabled
2. Service account permissions missing
3. Cloud Functions quota exceeded

**Solution**: Check Firebase Console → Functions for error messages

### Issue: AI responses not appearing in app

**Check**:
1. Firestore rules deployed: `firebase deploy --only firestore:rules`
2. Cloud Functions deployed: `firebase functions:list`
3. Console logs show requests being sent
4. Check Firestore console for `scriptureReferenceResults` and `noteSummaryResults` collections

## Cost Estimation

### Vertex AI (Gemini 1.5 Flash)
- **Scripture References**: ~200 tokens/request × $0.000125/1K tokens = ~$0.000025 per request
- **Note Summaries**: ~500 tokens/request × $0.000125/1K tokens = ~$0.0000625 per request

**Estimated monthly cost** (assuming 1000 notes):
- Scripture refs: $0.025
- Summaries: $0.06
- **Total**: ~$0.10/month

### Cloud Functions
- Free tier: 2M invocations/month
- After free tier: $0.40 per million invocations

**Estimated monthly cost**: $0 (within free tier for most use cases)

## Monitoring

### View Function Metrics

1. Go to [Firebase Console](https://console.firebase.google.com/project/amen-5e359/functions)
2. Navigate to Functions
3. Click on function name to see:
   - Invocations
   - Execution time
   - Memory usage
   - Error rate

### Set Up Alerts

1. Firebase Console → Functions → Alerts
2. Create alert for:
   - High error rate
   - Slow execution time
   - High memory usage

## Next Steps

1. ✅ Deploy Firestore rules
2. ✅ Deploy Cloud Functions
3. ✅ Test in the app
4. Monitor performance and costs
5. Consider adding:
   - Caching layer for common verses
   - Rate limiting for AI requests
   - User feedback mechanism

## Support

If you encounter issues:

1. Check Firebase Console logs
2. Review `AI_SERVICES_FIX_COMPLETE.md`
3. Check Xcode console for client-side logs
4. Verify Firestore rules are deployed

## Quick Reference

### Deploy Everything
```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
firebase deploy --only firestore:rules,functions --project amen-5e359
```

### Deploy Just Functions
```bash
firebase deploy --only functions:findScriptureReferences,functions:summarizeNote --project amen-5e359
```

### View Logs
```bash
firebase functions:log --project amen-5e359
```

### List Functions
```bash
firebase functions:list --project amen-5e359
```
