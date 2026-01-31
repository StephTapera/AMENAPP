#!/bin/bash
# Deploy Saved Search Alert Cloud Function

echo "🚀 Deploying Saved Search Alert Cloud Function..."

# Navigate to functions directory
cd functions || exit

# Install dependencies (if needed)
npm install

# Build TypeScript
npm run build

# Deploy only the saved search alert function
firebase deploy --only functions:onSearchAlertCreated

echo "✅ Deployment complete!"
echo ""
echo "📊 View logs:"
echo "  firebase functions:log --only onSearchAlertCreated"
echo ""
echo "🔍 Test manually:"
echo "  Create a saved search with notifications enabled"
echo "  Trigger a background check"
echo "  Verify push notification arrives"
