#!/bin/bash

# Deploy Two-Factor Authentication Cloud Functions
# This script deploys the 2FA OTP generation, delivery, and verification functions

echo "🔐 Deploying Two-Factor Authentication Functions..."
echo ""

# Check if we're in the functions directory
if [ ! -f "twoFactorAuth.js" ]; then
    echo "❌ Error: twoFactorAuth.js not found"
    echo "Please run this script from the functions directory"
    exit 1
fi

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Error: Firebase CLI not found"
    echo "Please install it with: npm install -g firebase-tools"
    exit 1
fi

# Deploy only the 2FA functions
echo "📦 Deploying 2FA functions..."
firebase deploy --only functions:request2FAOTP,functions:verify2FAOTP,functions:send2FAEmail,functions:send2FASMS,functions:cleanupExpiredOTPs

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Two-Factor Authentication functions deployed successfully!"
    echo ""
    echo "📋 Deployed functions:"
    echo "   ✓ request2FAOTP - Request OTP code"
    echo "   ✓ verify2FAOTP - Verify OTP code"
    echo "   ✓ send2FAEmail - Send OTP via email (trigger)"
    echo "   ✓ send2FASMS - Send OTP via SMS (trigger)"
    echo "   ✓ cleanupExpiredOTPs - Cleanup expired codes"
    echo ""
    echo "📌 Next steps:"
    echo "   1. Configure email delivery (Firebase Extensions: Trigger Email)"
    echo "   2. Configure SMS delivery (Twilio or Firebase Auth)"
    echo "   3. Test 2FA flow in the iOS app"
    echo "   4. Monitor function logs: firebase functions:log"
    echo ""
else
    echo ""
    echo "❌ Deployment failed. Check the error messages above."
    exit 1
fi
