#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS="$ROOT/AMEN_FINAL_10_GO_RESULTS/app_store_release"
mkdir -p "$RESULTS"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

echo "Amen App Store production readiness verification"
echo "Results: $RESULTS"

require_marker() {
  local file="$1"
  local marker="$2"
  if ! grep -q "^${marker}$" "$file"; then
    echo "FAIL: missing marker in $file: $marker"
    exit 1
  fi
}

require_nonempty_marker() {
  local file="$1"
  local key="$2"
  local value
  value="$(grep "^${key}=" "$file" | tail -1 | cut -d= -f2- || true)"
  if [ -z "$value" ]; then
    echo "FAIL: missing value for $key in $file"
    exit 1
  fi
  if [[ "$value" == \<* ]]; then
    echo "FAIL: placeholder value for $key in $file"
    exit 1
  fi
}

require_https_marker() {
  local file="$1"
  local key="$2"
  local value
  value="$(grep "^${key}=" "$file" | tail -1 | cut -d= -f2- || true)"
  if [[ ! "$value" =~ ^https://[^[:space:]]+$ ]]; then
    echo "FAIL: $key must be a public https URL in $file"
    exit 1
  fi
}

echo ""
echo "1) Trust and Safety production gate"
REQUIRE_PRODUCTION_SECRETS=1 "$ROOT/scripts/verify_trust_safety_10_go.sh" | tee "$RESULTS/trust_safety_production_gate.log"

SIGNOFF="$ROOT/Docs/TRUST_SAFETY_PRODUCTION_SIGNOFF.md"
PRIVACY="$ROOT/Docs/APP_STORE_PRIVACY_LABEL_MAPPING.md"
REVIEW_NOTES="$ROOT/Docs/APP_REVIEW_NOTES.md"
SAFETY_CONTACT="$ROOT/Docs/PUBLISHED_SAFETY_CONTACT_RECORD.md"
FIREBASE_RECORD="$ROOT/Docs/PRODUCTION_FIREBASE_RELEASE_RECORD.md"
ARCHIVE_RECORD="$ROOT/Docs/RELEASE_ARCHIVE_TEST_RECORD.md"

for file in "$SIGNOFF" "$PRIVACY" "$REVIEW_NOTES" "$SAFETY_CONTACT" "$FIREBASE_RECORD" "$ARCHIVE_RECORD"; do
  if [ ! -f "$file" ]; then
    echo "FAIL: missing release artifact: $file"
    exit 1
  fi
done

echo ""
echo "2) Human signoff"
require_marker "$SIGNOFF" "APPROVAL_STATUS=GO"
require_marker "$SIGNOFF" "ENGINEERING_APPROVED=true"
require_marker "$SIGNOFF" "TRUST_SAFETY_APPROVED=true"
require_marker "$SIGNOFF" "LEGAL_PRIVACY_APPROVED=true"
require_marker "$SIGNOFF" "APP_STORE_RELEASE_APPROVED=true"
echo "PASS: required signoff markers are complete."

echo ""
echo "3) App Store privacy labels and review notes"
require_marker "$PRIVACY" "APP_STORE_PRIVACY_LABELS_REVIEWED=true"
require_nonempty_marker "$PRIVACY" "APP_STORE_PRIVACY_LABELS_OWNER"
require_nonempty_marker "$PRIVACY" "APP_STORE_PRIVACY_LABELS_REVIEW_DATE"
require_marker "$REVIEW_NOTES" "APP_REVIEW_NOTES_FINAL=true"
require_nonempty_marker "$REVIEW_NOTES" "APP_REVIEW_NOTES_OWNER"
require_nonempty_marker "$REVIEW_NOTES" "APP_REVIEW_NOTES_REVIEW_DATE"
for required_text in "Report and block" "child-safety" "AI safety" "Delete account"; do
  if ! grep -qi "$required_text" "$REVIEW_NOTES"; then
    echo "FAIL: App Review notes missing required topic: $required_text"
    exit 1
  fi
done
echo "PASS: App Store privacy/review artifacts are marked final."

echo ""
echo "4) Published safety contact"
require_marker "$SAFETY_CONTACT" "SAFETY_CONTACT_PAGE_LIVE=true"
require_https_marker "$SAFETY_CONTACT" "SAFETY_CONTACT_URL"
require_nonempty_marker "$SAFETY_CONTACT" "SAFETY_CONTACT_OWNER"
require_nonempty_marker "$SAFETY_CONTACT" "SAFETY_CONTACT_REVIEW_DATE"
echo "PASS: published safety contact record is complete."

echo ""
echo "5) Production Firebase/App Check deployment"
require_nonempty_marker "$FIREBASE_RECORD" "FIREBASE_PRODUCTION_PROJECT_ID"
require_nonempty_marker "$FIREBASE_RECORD" "FIREBASE_DEPLOYED_PROJECT_ID"
expected_project="$(grep "^FIREBASE_PRODUCTION_PROJECT_ID=" "$FIREBASE_RECORD" | tail -1 | cut -d= -f2-)"
deployed_project="$(grep "^FIREBASE_DEPLOYED_PROJECT_ID=" "$FIREBASE_RECORD" | tail -1 | cut -d= -f2-)"
if [ "$expected_project" != "$deployed_project" ]; then
  echo "FAIL: deployed Firebase project does not match expected production project."
  exit 1
fi
require_marker "$FIREBASE_RECORD" "FIREBASE_RULES_DEPLOYED=true"
require_marker "$FIREBASE_RECORD" "FIREBASE_FUNCTIONS_DEPLOYED=true"
require_marker "$FIREBASE_RECORD" "FIREBASE_STORAGE_RULES_DEPLOYED=true"
require_marker "$FIREBASE_RECORD" "FIREBASE_DATABASE_RULES_DEPLOYED=true"
require_marker "$FIREBASE_RECORD" "FIREBASE_HOSTING_DEPLOYED=true"
require_marker "$FIREBASE_RECORD" "APP_CHECK_PRODUCTION_ENFORCED=true"
require_marker "$FIREBASE_RECORD" "PRODUCTION_MODERATION_PROVIDERS_CONFIGURED=true"
require_nonempty_marker "$FIREBASE_RECORD" "PRODUCTION_FIREBASE_RELEASE_OWNER"
require_nonempty_marker "$FIREBASE_RECORD" "PRODUCTION_FIREBASE_RELEASE_DATE"
echo "PASS: Firebase/App Check deployment record is complete."

echo ""
echo "6) Release archive and smoke test"
require_marker "$ARCHIVE_RECORD" "RELEASE_ARCHIVE_CREATED=true"
require_marker "$ARCHIVE_RECORD" "RELEASE_ARCHIVE_TESTED=true"
require_nonempty_marker "$ARCHIVE_RECORD" "RELEASE_ARCHIVE_SCHEME"
require_nonempty_marker "$ARCHIVE_RECORD" "RELEASE_ARCHIVE_BUILD_NUMBER"
require_nonempty_marker "$ARCHIVE_RECORD" "RELEASE_ARCHIVE_TEST_DEVICE_OR_SIMULATOR"
require_nonempty_marker "$ARCHIVE_RECORD" "RELEASE_ARCHIVE_OWNER"
require_nonempty_marker "$ARCHIVE_RECORD" "RELEASE_ARCHIVE_DATE"
echo "PASS: release archive record is complete."

echo ""
echo "APP STORE READY: all production release gates are complete."
