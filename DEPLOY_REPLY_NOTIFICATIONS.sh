#!/bin/bash

# Deploy Reply Notifications - Cloud Functions
# Date: February 11, 2026

echo "🚀 Deploying Reply Notifications to Firebase..."
echo ""

# Navigate to project directory
cd "$(dirname "$0")"

echo "📍 Current directory: $(pwd)"
echo ""

# Check if firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Install it with:"
    echo "   npm install -g firebase-tools"
    exit 1
fi

# Check if logged in to Firebase
echo "🔑 Checking Firebase authentication..."
firebase login:list
echo ""

# Deploy Cloud Functions
echo "☁️  Deploying Cloud Functions (this will take ~2-5 minutes)..."
echo ""

firebase deploy --only functions

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Reply Notifications Deployed Successfully!"
    echo ""
    echo "📋 Next Steps:"
    echo "   1. Test reply notifications:"
    echo "      - User A comments on a post"
    echo "      - User B replies to User A's comment"
    echo "      - User A should receive notification"
    echo ""
    echo "   2. Check Firebase Console:"
    echo "      - Go to Functions → Logs"
    echo "      - Look for 'onRealtimeReplyCreate' logs"
    echo "      - Verify notifications are created"
    echo ""
    echo "   3. Monitor badge counts and deep linking"
    echo ""
else
    echo ""
    echo "❌ Deployment failed. Check the error messages above."
    echo ""
    echo "💡 Common issues:"
    echo "   - Not logged in: Run 'firebase login'"
    echo "   - Wrong project: Run 'firebase use <project-id>'"
    echo "   - Missing dependencies: Run 'cd functions && npm install'"
    exit 1
fi
