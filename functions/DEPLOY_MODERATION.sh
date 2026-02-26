#!/bin/bash
# AMEN App - Content Moderation System Deployment
# Run this to deploy the organic content integrity + moderation system

set -e  # Exit on error

echo "🛡️  AMEN App - Deploying Content Moderation System"
echo "==================================================="
echo ""

# Check if firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found!"
    echo "Install it with: npm install -g firebase-tools"
    exit 1
fi

# 1. Install dependencies
echo "📦 Step 1/4: Installing npm dependencies..."
npm install
echo "✅ Dependencies installed!"
echo ""

# 2. Deploy Firestore Indexes
echo "📊 Step 2/4: Deploying Firestore indexes..."
cd ..
firebase deploy --only firestore:indexes
echo "✅ Indexes deployed!"
echo ""

# 3. Deploy Cloud Functions
echo "🚀 Step 3/4: Deploying moderateContent Cloud Function..."
firebase deploy --only functions:moderateContent
echo "✅ Function deployed!"
echo ""

# 4. Enable required APIs
echo "🔑 Step 4/4: Manual API enablement required..."
echo ""
echo "⚠️  MANUAL STEPS - Complete these now:"
echo ""
echo "1. Enable Google Cloud Natural Language API:"
echo "   https://console.cloud.google.com/apis/library/language.googleapis.com?project=amen-5e359"
echo ""
echo "2. View deployed function:"
echo "   https://console.firebase.google.com/project/amen-5e359/functions"
echo ""
echo "3. Create Firestore indexes (if deployment didn't auto-create):"
echo "   https://console.firebase.google.com/project/amen-5e359/firestore/indexes"
echo ""
echo "✅ DEPLOYMENT COMPLETE!"
echo ""
echo "📋 What was deployed:"
echo "   • ContentIntegrityPolicy.swift - Graduated enforcement ladder"
echo "   • ContentIntegrityComposer.swift - Client-side tracking"
echo "   • ContentModerationService.swift - Swift API client"
echo "   • functions/contentModeration.js - Backend moderation pipeline"
echo "   • Firestore indexes for moderation collections"
echo ""
echo "🧪 Testing:"
echo "   1. Create a post with pasted AI-generated text"
echo "   2. Should see 'Consider adding your own reflection' nudge"
echo "   3. Check Firebase Console > Functions > Logs for moderation events"
echo ""
