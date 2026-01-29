#!/bin/bash

# 🚀 Quick Deploy Script for Fixed Cloud Functions
# Run this from your project root directory

echo "🔥 AMEN App - Cloud Functions Deployment"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo -e "${RED}❌ Firebase CLI not found!${NC}"
    echo ""
    echo "Install it with:"
    echo "  npm install -g firebase-tools"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Firebase CLI found${NC}"
echo ""

# Check if functionsindex.js exists
if [ ! -f "functionsindex.js" ]; then
    echo -e "${RED}❌ functionsindex.js not found in current directory${NC}"
    echo ""
    echo "Make sure you're in the project root directory"
    exit 1
fi

echo -e "${GREEN}✅ functionsindex.js found${NC}"
echo ""

# Check if functions directory exists, if not create it
if [ ! -d "functions" ]; then
    echo -e "${YELLOW}📁 Creating functions directory...${NC}"
    mkdir functions
fi

# Copy functionsindex.js to functions/index.js
echo -e "${YELLOW}📋 Copying functionsindex.js to functions/index.js...${NC}"
cp functionsindex.js functions/index.js

# Check if package.json exists in functions
if [ ! -f "functions/package.json" ]; then
    echo -e "${YELLOW}📦 Creating package.json...${NC}"
    cd functions
    
    cat > package.json << 'EOF'
{
  "name": "functions",
  "description": "Cloud Functions for AMEN App",
  "scripts": {
    "serve": "firebase emulators:start --only functions",
    "shell": "firebase functions:shell",
    "start": "npm run shell",
    "deploy": "firebase deploy --only functions",
    "logs": "firebase functions:log"
  },
  "engines": {
    "node": "18"
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
    
    echo -e "${YELLOW}📥 Installing dependencies...${NC}"
    npm install
    
    cd ..
fi

echo -e "${GREEN}✅ Functions directory ready${NC}"
echo ""

# Show what will be deployed
echo -e "${YELLOW}📋 Functions to be deployed:${NC}"
echo "  ✅ syncAmenCount (NEW - Realtime DB trigger)"
echo "  ✅ syncCommentCount (NEW - Realtime DB trigger)"
echo "  ✅ syncLightbulbCount (NEW - Realtime DB trigger)"
echo "  ✅ syncRepostCount (NEW - Realtime DB trigger)"
echo ""
echo -e "${YELLOW}🗑️  Functions to be deleted:${NC}"
echo "  ❌ updateAmenCount (old broken trigger)"
echo "  ❌ updateCommentCount (old broken trigger)"
echo "  ❌ updateRepostCount (old broken trigger)"
echo ""

# Confirm deployment
echo -e "${YELLOW}⚠️  This will deploy Cloud Functions to Firebase${NC}"
read -p "Continue? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ Deployment cancelled${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🚀 Deploying functions...${NC}"
echo ""

# Deploy
firebase deploy --only functions

# Check deployment status
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ ✅ ✅ DEPLOYMENT SUCCESSFUL! ✅ ✅ ✅${NC}"
    echo ""
    echo "🎉 Your post interactions should now be INSTANT!"
    echo ""
    echo "Next steps:"
    echo "1. Open your app and test amen/comment interactions"
    echo "2. They should be instant (< 100ms)!"
    echo "3. Watch logs: firebase functions:log"
    echo ""
    echo "Verify deployment:"
    echo "  firebase functions:list"
    echo ""
else
    echo ""
    echo -e "${RED}❌ Deployment failed${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "1. Make sure you're logged in: firebase login"
    echo "2. Check you selected the right project: firebase use"
    echo "3. View error logs above"
    echo ""
    exit 1
fi
