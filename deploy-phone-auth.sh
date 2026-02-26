#!/bin/bash

echo "🚀 Deploying Phone Auth Rate Limiting Functions..."

cd functions

# Deploy the three phone auth functions
firebase deploy --only \
  functions:checkPhoneVerificationRateLimit,\
  functions:reportPhoneVerificationFailure,\
  functions:unblockPhoneNumber

if [ $? -eq 0 ]; then
  echo "✅ Phone auth functions deployed successfully!"
  echo ""
  echo "Next steps:"
  echo "1. Uncomment lines 937-960 in AMENAPP/AuthenticationViewModel.swift"
  echo "2. Uncomment lines 977-989 in AMENAPP/AuthenticationViewModel.swift"
  echo "3. Build and test on a physical device"
else
  echo "❌ Deployment failed. Check error messages above."
  exit 1
fi
