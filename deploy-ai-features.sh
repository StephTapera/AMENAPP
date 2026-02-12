#!/bin/bash

# Deploy AI Features - Church Notes, Scripture, and Church Recommendations
# Date: February 11, 2026

echo "🚀 Deploying AI Features (Notes, Scripture, Church Recommendations)..."
echo ""

cd "$(dirname "$0")"

echo "📍 Current directory: $(pwd)"
echo ""

# Deploy Cloud Functions
echo "☁️  Deploying AI Cloud Functions..."
echo ""

firebase deploy --only functions:summarizeChurchNote,functions:findRelatedScripture,functions:recommendChurches

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ AI Features Deployed Successfully!"
    echo ""
    echo "📋 What's New:"
    echo ""
    echo "🎯 AI Note Summarization:"
    echo "   • Auto-generates summaries of sermon notes"
    echo "   • Extracts main theme, scripture, key points, action steps"
    echo "   • Cost: ~\$0.001/note"
    echo ""
    echo "📖 AI Scripture Cross-References:"
    echo "   • Suggests related verses when typing references"
    echo "   • Real-time as you type 'John 3:16'"
    echo "   • Cost: ~\$0.0005/lookup"
    echo ""
    echo "⛪ AI Church Recommendations:"
    echo "   • Personalized recommendations based on profile"
    echo "   • Analyzes prayers, posts, interests"
    echo "   • Cost: ~\$0.002/recommendation set"
    echo ""
    echo "🧪 Test Now:"
    echo ""
    echo "   Church Notes:"
    echo "   1. Create a note with sermon content"
    echo "   2. Tap 'Generate Summary' button"
    echo "   3. See AI-generated summary appear"
    echo ""
    echo "   Scripture Cross-References:"
    echo "   1. Type a verse reference (e.g., 'John 3:16')"
    echo "   2. See related verses suggestion card"
    echo "   3. Tap to add references to note"
    echo ""
    echo "   Church Recommendations:"
    echo "   1. Go to Find Church view"
    echo "   2. Tap 'Get AI Recommendations'"
    echo "   3. See personalized church rankings with match scores"
    echo ""
    echo "📈 Monitor All Functions:"
    echo "   firebase functions:log --follow"
    echo ""
    echo "📊 Expected Costs:"
    echo "   • 10K note summaries/month: ~\$10"
    echo "   • 20K scripture lookups/month: ~\$10"
    echo "   • 5K church recommendations/month: ~\$10"
    echo "   Total: ~\$30/month for moderate usage"
    echo ""
else
    echo ""
    echo "❌ Deployment failed!"
    echo ""
    echo "💡 Common fixes:"
    echo "   - Run: firebase login"
    echo "   - Check: firebase use amen-5e359"
    echo "   - Verify functions/aiModeration.js has new functions"
    exit 1
fi
