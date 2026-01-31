#!/bin/bash

# 🚀 AMENAPP Firebase Cloud Functions Setup Script
# This script automates the setup of Firebase Cloud Functions

echo "🔥 AMENAPP Firebase Cloud Functions Setup"
echo "=========================================="
echo ""

# Check if Firebase CLI is installed
echo "📋 Checking prerequisites..."
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found!"
    echo "Installing Firebase CLI..."
    npm install -g firebase-tools
else
    echo "✅ Firebase CLI installed: $(firebase --version)"
fi

echo ""

# Login to Firebase
echo "🔐 Logging in to Firebase..."
firebase login

echo ""

# Check if already initialized
if [ -d "functions" ]; then
    echo "⚠️  Functions directory already exists!"
    read -p "Do you want to overwrite? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Setup cancelled"
        exit 1
    fi
    rm -rf functions
fi

echo "📁 Initializing Firebase Functions..."

# Create functions directory
mkdir -p functions
cd functions

# Initialize package.json
cat > package.json <<EOF
{
  "name": "amenapp-functions",
  "description": "Cloud Functions for AMENAPP",
  "scripts": {
    "serve": "firebase emulators:start --only functions",
    "shell": "firebase functions:shell",
    "start": "npm run shell",
    "deploy": "firebase deploy --only functions",
    "logs": "firebase functions:log"
  },
  "engines": {
    "node": "16"
  },
  "main": "index.js",
  "dependencies": {
    "firebase-admin": "^11.8.0",
    "firebase-functions": "^4.3.1"
  },
  "devDependencies": {
    "firebase-functions-test": "^3.1.0"
  },
  "private": true
}
EOF

echo "✅ package.json created"

# Install dependencies
echo "📦 Installing dependencies..."
npm install

echo "✅ Dependencies installed"

# Download the full Cloud Functions code
echo "📝 Creating index.js with all notification functions..."

# Create index.js (content is in the deployment guide)
cat > index.js <<'EOF'
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ========================================
// 1. FOLLOW NOTIFICATIONS
// ========================================

exports.sendFollowNotification = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const notification = snap.data();
    
    if (notification.type !== 'follow') {
      console.log('Skipping non-follow notification');
      return null;
    }
    
    console.log('📬 Processing follow notification:', notification);
    
    try {
      const userDoc = await db.collection('users').doc(notification.userId).get();
      
      if (!userDoc.exists) {
        console.log('❌ User not found:', notification.userId);
        return null;
      }
      
      const userData = userDoc.data();
      const fcmToken = userData.fcmToken;
      
      if (!fcmToken) {
        console.log('⚠️ No FCM token for user:', notification.userId);
        return null;
      }
      
      const message = {
        notification: {
          title: 'New Follower',
          body: notification.message || `${notification.fromUserName} started following you`,
        },
        data: {
          type: 'follow',
          fromUserId: notification.fromUserId || '',
          notificationId: context.params.notificationId,
        },
        token: fcmToken,
      };
      
      await messaging.send(message);
      console.log('✅ Follow notification sent to:', notification.userId);
      
      return null;
    } catch (error) {
      console.error('❌ Error sending follow notification:', error);
      return null;
    }
  });

// ========================================
// 2. MESSAGE NOTIFICATIONS
// ========================================

exports.sendMessageNotification = functions.firestore
  .document('conversations/{conversationId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const conversationId = context.params.conversationId;
    
    console.log('💬 Processing new message:', message);
    
    try {
      const conversationDoc = await db.collection('conversations').doc(conversationId).get();
      
      if (!conversationDoc.exists) {
        console.log('❌ Conversation not found:', conversationId);
        return null;
      }
      
      const conversation = conversationDoc.data();
      const participantIds = conversation.participantIds || [];
      const recipientId = participantIds.find(id => id !== message.senderId);
      
      if (!recipientId) {
        console.log('⚠️ No recipient found');
        return null;
      }
      
      const recipientDoc = await db.collection('users').doc(recipientId).get();
      
      if (!recipientDoc.exists) {
        console.log('❌ Recipient not found:', recipientId);
        return null;
      }
      
      const recipientData = recipientDoc.data();
      const fcmToken = recipientData.fcmToken;
      const notificationsEnabled = recipientData.messageNotificationsEnabled !== false;
      
      if (!notificationsEnabled) {
        console.log('⚠️ User has disabled message notifications:', recipientId);
        return null;
      }
      
      if (!fcmToken) {
        console.log('⚠️ No FCM token for recipient:', recipientId);
        return null;
      }
      
      const senderDoc = await db.collection('users').doc(message.senderId).get();
      const senderName = senderDoc.exists 
        ? (senderDoc.data().displayName || 'Someone')
        : 'Someone';
      
      const pushMessage = {
        notification: {
          title: senderName,
          body: message.text || 'Sent you a message',
        },
        data: {
          type: 'message',
          conversationId: conversationId,
          senderId: message.senderId,
          messageId: context.params.messageId,
        },
        token: fcmToken,
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: 'default',
            },
          },
        },
      };
      
      await messaging.send(pushMessage);
      console.log('✅ Message notification sent to:', recipientId);
      
      return null;
    } catch (error) {
      console.error('❌ Error sending message notification:', error);
      return null;
    }
  });

// ========================================
// 3. SAVED SEARCH MATCH NOTIFICATIONS
// ========================================

exports.sendSavedSearchNotification = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const notification = snap.data();
    
    if (notification.type !== 'savedSearchMatch') {
      return null;
    }
    
    console.log('🔍 Processing saved search notification:', notification);
    
    try {
      const userDoc = await db.collection('users').doc(notification.userId).get();
      
      if (!userDoc.exists) {
        console.log('❌ User not found:', notification.userId);
        return null;
      }
      
      const userData = userDoc.data();
      const fcmToken = userData.fcmToken;
      
      if (!fcmToken) {
        console.log('⚠️ No FCM token for user:', notification.userId);
        return null;
      }
      
      const message = {
        notification: {
          title: 'Saved Search Match',
          body: notification.message,
        },
        data: {
          type: 'savedSearchMatch',
          category: notification.category || '',
          contentId: notification.contentId || '',
          query: notification.query || '',
          notificationId: context.params.notificationId,
        },
        token: fcmToken,
      };
      
      await messaging.send(message);
      console.log('✅ Saved search notification sent to:', notification.userId);
      
      return null;
    } catch (error) {
      console.error('❌ Error sending saved search notification:', error);
      return null;
    }
  });

console.log('✅ Cloud Functions loaded successfully');
EOF

echo "✅ index.js created with all notification functions"

# Create .gitignore
cat > .gitignore <<EOF
node_modules/
npm-debug.log
.firebase/
*.log
EOF

echo "✅ .gitignore created"

cd ..

echo ""
echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "📁 Functions directory created with:"
echo "   - package.json"
echo "   - index.js (Follow, Message, Saved Search notifications)"
echo "   - node_modules/"
echo ""
echo "🚀 Next Steps:"
echo ""
echo "1. Review the functions code:"
echo "   cd functions && cat index.js"
echo ""
echo "2. Deploy to Firebase:"
echo "   firebase deploy --only functions"
echo ""
echo "3. Monitor logs:"
echo "   firebase functions:log"
echo ""
echo "4. Test locally (optional):"
echo "   firebase emulators:start"
echo ""
echo "📚 Full documentation: FIREBASE_CLOUD_FUNCTIONS_DEPLOYMENT_GUIDE.md"
echo ""
