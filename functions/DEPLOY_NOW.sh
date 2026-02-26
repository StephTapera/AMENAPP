#!/bin/bash
# AMEN App - Production Deployment Script
# Run this after installing Firebase CLI: npm install -g firebase-tools

set -e  # Exit on error

echo "🚀 AMEN App - Deploying Critical Fixes"
echo "========================================"
echo ""

# 1. Deploy Firestore Indexes (CRITICAL - Badge performance)
echo "📊 Step 1/2: Deploying Firestore indexes..."
firebase deploy --only firestore:indexes
echo "✅ Indexes deployed!"
echo ""

# 2. Deploy AI Search Function (CRITICAL - AI search broken)
echo "🤖 Step 2/2: Deploying AI search Cloud Function..."
firebase deploy --only functions:analyzeSearchIntent
echo "✅ AI search function deployed!"
echo ""

echo "🎉 Deployment Complete!"
echo ""
echo "⚠️  MANUAL STEPS STILL REQUIRED:"
echo "1. Enable Vertex AI API (1 min):"
echo "   https://console.cloud.google.com/apis/library/aiplatform.googleapis.com?project=amen-5e359"
echo ""
echo "2. Open Xcode and remove duplicate file references (3 min):"
echo "   - Look for RED files in Project Navigator"
echo "   - Select all red files → Right-click → Delete → Remove References"
echo "   - Clean Build Folder (⇧⌘K)"
echo ""
echo "✅ COMPLETED FIXES:"
echo "   • Info.plist - Added NSContactsUsageDescription (prevents crash)"
echo "   • firestore.indexes.json - Added prayer index (3 indexes total)"
echo "   • Shabbat Mode - Fully implemented with smart icon"
echo ""
