#!/bin/bash

# 🚀 Deploy AMEN Genkit Server to Cloud Run
# This script deploys all 10 AI flows to Google Cloud Run

echo "🚀 AMEN Genkit Server Deployment"
echo "=================================="
echo ""

# Check if we're in the genkit directory
if [ ! -f "genkit-production-server.js" ]; then
    echo "❌ Error: genkit-production-server.js not found"
    echo "   Please run this script from your genkit directory after copying the files"
    exit 1
fi

# Check if Google Cloud SDK is installed
if ! command -v gcloud &> /dev/null; then
    echo "❌ Error: gcloud CLI not found"
    echo "   Install it from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Get Google AI API key
if [ -z "$GOOGLE_AI_API_KEY" ]; then
    echo "🔑 Please enter your Google AI API Key:"
    echo "   (Get one from: https://makersuite.google.com/app/apikey)"
    read -r GOOGLE_AI_API_KEY
fi

echo ""
echo "📦 Copying production files..."
cp genkit-production-server.js index.js
cp genkit-production-package.json package.json  
cp genkit-production-Dockerfile Dockerfile

echo "✅ Files ready for deployment"
echo ""

# Deploy to Cloud Run
echo "☁️  Deploying to Cloud Run..."
echo "   This may take 2-3 minutes..."
echo ""

gcloud run deploy genkit-amen \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars="GOOGLE_AI_API_KEY=$GOOGLE_AI_API_KEY" \
  --port 8080 \
  --memory 1Gi \
  --timeout 300 \
  --max-instances 10

# Check if deployment succeeded
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Deployment successful!"
    echo ""
    echo "🎯 Your server is live at:"
    gcloud run services describe genkit-amen --region us-central1 --format 'value(status.url)'
    echo ""
    echo "🧪 Test it with:"
    SERVICE_URL=$(gcloud run services describe genkit-amen --region us-central1 --format 'value(status.url)')
    echo "curl $SERVICE_URL/generateFunBibleFact \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"data\": {\"category\": \"random\"}}'"
    echo ""
    echo "📱 Update your iOS app's Info.plist with:"
    echo "<key>GENKIT_ENDPOINT</key>"
    echo "<string>$SERVICE_URL</string>"
    echo ""
    echo "🎉 Ready to ship to TestFlight!"
else
    echo ""
    echo "❌ Deployment failed"
    echo "   Check the error messages above"
    exit 1
fi
