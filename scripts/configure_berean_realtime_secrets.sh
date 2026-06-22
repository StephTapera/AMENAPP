#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
LOCAL_FIREBASE="$ROOT/Backend/rules-tests/node_modules/.bin/firebase"

if command -v firebase >/dev/null 2>&1; then
  FIREBASE_CMD=(firebase)
elif [ -x "$LOCAL_FIREBASE" ]; then
  FIREBASE_CMD=("$LOCAL_FIREBASE")
else
  FIREBASE_CMD=()
fi

PROJECT_ID="${FIREBASE_PROJECT_ID:-}"
if [ -z "$PROJECT_ID" ]; then
  echo "FAIL: set FIREBASE_PROJECT_ID to the production Firebase project id."
  exit 1
fi

if [ "${#FIREBASE_CMD[@]}" -eq 0 ]; then
  echo "FAIL: firebase CLI is required."
  echo "Install it globally or run: npm --prefix \"$ROOT/Backend/rules-tests\" install"
  exit 1
fi

echo "Configuring Berean realtime secrets for Firebase project: $PROJECT_ID"
echo "Secret values are entered through the Firebase CLI and are not written to this repo."
echo ""

"${FIREBASE_CMD[@]}" --project "$PROJECT_ID" functions:secrets:set OPENAI_API_KEY

echo ""
echo "Verifying the secret can be accessed by Firebase Functions..."
"${FIREBASE_CMD[@]}" --project "$PROJECT_ID" functions:secrets:access OPENAI_API_KEY >/dev/null

echo ""
echo "Berean realtime secret configuration complete."
echo "Next run:"
echo "  FIREBASE_PROJECT_ID=$PROJECT_ID REQUIRE_FIREBASE_LIVE=1 scripts/verify_berean_realtime_10_go.sh"
