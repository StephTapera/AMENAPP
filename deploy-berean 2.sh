#!/usr/bin/env bash
set -euo pipefail

# deploy-berean.sh
# Deploys all Berean AI Cloud Functions and Firestore rules added during the
# 2026-06-03 audit. Run from the repo root: bash deploy-berean.sh
#
# Pre-requisites:
#   firebase login
#   firebase use <project-id>          # default alias: amen-5e359
#   firebase functions:secrets:set CLAUDE_API_KEY
#   firebase functions:secrets:set OPENAI_API_KEY
#   firebase functions:secrets:set PINECONE_API_KEY
#   firebase functions:secrets:set PINECONE_HOST
#
# To make this script executable (run once):
#   chmod +x deploy-berean.sh

PROJECT="amen-5e359"

echo "=== AMEN Berean AI Audit Deploy ==="
echo "Project: ${PROJECT}"
echo ""

# ---------------------------------------------------------------------------
# 1. Verify Firebase CLI
# ---------------------------------------------------------------------------
if ! command -v firebase &> /dev/null; then
  echo "ERROR: firebase CLI not found."
  echo "Install: npm install -g firebase-tools"
  exit 1
fi

echo "Verifying Firebase authentication..."
if ! firebase projects:list --project "${PROJECT}" &> /dev/null; then
  echo "ERROR: Firebase CLI is not authenticated or project '${PROJECT}' is not accessible."
  echo "Run: firebase login"
  exit 1
fi
echo "  Authenticated OK"
echo ""

# ---------------------------------------------------------------------------
# 2. Verify required secrets (non-blocking — warns but does not fail)
# ---------------------------------------------------------------------------
SECRETS_MISSING=0

check_secret() {
  local secret=$1
  if firebase functions:secrets:access "${secret}" --project "${PROJECT}" &> /dev/null; then
    echo "  [OK]     ${secret}"
  else
    echo "  [MISSING] ${secret}  — set with: firebase functions:secrets:set ${secret}"
    SECRETS_MISSING=1
  fi
}

echo "Checking secrets..."
check_secret "CLAUDE_API_KEY"
check_secret "OPENAI_API_KEY"
check_secret "PINECONE_API_KEY"
check_secret "PINECONE_HOST"
echo ""

if [ "${SECRETS_MISSING}" = "1" ]; then
  echo "WARNING: One or more secrets are missing."
  echo "         Deployed functions will fail at runtime until they are set."
  read -rp "Continue anyway? (y/N) " confirm
  [[ "${confirm}" == [yY] ]] || { echo "Aborted."; exit 1; }
  echo ""
fi

# ---------------------------------------------------------------------------
# 3. Deploy Firestore rules first
#    Rules are applied before CF changes land, so clients already get the
#    correct permission model when new functions start serving traffic.
# ---------------------------------------------------------------------------
echo "Step 1/2 — Deploying Firestore rules..."
firebase deploy --only firestore:rules --project "${PROJECT}"
echo "  Firestore rules deployed."
echo ""

# ---------------------------------------------------------------------------
# 4. Deploy Berean AI Cloud Functions (audit batch)
#
#    Dependency order:
#      a. writeBereanAuditEntry  — foundation; other CFs write to bereanAuditLog
#      b. reportUnsafeAIResponse — depends on bereanAuditLog collection existing
#      c. createRealtimeSession  — no peer dependencies
#      d. bereanSLOCheck         — reads bereanMetrics/hourly; scheduled function
#      e. cleanupDraftVectors    — admin-only; run once after deploy
#      f. deleteAccount          — extended to purge Pinecone vectors on deletion
#      g. getCrisisAlertQueue    — admin callable: lists open pastoral care alerts
#      h. resolveAlert           — admin callable: marks an alert resolved
# ---------------------------------------------------------------------------
echo "Step 2/2 — Deploying Berean AI Cloud Functions..."
firebase deploy \
  --only \
    functions:writeBereanAuditEntry,\
functions:reportUnsafeAIResponse,\
functions:createRealtimeSession,\
functions:bereanSLOCheck,\
functions:cleanupDraftVectors,\
functions:deleteAccount,\
functions:getCrisisAlertQueue,\
functions:resolveAlert \
  --project "${PROJECT}"
echo "  Cloud Functions deployed."
echo ""

# ---------------------------------------------------------------------------
# 5. Summary
# ---------------------------------------------------------------------------
echo "=== Deploy complete ==="
echo ""
echo "POST-DEPLOY STEPS (manual):"
echo ""
echo "  1. Run the Pinecone draft-vector cleanup (one-time, admin auth required):"
echo "       firebase functions:call cleanupDraftVectors --data '{}' --project ${PROJECT}"
echo "     Expected response: { \"deleted\": N, \"scanned\": M, \"durationMs\": D }"
echo "     Safe to re-run — idempotent."
echo ""
echo "  2. Register App Check in Firebase Console:"
echo "       https://console.firebase.google.com/project/${PROJECT}/appcheck"
echo "     - Provider: App Attest (production) / DeviceCheck (fallback)"
echo "     - Enable enforcement for: Authentication, Firestore, Functions, Storage"
echo "     - Add a debug token from the first DEBUG build's Xcode console log"
echo "       (set FirebaseAppCheckDebugToken in your Xcode scheme environment variables)"
echo ""
echo "  3. After enabling App Check enforcement, flip enforceAppCheck: false -> true in:"
echo "       functions/bereanFunctions.js — bereanChatProxy, deleteAccount"
echo ""
echo "  4. Verify bereanSLOCheck appears as a scheduled function:"
echo "       https://console.firebase.google.com/project/${PROJECT}/functions"
echo ""
echo "  5. Check CF logs for any 'App Check token verification failed' errors"
echo "     (should be 0 from legitimate clients once App Check is enforced)."
echo ""
