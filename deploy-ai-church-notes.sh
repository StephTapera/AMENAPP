#!/bin/bash

# ============================================================================
# Deploy AI Church Notes Features
# - Scripture Cross-References
# - Note Summarization
# ============================================================================

echo "🚀 Deploying AI Church Notes Cloud Functions..."
echo ""

# Check if firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Install with: npm install -g firebase-tools"
    exit 1
fi

# Check if logged in
if ! firebase projects:list &> /dev/null; then
    echo "❌ Not logged in to Firebase. Run: firebase login"
    exit 1
fi

echo "📋 Deploying functions:"
echo "  - findScriptureReferences"
echo "  - summarizeNote"
echo ""

# Deploy only the new AI church notes functions
firebase deploy \
  --only functions:findScriptureReferences,functions:summarizeNote \
  --project amen-5e359

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ AI Church Notes functions deployed successfully!"
    echo ""
    echo "📖 Scripture References:"
    echo "   - Triggered on: scriptureReferenceRequests collection"
    echo "   - Results in: scriptureReferenceResults collection"
    echo ""
    echo "📝 Note Summarization:"
    echo "   - Triggered on: noteSummaryRequests collection"
    echo "   - Results in: noteSummaryResults collection"
    echo ""
    echo "🧪 Test the functions:"
    echo "   1. Create a church note in the app"
    echo "   2. Check console logs for AI processing"
    echo "   3. Verify results appear in the app"
    echo ""
else
    echo ""
    echo "❌ Deployment failed. Check errors above."
    exit 1
fi
