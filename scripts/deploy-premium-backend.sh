#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v firebase >/dev/null 2>&1; then
  echo "Firebase CLI is not installed or not on PATH." >&2
  exit 127
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node is not installed or not on PATH. Firebase predeploy needs Node." >&2
  exit 127
fi

echo "Minifying Firestore rules..."
node scripts/strip-rules.js

echo "Deploying premium Cloud Functions and Firestore rules..."
firebase deploy \
  --only \
  functions:default:getPremiumEntitlement,\
functions:default:syncPremiumEntitlement,\
functions:default:appStoreServerNotificationV2,\
functions:default:listCustomTopicTags,\
functions:default:createCustomTopicTag,\
functions:default:recordAIUsageAndCheckLimit,\
functions:default:requirePremiumFeature,\
firestore:rules

echo "Premium backend deploy complete."
