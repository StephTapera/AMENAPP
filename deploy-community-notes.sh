#!/usr/bin/env bash
# deploy-community-notes.sh
# Full deploy checklist for the Community Notes feature.
# Run from the project root: bash deploy-community-notes.sh
#
# BEFORE running:
#   1. Fill in PINECONE_NOTES_INDEX_HOST in Backend/functions/.env (step 1 below)
#   2. Set Firebase secrets (steps 2-5 below)
#   3. Flip the Remote Config flag (step 6 below)
#
# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: Create the Pinecone index (run once, in browser or via curl)
# ─────────────────────────────────────────────────────────────────────────────
# Create at https://app.pinecone.io → "Create Index" with:
#   Name:       amen-notes
#   Dimensions: 1536   (text-embedding-3-small output size)
#   Metric:     cosine
#   Cloud:      AWS us-east-1 (serverless)
#
# Or via curl (replace <YOUR_PINECONE_API_KEY>):
#
# curl -s -X POST "https://api.pinecone.io/indexes" \
#   -H "Api-Key: <YOUR_PINECONE_API_KEY>" \
#   -H "Content-Type: application/json" \
#   -d '{
#     "name": "amen-notes",
#     "dimension": 1536,
#     "metric": "cosine",
#     "spec": {
#       "serverless": {
#         "cloud": "aws",
#         "region": "us-east-1"
#       }
#     }
#   }'
#
# After creation, copy the "Host" URL from the index details page
# (looks like: amen-notes-xxxx.svc.us-east1-gcp.pinecone.io)
# and paste it in Backend/functions/.env:
#   PINECONE_NOTES_INDEX_HOST=https://amen-notes-xxxx.svc.us-east1-gcp.pinecone.io

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
FUNCTIONS_DIR="$PROJECT_DIR/Backend/functions"

echo "=== Community Notes deployment ==="
echo ""

# ─── Step 2: Firebase secrets ────────────────────────────────────────────────
# Set these once. Skip if already set.
# Retrieve each key from its respective dashboard.

echo "--- Checking Firebase secrets ---"
echo "Run the following if not yet set:"
echo ""
echo "  firebase functions:secrets:set ALGOLIA_APP_ID"
echo "  firebase functions:secrets:set ALGOLIA_ADMIN_KEY"
echo "  firebase functions:secrets:set PINECONE_API_KEY"
echo "  firebase functions:secrets:set OPENAI_API_KEY"
echo ""
echo "  (Each command will prompt for the value interactively.)"
echo ""
read -rp "Have all four secrets been set? (y/N) " secrets_ok
if [[ "${secrets_ok,,}" != "y" ]]; then
  echo "Aborting — set secrets first, then re-run."
  exit 1
fi

# ─── Step 3: Verify .env has the Pinecone host ───────────────────────────────
PINECONE_HOST_VAR=$(grep "^PINECONE_NOTES_INDEX_HOST=" "$FUNCTIONS_DIR/.env" | cut -d= -f2 | tr -d '[:space:]')
if [[ -z "$PINECONE_HOST_VAR" ]]; then
  echo ""
  echo "ERROR: PINECONE_NOTES_INDEX_HOST is empty in Backend/functions/.env"
  echo "Create the Pinecone index first (see Step 1 comments above), then fill in the host."
  exit 1
fi
echo "Pinecone host: $PINECONE_HOST_VAR ✓"
echo ""

# ─── Step 4: Build Cloud Functions ───────────────────────────────────────────
echo "--- Building Cloud Functions ---"
(cd "$FUNCTIONS_DIR" && npm run build)
echo ""

# ─── Step 5: Deploy functions + rules + indexes ──────────────────────────────
echo "--- Deploying to Firebase ---"
firebase deploy \
  --only "functions:backend,firestore:rules,firestore:indexes" \
  --project "$(firebase use 2>/dev/null | head -1 || echo 'your-project-id')"
echo ""

# ─── Step 6: Enable the feature flag ─────────────────────────────────────────
echo "--- Remote Config ---"
echo "Flip community_notes_enabled = true in Firebase Remote Config:"
echo "  https://console.firebase.google.com → Remote Config → community_notes_enabled"
echo ""
echo "Or via CLI (requires remoteconfig:update permission):"
echo "  firebase remoteconfig:set community_notes_enabled true"
echo ""

echo "=== Deployment complete ==="
echo ""
echo "Acceptance checklist:"
echo "  [ ] Publish a test note → appears in community_notes Algolia index"
echo "  [ ] Publish a test note → vector stored in amen-notes Pinecone namespace"
echo "  [ ] searchCommunityNotes callable returns results for a scripture query"
echo "  [ ] Like/Save a note → counters increment in Firestore"
echo "  [ ] Private note → NOT returned by top/recent queries"
echo "  [ ] Flip community_notes_enabled = true → Notes tab appears in app"
