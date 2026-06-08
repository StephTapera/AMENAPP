#!/usr/bin/env bash
# deploy-berean-v1.sh
# Deploy Berean v1 end-to-end. Run from the project root.
# Firebase project: amen-5e359
#
# Prerequisites:
#   - firebase CLI installed and authenticated
#   - GOOGLE_APPLICATION_CREDENTIALS set OR `firebase login` completed
#   - BIBLE_API_KEY secret already set in Firebase Secret Manager
#     (firebase functions:secrets:set BIBLE_API_KEY)
#
# Usage:
#   chmod +x deploy-berean-v1.sh
#   ./deploy-berean-v1.sh

set -euo pipefail

PROJECT="amen-5e359"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Berean v1 Deploy  —  Firebase project: $PROJECT"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── Step 1: Check BIBLE_API_KEY secret exists ─────────────────────────────────
echo "Step 1/5 — Verifying BIBLE_API_KEY secret..."
if firebase functions:secrets:access BIBLE_API_KEY --project "$PROJECT" > /dev/null 2>&1; then
  echo "  ✅  BIBLE_API_KEY secret found"
else
  echo ""
  echo "  ⛔  CREDENTIAL STOP: BIBLE_API_KEY is not set."
  echo "  Run:  firebase functions:secrets:set BIBLE_API_KEY --project $PROJECT"
  echo "  Then re-run this script."
  exit 1
fi

# ── Step 2: Deploy Firestore rules ────────────────────────────────────────────
echo ""
echo "Step 2/5 — Deploying Firestore security rules..."
firebase deploy --only firestore:rules --project "$PROJECT"
echo "  ✅  Firestore rules deployed (berean/{uid}/... B-1–B-8 invariants active)"

# ── Step 3: Deploy Berean Cloud Functions ─────────────────────────────────────
echo ""
echo "Step 3/5 — Deploying Berean callables..."
firebase deploy \
  --only functions:bereanChat,functions:bereanMemory,functions:bereanCrisisDetect,functions:bereanBibleLookup \
  --project "$PROJECT"
echo "  ✅  4 Berean callables deployed:"
echo "       bereanChat           — main answer callable"
echo "       bereanMemory         — memory summarization"
echo "       bereanCrisisDetect   — crisis detection (boolean only, AI answer suppressed)"
echo "       bereanBibleLookup    — server-side Bible API proxy (BSB/WEB/KJV)"

# ── Step 4: Seed Firestore config documents ───────────────────────────────────
echo ""
echo "Step 4/5 — Seeding config/credits and config/voice..."
node scripts/seed-berean-config.js

# ── Step 5: Reminder — T&S crisis gate review ─────────────────────────────────
echo ""
echo "Step 5/5 — HUMAN ACTION REQUIRED (T&S)"
echo "══════════════════════════════════════════════════════════════"
echo "  Before enabling production traffic on bereanCrisisDetect:"
echo ""
echo "  1. Review the crisis HumanGatePayload log path in:"
echo "     src/berean/core/crisis.ts → handleCrisis()"
echo ""
echo "  2. Confirm the T&S escalation queue is configured to receive"
echo "     HumanGatePayload documents with reason: 'CRISIS_CONTENT'."
echo ""
echo "  3. Confirm SLA for crisis handoff review."
echo ""
echo "  This is a HUMAN GATE — do not skip."
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "  ✅  Berean v1 deploy complete."
echo ""
echo "  YouVersion: BLOCKED pending written commercial agreement."
echo "  CSAM:       Existing ncmecReporter.js pipeline unchanged."
echo ""
