#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR/Backend/functions"
npm run typecheck -- --pretty false

cd "$ROOT_DIR"
firebase deploy \
  --only functions:processAmenIntelligenceSnapshot,functions:processAmenIntelligenceAuditEvent,firestore:rules
