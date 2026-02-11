#!/bin/bash

# 🎯 Deploy Firebase Realtime Database Rules
# This fixes the comments persistence issue

clear

cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   🔥 AMEN APP - DATABASE RULES FIX                       ║
║                                                           ║
║   Problem: Comments not persisting after app close       ║
║   Root Cause: Security rules blocking comment reads      ║
║   Solution: Fixed validation rules                       ║
║   Status: READY TO DEPLOY!                               ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF

echo ""
echo "This will deploy the fixed Firebase Realtime Database rules"
echo "that allow comments to persist and sync in real-time."
echo ""

# Check if Firebase CLI is available
if command -v firebase &> /dev/null; then
    echo "✅ Firebase CLI found"
    echo ""
    echo "🚀 Deploying database rules..."
    echo ""

    firebase deploy --only database

    if [ $? -eq 0 ]; then
        echo ""
        echo "╔═══════════════════════════════════════════════════════╗"
        echo "║                                                       ║"
        echo "║  ✅ ✅ ✅  DEPLOYMENT SUCCESSFUL!  ✅ ✅ ✅          ║"
        echo "║                                                       ║"
        echo "╚═══════════════════════════════════════════════════════╝"
        echo ""
        echo "🎉 Comments should now persist and sync in real-time!"
        echo ""
        echo "📱 Test it now:"
        echo "   1. Open your app"
        echo "   2. Add a comment to a post"
        echo "   3. Close and reopen the app"
        echo "   4. Comment should still be there! ✅"
        echo ""
        echo "🔍 Check the Firebase Console to verify:"
        echo "   https://console.firebase.google.com/project/amen-5e359/database/amen-5e359-default-rtdb/rules"
        echo ""
    else
        echo ""
        echo "❌ Deployment failed"
        echo ""
        echo "Try:"
        echo "  firebase login"
        echo "  firebase use --add"
        echo "  firebase deploy --only database"
        echo ""
    fi
else
    echo "⚠️  Firebase CLI not installed"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  OPTION 1: Install Firebase CLI (Recommended)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Install Node.js from: https://nodejs.org/"
    echo "2. Install Firebase CLI:"
    echo "   npm install -g firebase-tools"
    echo "3. Login to Firebase:"
    echo "   firebase login"
    echo "4. Run this script again:"
    echo "   ./deploy-database-rules.sh"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  OPTION 2: Manual Deployment (Quickest)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Open Firebase Console:"
    echo "   https://console.firebase.google.com/project/amen-5e359/database/amen-5e359-default-rtdb/rules"
    echo ""
    echo "2. Copy the rules from:"
    echo "   AMENAPP/database.rules.json"
    echo ""
    echo "3. Paste into the Firebase Console Rules editor"
    echo ""
    echo "4. Click 'Publish'"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi
