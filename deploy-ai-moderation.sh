#!/bin/bash

# ============================================================================
# Deploy AI Moderation, Crisis Detection & Smart Notifications
# ============================================================================

echo "🚀 Deploying AI-powered moderation system..."
echo ""

# Navigate to functions directory
cd functions || exit 1

# Check if aiModeration.js exists
if [ ! -f "aiModeration.js" ]; then
    echo "❌ Error: aiModeration.js not found in functions/"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Update index.js to export AI moderation functions
echo "📝 Updating index.js..."

# Check if AI moderation exports already exist
if ! grep -q "aiModeration" index.js; then
    echo ""
    echo "// ============================================================================"
    echo "// AI MODERATION, CRISIS DETECTION & SMART NOTIFICATIONS"
    echo "// ============================================================================"
    echo "const aiModeration = require('./aiModeration');"
    echo ""
    echo "// Content Moderation"
    echo "exports.moderateContent = aiModeration.moderateContent;"
    echo ""
    echo "// Crisis Detection"
    echo "exports.detectCrisis = aiModeration.detectCrisis;"
    echo ""
    echo "// Smart Notifications"
    echo "exports.deliverBatchedNotifications = aiModeration.deliverBatchedNotifications;"
    echo ""

    # Backup existing index.js
    cp index.js index.js.backup

    # Append AI moderation exports to index.js
    cat >> index.js << 'EOF'

// ============================================================================
// AI MODERATION, CRISIS DETECTION & SMART NOTIFICATIONS
// ============================================================================
const aiModeration = require('./aiModeration');

// Content Moderation
exports.moderateContent = aiModeration.moderateContent;

// Crisis Detection
exports.detectCrisis = aiModeration.detectCrisis;

// Smart Notifications
exports.deliverBatchedNotifications = aiModeration.deliverBatchedNotifications;
EOF

    echo "✅ index.js updated"
else
    echo "✅ AI moderation exports already exist in index.js"
fi

echo ""
echo "🔥 Deploying to Firebase..."
echo ""

# Deploy Firestore rules first
cd ..
echo "📋 Deploying Firestore security rules..."
firebase deploy --only firestore:rules

# Deploy Cloud Functions
cd functions
echo ""
echo "⚙️ Deploying Cloud Functions..."
firebase deploy --only functions:moderateContent,functions:detectCrisis,functions:deliverBatchedNotifications

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Next steps:"
echo "1. Enable Firebase AI Logic extension in Firebase Console"
echo "2. Configure Vertex AI API credentials"
echo "3. Test content moderation by creating a post with profanity"
echo "4. Test crisis detection by creating a prayer with crisis keywords"
echo "5. Monitor Cloud Functions logs: firebase functions:log"
echo ""
echo "🛡️ AI Moderation is now LIVE! 🚀"
