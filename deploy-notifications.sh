#!/bin/bash

# Deploy Notifications System (Instagram-Speed) to Production
# Created: February 9, 2026

echo "🚀 Deploying Production-Ready Notifications System"
echo "=================================================="
echo ""

# Check if we're in the right directory
if [ ! -d "functions" ]; then
    echo "❌ Error: functions directory not found"
    echo "   Please run this script from the project root"
    exit 1
fi

# Step 1: Deploy Cloud Functions
echo "📤 Step 1: Deploying Cloud Functions..."
echo "   This will update all notification functions to include profile photos"
echo ""

cd functions

# Deploy all notification functions
firebase deploy --only functions:onUserFollow,functions:onUserUnfollow,functions:onCommentCreate,functions:onCommentReply,functions:onPostCreate,functions:onAmenCreate,functions:onAmenDelete,functions:onRepostCreate,functions:onFollowRequestAccepted,functions:onMessageRequestAccepted,functions:onRealtimeCommentCreate

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Cloud Functions deployment failed"
    echo "   Please check your Firebase credentials and try again"
    cd ..
    exit 1
fi

cd ..

echo ""
echo "✅ Cloud Functions deployed successfully!"
echo ""

# Step 2: Verify Deployment
echo "🔍 Step 2: Verifying deployment..."
echo ""

# Check if functions are live
firebase functions:list 2>/dev/null | grep -E "onUserFollow|onCommentCreate|onAmenCreate|onRepostCreate"

if [ $? -eq 0 ]; then
    echo "✅ Functions are live and running"
else
    echo "⚠️  Could not verify functions (firebase CLI may not be configured)"
    echo "   You can verify manually in Firebase Console"
fi

echo ""
echo "=================================================="
echo "✅ Deployment Complete!"
echo "=================================================="
echo ""
echo "📱 Next Steps:"
echo ""
echo "1. Build and run the iOS app:"
echo "   - Open AMENAPP.xcodeproj in Xcode"
echo "   - Build for physical device (Simulator doesn't support push)"
echo "   - Run the app"
echo ""
echo "2. Test notifications:"
echo "   - Have another user follow you"
echo "   - Have another user comment on your post"
echo "   - Have another user like your post"
echo "   - Check Notifications tab for profile photos"
echo ""
echo "3. Verify performance:"
echo "   - First load: Should see images load (300-500ms)"
echo "   - Second load: Images appear instantly (< 50ms)"
echo "   - Scrolling: Should be butter smooth"
echo ""
echo "📊 Monitor in Xcode Console:"
echo "   Look for these logs:"
echo "   ✅ NotificationImageCache initialized"
echo "   📸 Image loaded from memory cache (0ms)"
echo "   📥 Image loaded from disk cache (15ms)"
echo ""
echo "🎉 Your notification system is now Instagram/Threads-level fast!"
echo ""
