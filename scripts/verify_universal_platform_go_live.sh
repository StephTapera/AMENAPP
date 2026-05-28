#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export FIREBASE_CLI_DISABLE_UPDATE_CHECK=1

LOCAL_FIREBASE="$ROOT/Backend/rules-tests/node_modules/.bin/firebase"
REQUIRE_FIREBASE_LIVE="${REQUIRE_FIREBASE_LIVE:-0}"
RUN_BACKEND_TESTS="${RUN_BACKEND_TESTS:-1}"
RUN_IOS_BUILD="${RUN_IOS_BUILD:-0}"
PROJECT_ID="${FIREBASE_PROJECT_ID:-}"

if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="$(node -e "const fs=require('fs'); const p=JSON.parse(fs.readFileSync('.firebaserc','utf8')); process.stdout.write(p.projects && p.projects.default || '')" 2>/dev/null || true)"
fi

if command -v firebase >/dev/null 2>&1; then
  FIREBASE_CMD=(firebase)
elif [ -x "$LOCAL_FIREBASE" ]; then
  FIREBASE_CMD=("$LOCAL_FIREBASE")
else
  FIREBASE_CMD=()
fi

fail() {
  echo "FAIL: $1"
  exit 1
}

require_file_contains() {
  local file="$1"
  local pattern="$2"
  grep -q "$pattern" "$ROOT/$file" || fail "$file is missing required pattern: $pattern"
}

echo "Universal Creation Platform GO-live verification"
echo "Project: ${PROJECT_ID:-not set}"
echo ""

[ -n "$PROJECT_ID" ] || fail "FIREBASE_PROJECT_ID is not set and .firebaserc has no default project."

echo "Checking Firebase deploy sources..."
require_file_contains "firebase.json" '"rules": "AMENAPP/firestore.deploy.rules"'
require_file_contains "firebase.json" '"rules": "AMENAPP/storage.rules"'
require_file_contains "firebase.json" '"source": "Backend/functions"'

echo "Regenerating Firestore deploy rules..."
node "$ROOT/scripts/strip-rules.js"

echo "Checking universal Firestore rules..."
require_file_contains "AMENAPP/firestore.deploy.rules" 'match/users/{userId}/drafts/{draftId}'
require_file_contains "AMENAPP/firestore.deploy.rules" 'match/users/{userId}/media/{mediaId}'
require_file_contains "AMENAPP/firestore.deploy.rules" 'match/transcriptTracks/{trackId}'
require_file_contains "AMENAPP/firestore.deploy.rules" 'match/captionTracks/{trackId}'
require_file_contains "AMENAPP/firestore.deploy.rules" 'match/users/{userId}/designs/{designId}'
require_file_contains "AMENAPP/firestore.deploy.rules" 'match/users/{userId}/scheduledContent/{scheduleId}'
require_file_contains "AMENAPP/firestore.deploy.rules" 'match/users/{userId}/aiJobs/{jobId}'
require_file_contains "AMENAPP/firestore.deploy.rules" 'match/contentEmbeddings/{contentId}'
require_file_contains "AMENAPP/firestore.deploy.rules" 'match/threadSummaries/{summaryId}'

echo "Checking universal Storage rules..."
require_file_contains "AMENAPP/storage.rules" 'match /users/{userId}/media/{mediaId}/original'
require_file_contains "AMENAPP/storage.rules" 'match /users/{userId}/media/{mediaId}/processed/{fileName}'
require_file_contains "AMENAPP/storage.rules" 'match /users/{userId}/media/{mediaId}/thumbnails/{fileName}'
require_file_contains "AMENAPP/storage.rules" 'match /users/{userId}/designs/{designId}/{fileName}'

echo "Checking required backend exports..."
require_file_contains "Backend/functions/src/universalContent/platformFunctions.ts" 'export const generateVideoTranscript'
require_file_contains "Backend/functions/src/universalContent/platformFunctions.ts" 'export const generateCaptions'
require_file_contains "Backend/functions/src/universalContent/platformFunctions.ts" 'export const generateVideoChapters'
require_file_contains "Backend/functions/src/universalContent/platformFunctions.ts" 'export const generateMediaSummary'
require_file_contains "Backend/functions/src/universalContent/platformFunctions.ts" 'export const publishDueUniversalScheduledContent'
require_file_contains "Backend/functions/src/universalContent/platformFunctions.ts" 'export const processQueuedUniversalMedia'
require_file_contains "Backend/functions/src/universalContent/platformFunctions.ts" 'defineSecret("ANTHROPIC_API_KEY")'
require_file_contains "Backend/functions/src/universalContent/platformFunctions.ts" 'defineSecret("OPENAI_API_KEY")'
require_file_contains "Backend/functions/src/index.ts" './universalContent/platformFunctions'

echo "Building backend TypeScript..."
npm --prefix "$ROOT/Backend/functions" run build

if [ "$RUN_BACKEND_TESTS" = "1" ]; then
  echo "Running backend Jest suite..."
  npm --prefix "$ROOT/Backend/functions" test -- --runInBand src/universalContent/contentNodeFunctions.test.ts
else
  echo "Skipping backend Jest suite because RUN_BACKEND_TESTS=$RUN_BACKEND_TESTS"
fi

if [ "$RUN_IOS_BUILD" = "1" ]; then
  echo "RUN_IOS_BUILD=1 is set. Build the iOS app from Xcode/Codex with BuildProject; this shell gate does not invoke xcodebuild directly."
fi

if [ "$REQUIRE_FIREBASE_LIVE" = "1" ]; then
  [ "${#FIREBASE_CMD[@]}" -gt 0 ] || fail "firebase CLI is required for live verification."
  echo "Checking Firebase secret access..."
  "${FIREBASE_CMD[@]}" --project "$PROJECT_ID" functions:secrets:access ANTHROPIC_API_KEY >/dev/null
  "${FIREBASE_CMD[@]}" --project "$PROJECT_ID" functions:secrets:access OPENAI_API_KEY >/dev/null

  echo "Checking Firebase project access..."
  "${FIREBASE_CMD[@]}" --project "$PROJECT_ID" projects:list >/dev/null
else
  echo "Skipping live Firebase secret/project checks because REQUIRE_FIREBASE_LIVE=$REQUIRE_FIREBASE_LIVE"
fi

echo ""
echo "Universal Creation Platform GO-live verification passed."
