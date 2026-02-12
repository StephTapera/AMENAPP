#!/bin/bash

# ============================================================================
# AMEN App - Complete Messaging System Deployment
# ============================================================================
# Deploys all messaging features including:
# - Message notifications
# - Comment notifications
# - Reply notifications
# - Firestore security rules (with group support)
#
# Prerequisites:
# - Firebase CLI installed
# - Logged in to Firebase
# - Project initialized
#
# Usage:
#   chmod +x deploy-messaging-system.sh
#   ./deploy-messaging-system.sh
# ============================================================================

set -e  # Exit on error

echo "🚀 AMEN App - Messaging System Deployment"
echo "=========================================="
echo ""

# Check Firebase CLI
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found"
    echo "Install: npm install -g firebase-tools"
    exit 1
fi

echo "✅ Firebase CLI found"
echo ""

# Navigate to project root
cd "$(dirname "$0")"
PROJECT_ROOT=$(pwd)
echo "📂 Project: $PROJECT_ROOT"
echo ""

# Step 1: Deploy Firestore Rules
echo "📋 Step 1/2: Deploying Firestore Rules..."
echo "----------------------------------------"
firebase deploy --only firestore:rules
echo ""
echo "✅ Firestore rules deployed"
echo ""

# Step 2: Deploy Cloud Functions
echo "☁️  Step 2/2: Deploying Cloud Functions..."
echo "----------------------------------------"
cd functions
npm install
cd "$PROJECT_ROOT"

firebase deploy --only functions:onMessageSent,functions:onRealtimeCommentCreate,functions:onRealtimeReplyCreate

echo ""
echo "=========================================="
echo "✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "📋 Deployed Components:"
echo "  ✓ Firestore Rules (with group support)"
echo "  ✓ onMessageSent - Message notifications"
echo "  ✓ onRealtimeCommentCreate - Comment notifications"
echo "  ✓ onRealtimeReplyCreate - Reply notifications"
echo ""
echo "🔍 Verify in Firebase Console:"
echo "  1. Functions → Check all 3 functions are active"
echo "  2. Firestore → Rules show latest version"
echo ""
echo "🧪 Test the features:"
echo "  • Send a message → Recipient gets notification"
echo "  • Send message request → Shows in Requests tab"
echo "  • Comment on post → Author gets notification"
echo "  • Create group chat → Works with 2+ members"
echo ""
echo "📊 Monitor logs:"
echo "  firebase functions:log"
echo ""
echo "✨ Ready for production!"
