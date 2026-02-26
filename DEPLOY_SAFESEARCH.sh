#!/bin/bash

# Deployment script for Cloud Vision SafeSearch Image Moderation
# Run this to deploy all SafeSearch components

set -e  # Exit on error

echo "🚀 Deploying Cloud Vision SafeSearch Image Moderation"
echo "===================================================="
echo ""

# Step 1: Enable Vision API in GCP
echo "📋 Step 1: Enabling Cloud Vision API..."
gcloud services enable vision.googleapis.com --project=amen-5e359
echo "✅ Vision API enabled"
echo ""

# Step 2: Install Cloud Functions dependencies
echo "📦 Step 2: Installing Cloud Functions dependencies..."
cd functions
npm install @google-cloud/vision --save
echo "✅ Dependencies installed"
echo ""

# Step 3: Deploy Cloud Functions
echo "☁️  Step 3: Deploying Cloud Function..."
cd ..
firebase deploy --only functions:moderateUploadedImage
echo "✅ Cloud Function deployed"
echo ""

# Step 4: Update Firestore Security Rules
echo "🔒 Step 4: Deploying Firestore security rules..."
firebase deploy --only firestore:rules
echo "✅ Security rules deployed"
echo ""

# Step 5: Verify deployment
echo "🔍 Step 5: Verifying deployment..."
echo ""
echo "Cloud Function: moderateUploadedImage"
echo "  - Trigger: onObjectFinalized (Storage)"
echo "  - Region: us-central1"
echo "  - Status: Check Firebase Console > Functions"
echo ""
echo "Vision API Status:"
gcloud services list --enabled --project=amen-5e359 | grep vision || echo "  ⚠️  Not found in enabled services"
echo ""

# Step 6: Test checklist
echo "✅ Deployment Complete!"
echo ""
echo "📝 Next Steps - Manual Testing:"
echo "  1. Upload a clean test image → should approve"
echo "  2. Upload an inappropriate test image → should block and delete"
echo "  3. Check Firebase Console > Firestore > imageModerationLogs"
echo "  4. Check Firebase Console > Firestore > moderatorAlerts"
echo "  5. Monitor Cloud Functions logs for any errors"
echo ""
echo "💰 Cost Monitoring:"
echo "  - Set up billing alerts at \$20/month"
echo "  - Monitor Vision API usage in GCP Console"
echo "  - First 1,000 requests/month are FREE"
echo ""
echo "📚 Documentation:"
echo "  - See: CLOUD_VISION_SAFESEARCH_AUDIT.md for full details"
echo "  - Vision API Docs: https://cloud.google.com/vision/docs/detecting-safe-search"
echo ""
echo "🎉 SafeSearch Image Moderation is now live!"
