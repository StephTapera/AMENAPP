#!/bin/bash

# Deploy Vertex AI Moderation - Quick Script
# Date: February 11, 2026

echo "🚀 Deploying Vertex AI Moderation..."
echo ""

# Navigate to project directory
cd "$(dirname "$0")"

echo "📍 Current directory: $(pwd)"
echo ""

# Step 1: Install dependencies
echo "📦 Step 1: Installing dependencies..."
cd functions
npm install

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ npm install failed!"
    echo "💡 Make sure Node.js and npm are installed"
    exit 1
fi

echo ""
echo "✅ Dependencies installed"
echo ""

# Step 2: Verify Vertex AI package
echo "🔍 Step 2: Verifying @google-cloud/vertexai..."
npm list @google-cloud/vertexai

if [ $? -ne 0 ]; then
    echo ""
    echo "⚠️ Vertex AI package not found, installing manually..."
    npm install @google-cloud/vertexai
fi

echo ""
echo "✅ Vertex AI package verified"
echo ""

# Step 3: Go back to project root
cd ..

# Step 4: Deploy to Firebase
echo "☁️  Step 3: Deploying to Firebase..."
echo ""

firebase deploy --only functions:moderateContent

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Vertex AI Moderation Deployed Successfully!"
    echo ""
    echo "📋 Next Steps:"
    echo "   1. Test by posting a comment in your app"
    echo "   2. Check logs: firebase functions:log --only moderateContent --follow"
    echo "   3. Monitor Firebase Console: https://console.firebase.google.com/project/amen-5e359/functions"
    echo ""
    echo "🤖 Your moderation is now powered by Gemini AI!"
    echo ""
else
    echo ""
    echo "❌ Deployment failed!"
    echo ""
    echo "💡 Common fixes:"
    echo "   - Run: firebase login"
    echo "   - Check: firebase use amen-5e359"
    echo "   - Verify Vertex AI API is enabled in Google Cloud Console"
    exit 1
fi
