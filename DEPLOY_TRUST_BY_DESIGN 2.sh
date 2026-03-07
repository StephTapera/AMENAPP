#!/bin/bash
# AMEN App - Trust-by-Design Privacy Controls Deployment
# Deploy privacy & contact controls, firestore rules, and indexes

set -e  # Exit on error

echo "🔒 AMEN App - Deploying Trust-by-Design Privacy Controls"
echo "==========================================================="
echo ""

# Check if firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found!"
    echo "Install it with: npm install -g firebase-tools"
    exit 1
fi

echo "📋 What will be deployed:"
echo "  • Updated Firestore security rules (firestore 18.rules)"
echo "  • New Firestore indexes for privacy collections"
echo "  • Privacy & Contact Controls features:"
echo "    - DM permissions (Everyone/Followers/Mutuals/Nobody)"
echo "    - Message request inbox with safety filters"
echo "    - Comment/reply interaction controls"
echo "    - Quiet block tools (Block/Mute/Restrict/Hide/Limit)"
echo "    - Anti-harassment repeat detection"
echo ""

read -p "Continue with deployment? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

# 1. Deploy Firestore Indexes
echo "📊 Step 1/2: Deploying Firestore indexes..."
firebase deploy --only firestore:indexes
echo "✅ Indexes deployed!"
echo ""

# 2. Deploy Firestore Rules
echo "🛡️  Step 2/2: Deploying Firestore security rules..."
# Copy firestore 18.rules to firestore.rules (the file Firebase expects)
cp "AMENAPP/firestore 18.rules" firestore.rules
firebase deploy --only firestore:rules
echo "✅ Security rules deployed!"
echo ""

echo "✅ DEPLOYMENT COMPLETE!"
echo ""
echo "📋 What was deployed:"
echo "   • Firestore indexes for:"
echo "     - user_privacy_settings"
echo "     - quiet_blocks"
echo "     - repeated_contact_attempts"
echo "   • Security rules for privacy collections"
echo ""
echo "🧪 Testing Checklist:"
echo "   1. Open Privacy & Contact in Account Settings"
echo "   2. Configure DM permissions (try Mutuals Only)"
echo "   3. Test Message Requests inbox"
echo "   4. Create a post and set Comment Controls"
echo "   5. Open a user profile and try Quiet Block Actions"
echo "   6. Verify permissions are enforced (try messaging as non-mutual)"
echo ""
echo "📊 Firebase Console Links:"
echo "   • Firestore indexes: https://console.firebase.google.com/project/amen-5e359/firestore/indexes"
echo "   • Security rules: https://console.firebase.google.com/project/amen-5e359/firestore/rules"
echo ""
