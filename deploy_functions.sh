#!/bin/bash

# AMEN App - Cloud Functions Deployment Script
# Deploys P0 fixes to Firebase Cloud Functions

set -e  # Exit on error

echo "🚀 AMEN App - Cloud Functions Deployment"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo -e "${RED}❌ Firebase CLI not found${NC}"
    echo "Install it with: npm install -g firebase-tools"
    exit 1
fi

echo -e "${GREEN}✅ Firebase CLI found${NC}"

# Navigate to functions directory
cd "$(dirname "$0")/functions"

# Check if logged in
if ! firebase projects:list &> /dev/null; then
    echo -e "${YELLOW}⚠️  Not logged in to Firebase${NC}"
    echo "Running firebase login..."
    firebase login
fi

echo -e "${GREEN}✅ Authenticated${NC}"

# Show current project
PROJECT=$(firebase use)
echo -e "${GREEN}📱 Current project: ${PROJECT}${NC}"
echo ""

# Confirm deployment
read -p "Deploy to production? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "📦 Installing dependencies..."
npm install

echo ""
echo "🔨 Building functions..."

echo ""
echo "🚀 Deploying to Firebase..."
firebase deploy --only functions

echo ""
echo -e "${GREEN}✅ Deployment complete!${NC}"
echo ""
echo "📊 Next steps:"
echo "  1. Check Firebase Console: https://console.firebase.google.com"
echo "  2. Monitor function logs: firebase functions:log"
echo "  3. Test notifications to verify idempotency"
echo ""
echo "🔍 Verification checklist:"
echo "  □ Notifications have idempotencyKey field"
echo "  □ No duplicate follow notifications"
echo "  □ No duplicate follow request accepted notifications"
echo "  □ Badge counts are accurate"
echo ""
