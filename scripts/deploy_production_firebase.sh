#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

PROJECT_ID="${FIREBASE_PROJECT_ID:-}"
ACK="${PRODUCTION_DEPLOY_ACK:-}"
LOCAL_FIREBASE="$ROOT/Backend/rules-tests/node_modules/.bin/firebase"
export FIREBASE_CLI_DISABLE_UPDATE_CHECK=1

if command -v firebase >/dev/null 2>&1; then
  FIREBASE_CMD=(firebase)
elif [ -x "$LOCAL_FIREBASE" ]; then
  FIREBASE_CMD=("$LOCAL_FIREBASE")
else
  FIREBASE_CMD=()
fi

if [ -z "$PROJECT_ID" ]; then
  echo "FAIL: set FIREBASE_PROJECT_ID to the intended production Firebase project id."
  exit 1
fi

if [ "$ACK" != "deploy-to-production" ]; then
  echo "FAIL: set PRODUCTION_DEPLOY_ACK=deploy-to-production to deploy to $PROJECT_ID."
  exit 1
fi

if [ "${#FIREBASE_CMD[@]}" -eq 0 ]; then
  echo "FAIL: firebase CLI is required."
  echo "Install it globally or run: npm --prefix \"$ROOT/Backend/rules-tests\" install"
  exit 1
fi

echo "Verifying Trust and Safety production gate before Firebase deploy..."
REQUIRE_PRODUCTION_SECRETS=1 "$ROOT/scripts/verify_trust_safety_10_go.sh"

echo ""
echo "Verifying Berean realtime production gate before Firebase deploy..."
REQUIRE_FIREBASE_LIVE=1 \
REQUIRE_DEPLOY_DRY_RUN=0 \
REQUIRE_DEVICE_SMOKE_ACK=1 \
"$ROOT/scripts/verify_berean_realtime_10_go.sh"

echo ""
echo "Regenerating deploy Firestore rules from canonical source..."
node "$ROOT/scripts/strip-rules.js"

echo ""
echo "Deploying Firebase rules, functions, and hosting to production project: $PROJECT_ID"
"${FIREBASE_CMD[@]}" --non-interactive --project "$PROJECT_ID" deploy --only firestore,storage,database,functions,hosting

echo ""
echo "Firebase deploy complete. Update Docs/PRODUCTION_FIREBASE_RELEASE_RECORD.md with:"
echo "FIREBASE_PRODUCTION_PROJECT_ID=$PROJECT_ID"
echo "FIREBASE_DEPLOYED_PROJECT_ID=$PROJECT_ID"
echo "FIREBASE_RULES_DEPLOYED=true"
echo "FIREBASE_FUNCTIONS_DEPLOYED=true"
echo "FIREBASE_STORAGE_RULES_DEPLOYED=true"
echo "FIREBASE_DATABASE_RULES_DEPLOYED=true"
echo "FIREBASE_HOSTING_DEPLOYED=true"
echo "APP_CHECK_PRODUCTION_ENFORCED=true only after confirming enforcement in Firebase console."
echo "PRODUCTION_MODERATION_PROVIDERS_CONFIGURED=true only after confirming provider secrets and live checks."
