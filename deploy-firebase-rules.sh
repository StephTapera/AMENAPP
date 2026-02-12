#!/bin/bash

# ✅ Firebase Rules Deployment Script
# Deploys both Firestore and Realtime Database rules

set -e  # Exit on error

echo "🚀 Starting Firebase Rules Deployment..."
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not installed"
    echo "Install with: npm install -g firebase-tools"
    exit 1
fi

echo "✅ Firebase CLI found"

# Check if logged in
echo "🔐 Checking Firebase login..."
if ! firebase projects:list &> /dev/null; then
    echo "❌ Not logged in to Firebase"
    echo "Run: firebase login"
    exit 1
fi

echo "✅ Firebase authenticated"

# Check current project
echo "📋 Current project:"
firebase use

echo ""
echo "📦 Deploying Realtime Database rules..."
firebase deploy --only database

echo ""
echo "📦 Deploying Firestore rules..."
firebase deploy --only firestore:rules

echo ""
echo "✅ Deployment complete!"
echo ""
echo "🔍 Verification:"
echo "1. Check Firebase Console → Realtime Database → Rules"
echo "2. Check Firebase Console → Firestore → Rules"
echo "3. Run app and verify no permission errors"
echo ""
echo "⚠️  IMPORTANT: Still need to register App Check manually:"
echo "   → https://console.firebase.google.com/project/amen-5e359/appcheck"
echo "   → Register iOS app: 1:78278013543:ios:248f404eb1ec902f545ac2"
echo "   → Enable DeviceCheck provider"
echo ""
