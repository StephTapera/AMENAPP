#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS="$ROOT/AMEN_FINAL_10_GO_RESULTS/trust_safety"
mkdir -p "$RESULTS"

echo "Amen Trust and Safety 10/10 technical verification"
echo "Results: $RESULTS"

echo ""
echo "1) Backend typecheck"
(
  cd "$ROOT/Backend/functions"
  npm run typecheck
) | tee "$RESULTS/backend_typecheck.log"

echo ""
echo "2) Backend tests"
(
  cd "$ROOT/Backend/functions"
  npm test -- --runInBand
) | tee "$RESULTS/backend_tests.log"

echo ""
echo "3) Rules launch gates"
(
  cd "$ROOT/Backend/rules-tests"
  npm run test:launch-gates
) | tee "$RESULTS/rules_launch_gates.log"

echo ""
echo "4) Direct report write scan"
REPORT_SCAN="$RESULTS/direct_report_write_scan.txt"
grep -RInE 'collection\("reports"\)|collection\(FirebaseManager\.CollectionPath\.reports\)|collection\("userReports"\)\.(addDocument|document\(|setData)' \
  "$ROOT/AMENAPP" \
  --include="*.swift" \
  > "$REPORT_SCAN" || true
if [ -s "$REPORT_SCAN" ]; then
  echo "FAIL: direct report writes found:"
  cat "$REPORT_SCAN"
  exit 1
fi
echo "PASS: no direct Swift writes to reports/userReports."

echo ""
echo "5) Production provider configuration"
if [ "${REQUIRE_PRODUCTION_SECRETS:-0}" = "1" ]; then
  required_env=(
    REQUIRE_MEDIA_MODERATION_PROVIDERS
    CSAM_HASH_LOOKUP_URL
    CSAM_HASH_LOOKUP_TOKEN
    PERSPECTIVE_API_KEY
  )
  for key in "${required_env[@]}"; do
    if [ -z "${!key:-}" ]; then
      echo "FAIL: missing required production environment variable: $key"
      exit 1
    fi
  done
  if [ "${REQUIRE_MEDIA_MODERATION_PROVIDERS}" != "true" ]; then
    echo "FAIL: REQUIRE_MEDIA_MODERATION_PROVIDERS must be true in production."
    exit 1
  fi
  echo "PASS: required production provider environment is present."
else
  echo "SKIP: set REQUIRE_PRODUCTION_SECRETS=1 to enforce provider secret presence in this shell."
fi

echo ""
echo "6) Signoff artifact check"
SIGNOFF="$ROOT/Docs/TRUST_SAFETY_PRODUCTION_SIGNOFF.md"
if [ ! -f "$SIGNOFF" ]; then
  echo "FAIL: missing $SIGNOFF"
  exit 1
fi
echo "PASS: signoff artifact exists. Human approvals must be completed before production launch."

echo ""
echo "Technical verification complete."
