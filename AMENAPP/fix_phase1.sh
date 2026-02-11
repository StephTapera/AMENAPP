#!/bin/bash

# Phase 1 Auto-Fix Script
# This script automatically fixes all Phase 1 integration issues

echo "🚀 Starting Phase 1 Auto-Fix..."
echo ""

# Get the script's directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"

echo "📁 Project directory: $PROJECT_DIR"
echo ""

# ============================================================================
# Step 1: Fix Cloud Functions
# ============================================================================

echo "📝 Step 1: Fixing Cloud Functions..."

cd "$PROJECT_DIR/functions" || exit 1

# Backup existing files
echo "   📦 Creating backups..."
cp index.js index.js.backup 2>/dev/null || true
cp pushNotifications.js pushNotifications.js.backup 2>/dev/null || true

# Create fixed index.js
echo "   ✍️  Creating fixed index.js..."
cat > index.js << 'EOF'
/**
 * Firebase Cloud Functions for AMENAPP
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Initialize Firebase Admin
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// Import push notification functions
const {
  processFCMQueue,
} = require("./pushNotifications");

// Export functions
exports.processFCMQueue = processFCMQueue;

console.log("🚀 Cloud Functions initialized");
EOF

# Create fixed pushNotifications.js
echo "   ✍️  Creating fixed pushNotifications.js..."
cat > pushNotifications.js << 'EOF'
/**
 * Push Notification Cloud Functions
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

const db = admin.firestore();
const messaging = admin.messaging();

/**
 * Process FCM Queue - Send push notifications
 * @param {Object} snap - Firestore document snapshot
 * @param {Object} context - Function context
 * @return {Promise<void>}
 */
exports.processFCMQueue = functions.firestore
    .document("fcmQueue/{queueId}")
    .onCreate(async (snap, context) => {
      const notification = snap.data();

      console.log("📬 Processing notification:", notification);

      try {
        // Get recipient's FCM token
        const userDoc = await db
            .collection("users")
            .doc(notification.recipientId)
            .get();

        if (!userDoc.exists) {
          console.error(
              "❌ Recipient not found:",
              notification.recipientId,
          );
          await snap.ref.update({
            status: "failed",
            error: "User not found",
          });
          return;
        }

        const fcmToken = userDoc.data().fcmToken;

        if (!fcmToken) {
          console.log(
              "⚠️ No FCM token:",
              notification.recipientId,
          );
          await snap.ref.update({status: "no_token"});
          return;
        }

        // Build notification payload
        const message = {
          notification: {
            title: notification.title,
            body: notification.body,
          },
          data: {
            conversationId: notification.conversationId,
            messageId: notification.messageId || "",
            type: notification.type,
            senderId: notification.senderId,
          },
          token: fcmToken,
        };

        // Send notification
        const response = await messaging.send(message);
        console.log("✅ Notification sent:", response);

        // Update queue status
        await snap.ref.update({
          status: "sent",
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          response: response,
        });
      } catch (error) {
        console.error("❌ Error sending notification:", error);
        await snap.ref.update({
          status: "failed",
          error: error.message,
        });
      }
    });
EOF

echo "   ✅ Cloud Functions files created"

# Verify linting
echo "   🔍 Running linting check..."
npm run lint

if [ $? -eq 0 ]; then
    echo "   ✅ Linting passed!"
else
    echo "   ⚠️  Linting has errors, but continuing..."
fi

# Go back to project root
cd "$PROJECT_DIR"

echo ""
echo "✅ Step 1 Complete: Cloud Functions fixed"
echo ""

# ============================================================================
# Step 2: Show Xcode Fix Instructions
# ============================================================================

echo "📝 Step 2: Xcode Fixes Required"
echo ""
echo "⚠️  Please do these manually in Xcode:"
echo ""
echo "1. DELETE 'PushNotificationManager 2.swift':"
echo "   - Find it in Project Navigator"
echo "   - Right-click → Delete → Move to Trash"
echo ""
echo "2. VERIFY only ONE PushNotificationManager.swift exists"
echo ""
echo "3. BUILD the project (⌘B)"
echo ""

# ============================================================================
# Step 3: Deploy Cloud Functions
# ============================================================================

echo "📝 Step 3: Ready to Deploy Cloud Functions"
echo ""
read -p "Deploy Cloud Functions now? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Deploying Cloud Functions..."
    firebase deploy --only functions
    
    if [ $? -eq 0 ]; then
        echo "✅ Cloud Functions deployed successfully!"
    else
        echo "❌ Deployment failed. Check the errors above."
        exit 1
    fi
else
    echo "⏭️  Skipping deployment. Run manually later with:"
    echo "   firebase deploy --only functions"
fi

echo ""
echo "============================================"
echo "✅ Phase 1 Auto-Fix Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "1. Fix Xcode errors (delete PushNotificationManager 2.swift)"
echo "2. Build in Xcode (⌘B)"
echo "3. Test on a real device"
echo ""
echo "📄 For detailed info, see:"
echo "   - STEP2_COMPLETE.md"
echo "   - QUICK_FIX_PHASE1.md"
echo "   - CLOUD_FUNCTIONS_FIXED.md"
echo ""
