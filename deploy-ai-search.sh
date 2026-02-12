#!/bin/bash

# Deploy AI Resource Search - Cloud Function
# Date: February 11, 2026

echo "🚀 Deploying AI Resource Search..."
echo ""

cd "$(dirname "$0")"

echo "📍 Current directory: $(pwd)"
echo ""

# Deploy Cloud Function
echo "☁️  Deploying analyzeSearchIntent function..."
echo ""

firebase deploy --only functions:analyzeSearchIntent

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ AI Resource Search Deployed Successfully!"
    echo ""
    echo "📋 What's New:"
    echo "   • Natural language search in Resources tab"
    echo "   • Sparkles icon triggers AI analysis"
    echo "   • Results ranked by relevance"
    echo "   • Shows why each resource matches"
    echo ""
    echo "🧪 Test Now:"
    echo "   1. Go to Resources tab"
    echo "   2. Type: \"I'm feeling anxious\""
    echo "   3. Tap sparkles button (purple icon)"
    echo "   4. See AI-ranked results with reasons"
    echo ""
    echo "💡 Example Queries:"
    echo "   • \"depression help\""
    echo "   • \"crisis support\""
    echo "   • \"bible study resources\""
    echo "   • \"christian podcasts\""
    echo ""
    echo "📈 Monitor:"
    echo "   firebase functions:log --only analyzeSearchIntent --follow"
    echo ""
else
    echo ""
    echo "❌ Deployment failed!"
    echo ""
    echo "💡 Common fixes:"
    echo "   - Run: firebase login"
    echo "   - Check: firebase use amen-5e359"
    exit 1
fi
