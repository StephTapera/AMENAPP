#!/bin/bash

# ============================================================================
# AMEN App - Comment Notifications Deployment Script
# ============================================================================
# This script deploys the Real-time Database Cloud Functions for comment
# notifications to Firebase.
#
# What it does:
# 1. Deploys onRealtimeCommentCreate function (for top-level comments)
# 2. Deploys onRealtimeReplyCreate function (for replies)
# 3. Verifies deployment status
#
# Prerequisites:
# - Firebase CLI installed (npm install -g firebase-tools)
# - Logged in to Firebase (firebase login)
# - Project initialized (firebase init)
#
# Usage:
#   chmod +x deploy-comment-notifications.sh
#   ./deploy-comment-notifications.sh
# ============================================================================

set -e  # Exit on error

echo "🚀 Starting Comment Notifications Deployment"
echo "=============================================="
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI is not installed"
    echo "Install it with: npm install -g firebase-tools"
    exit 1
fi

echo "✅ Firebase CLI found"
echo ""

# Navigate to project root
cd "$(dirname "$0")"
PROJECT_ROOT=$(pwd)
echo "📂 Project root: $PROJECT_ROOT"
echo ""

# Check if functions directory exists
if [ ! -d "functions" ]; then
    echo "❌ Functions directory not found"
    exit 1
fi

echo "✅ Functions directory found"
echo ""

# Navigate to functions directory
cd functions

echo "📦 Installing dependencies..."
npm install
echo ""

# Navigate back to project root
cd "$PROJECT_ROOT"

echo "🔧 Deploying Cloud Functions..."
echo ""

# Deploy only the comment notification functions
firebase deploy --only functions:onRealtimeCommentCreate,functions:onRealtimeReplyCreate

echo ""
echo "=============================================="
echo "✅ Deployment Complete!"
echo "=============================================="
echo ""
echo "📋 Summary:"
echo "  ✓ onRealtimeCommentCreate - Triggers on new top-level comments"
echo "  ✓ onRealtimeReplyCreate - Triggers on new replies"
echo ""
echo "🔍 Verify deployment:"
echo "  1. Go to Firebase Console → Functions"
echo "  2. Look for onRealtimeCommentCreate and onRealtimeReplyCreate"
echo "  3. Check that both functions are active"
echo ""
echo "🧪 Test the functions:"
echo "  1. Open the AMEN app"
echo "  2. Comment on someone else's post"
echo "  3. Check that they receive a notification"
echo "  4. Reply to someone else's comment"
echo "  5. Check that they receive a reply notification"
echo ""
echo "📊 Monitor function logs:"
echo "  firebase functions:log --only onRealtimeCommentCreate,onRealtimeReplyCreate"
echo ""
