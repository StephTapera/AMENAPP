#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS="$ROOT/AMEN_FINAL_10_GO_RESULTS/berean_realtime"
PROJECT_ID="${FIREBASE_PROJECT_ID:-amen-5e359}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export FIREBASE_CLI_DISABLE_UPDATE_CHECK=1
LOCAL_FIREBASE="$ROOT/Backend/rules-tests/node_modules/.bin/firebase"

if command -v firebase >/dev/null 2>&1; then
  FIREBASE_CMD=(firebase)
elif [ -x "$LOCAL_FIREBASE" ]; then
  FIREBASE_CMD=("$LOCAL_FIREBASE")
else
  FIREBASE_CMD=()
fi

mkdir -p "$RESULTS"

echo "Amen Berean Realtime 10/10 technical verification"
echo "Project: $PROJECT_ID"
echo "Results: $RESULTS"

echo ""
echo "1) Backend typecheck"
(
  cd "$ROOT/Backend/functions"
  npm run typecheck
) | tee "$RESULTS/backend_typecheck.log"

echo ""
echo "2) Backend lint"
(
  cd "$ROOT/Backend/functions"
  npm run lint
) | tee "$RESULTS/backend_lint.log"

echo ""
echo "3) Backend build"
(
  cd "$ROOT/Backend/functions"
  npm run build
) | tee "$RESULTS/backend_build.log"

echo ""
echo "4) Berean realtime release tests"
(
  cd "$ROOT/Backend/functions"
  npm test -- --runTestsByPath \
    src/__tests__/berean.realtime.static.test.ts \
    src/__tests__/berean.realtimeReleaseReadiness.static.test.ts
) | tee "$RESULTS/backend_realtime_tests.log"

echo ""
echo "5) Firestore deploy rules generation"
node "$ROOT/scripts/strip-rules.js" | tee "$RESULTS/strip_rules.log"

if ! grep -q "match /realtimeSessions/{sessionId}" "$ROOT/AMENAPP/firestore.deploy.rules"; then
  echo "FAIL: generated deploy rules are missing realtimeSessions."
  exit 1
fi
if ! grep -q "match /realtimeModerationEvents/{eventId}" "$ROOT/AMENAPP/firestore.deploy.rules"; then
  echo "FAIL: generated deploy rules are missing realtimeModerationEvents."
  exit 1
fi
echo "PASS: generated deploy rules include Berean realtime collections."

echo ""
echo "6) Firebase live project checks"
if [ "${REQUIRE_FIREBASE_LIVE:-0}" = "1" ]; then
  if [ "${#FIREBASE_CMD[@]}" -eq 0 ]; then
    echo "FAIL: firebase CLI is required for live Firebase verification."
    echo "Install it globally or run: npm --prefix \"$ROOT/Backend/rules-tests\" install"
    exit 1
  fi

  "${FIREBASE_CMD[@]}" --non-interactive --project "$PROJECT_ID" projects:list >/dev/null
  "${FIREBASE_CMD[@]}" --non-interactive --project "$PROJECT_ID" functions:secrets:access OPENAI_API_KEY >/dev/null
  echo "PASS: Firebase CLI is authenticated and OPENAI_API_KEY is configured."

  if [ "${REQUIRE_DEPLOY_DRY_RUN:-1}" = "1" ]; then
    "${FIREBASE_CMD[@]}" --non-interactive --project "$PROJECT_ID" deploy \
      --only firestore:rules,firestore:indexes,functions:creator \
      --dry-run | tee "$RESULTS/firebase_deploy_dry_run.log"
    echo "PASS: Firebase deploy dry-run completed."
  fi
else
  echo "SKIP: set REQUIRE_FIREBASE_LIVE=1 to require Firebase auth, OPENAI_API_KEY access, and deploy dry-run."
fi

echo ""
echo "7) Real device smoke-test acknowledgement"
if [ "${REQUIRE_DEVICE_SMOKE_ACK:-0}" = "1" ]; then
  required_markers=(
    "REAL_AUDIO_SESSION_STARTED=true"
    "OPENAI_REALTIME_CONNECTED=true"
    "CAPTIONS_RENDERED=true"
    "TRANSCRIPT_CHUNKS_PERSISTED=true"
    "MODERATION_EVENTS_VERIFIED=true"
    "RECONNECT_RECOVERY_VERIFIED=true"
  )
  SMOKE_FILE="$ROOT/Docs/BEREAN_REALTIME_DEVICE_SMOKE_SIGNOFF.md"
  if [ ! -f "$SMOKE_FILE" ]; then
    echo "FAIL: missing $SMOKE_FILE"
    exit 1
  fi
  for marker in "${required_markers[@]}"; do
    if ! grep -q "$marker" "$SMOKE_FILE"; then
      echo "FAIL: missing smoke-test marker: $marker"
      exit 1
    fi
  done
  echo "PASS: real device smoke-test signoff markers are complete."
else
  echo "SKIP: set REQUIRE_DEVICE_SMOKE_ACK=1 after completing real-device streaming validation."
fi

echo ""
echo "Berean realtime technical verification complete."
