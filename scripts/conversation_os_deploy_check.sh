#!/usr/bin/env bash
# conversation_os_deploy_check.sh
# Pre-deploy safety checks for the Intelligent Conversation OS.
# Run this before: firebase deploy --only functions,firestore:rules,firestore:indexes,remoteconfig
#
# Usage: bash scripts/conversation_os_deploy_check.sh [--project <firebase-project-id>]

set -euo pipefail

PROJECT="${FIREBASE_PROJECT:-}"

# Parse --project flag
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$PROJECT" ]]; then
  # Try to read from .firebaserc
  if [[ -f .firebaserc ]]; then
    PROJECT=$(python3 -c "import json,sys; d=json.load(open('.firebaserc')); print(d.get('projects',{}).get('default',''))" 2>/dev/null || echo "")
  fi
fi

if [[ -z "$PROJECT" ]]; then
  echo "ERROR: Firebase project not found. Pass --project <id> or set FIREBASE_PROJECT env var."
  exit 1
fi

echo "==> Checking deploy readiness for project: $PROJECT"
echo ""

PASS=0
FAIL=0

check() {
  local label="$1"
  local result="$2"
  if [[ "$result" == "ok" ]]; then
    echo "  [PASS] $label"
    ((PASS++)) || true
  else
    echo "  [FAIL] $label — $result"
    ((FAIL++)) || true
  fi
}

# 1. Check OPENAI_API_KEY in Secret Manager
echo "--- Secret Manager ---"
if gcloud secrets describe OPENAI_API_KEY --project="$PROJECT" &>/dev/null; then
  check "OPENAI_API_KEY exists in Secret Manager" "ok"
else
  check "OPENAI_API_KEY exists in Secret Manager" \
    "NOT FOUND. Create it: gcloud secrets create OPENAI_API_KEY --project=$PROJECT && echo -n '<key>' | gcloud secrets versions add OPENAI_API_KEY --data-file=- --project=$PROJECT"
fi

# CLAUDE_API_KEY is optional (fallback provider); warn but don't fail
if gcloud secrets describe CLAUDE_API_KEY --project="$PROJECT" &>/dev/null; then
  check "CLAUDE_API_KEY exists in Secret Manager (optional fallback)" "ok"
else
  echo "  [WARN] CLAUDE_API_KEY not found — Claude fallback disabled. Add when available."
fi

echo ""
echo "--- Firestore indexes file ---"
if python3 -c "
import json, sys
data = json.load(open('firestore.indexes.json'))
groups = [i['collectionGroup'] for i in data.get('indexes', [])]
missing = [g for g in ['summaries', 'insights', 'memory'] if g not in groups]
sys.exit(1 if missing else 0)
" 2>/dev/null; then
  check "ConversationOS indexes present (summaries, insights, memory)" "ok"
else
  check "ConversationOS indexes present (summaries, insights, memory)" \
    "One or more ConversationOS indexes missing from firestore.indexes.json"
fi

echo ""
echo "--- Remote Config template ---"
if [[ -f remoteconfig.template.json ]]; then
  check "remoteconfig.template.json exists" "ok"
  # Verify sensitive space restriction defaults to true
  SENSITIVE_DEFAULT=$(python3 -c "
import json
d = json.load(open('remoteconfig.template.json'))
val = d.get('parameters', {}).get('conversation_os_sensitive_space_restrictions_enabled', {}).get('defaultValue', {}).get('value', '')
print(val)
" 2>/dev/null || echo "")
  if [[ "$SENSITIVE_DEFAULT" == "true" ]]; then
    check "conversation_os_sensitive_space_restrictions_enabled defaults to true" "ok"
  else
    check "conversation_os_sensitive_space_restrictions_enabled defaults to true" \
      "Default is '$SENSITIVE_DEFAULT' — MUST be true before deploy"
  fi
else
  check "remoteconfig.template.json exists" "NOT FOUND — create it before deploying Remote Config"
fi

echo ""
echo "--- Functions source ---"
if [[ -f functions/conversationOSFunctions.js ]]; then
  check "conversationOSFunctions.js present" "ok"
else
  check "conversationOSFunctions.js present" "NOT FOUND in functions/"
fi

EXPORTS_COUNT=$(grep -c "conversationOSFns\." functions/index.js 2>/dev/null || echo 0)
if [[ "$EXPORTS_COUNT" -ge 8 ]]; then
  check "All 8 ConversationOS callables exported in index.js" "ok"
else
  check "All 8 ConversationOS callables exported in index.js" \
    "Only $EXPORTS_COUNT found — expected 8"
fi

echo ""
echo "================================"
echo "  PASS: $PASS   FAIL: $FAIL"
echo "================================"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "Fix all FAILs before deploying."
  exit 1
else
  echo "All checks passed. Safe to deploy:"
  echo ""
  echo "  firebase deploy --only functions,firestore:rules,firestore:indexes,remoteconfig \\"
  echo "    --project $PROJECT"
  echo ""
fi
