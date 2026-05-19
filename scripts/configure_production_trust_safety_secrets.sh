#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

if ! command -v firebase >/dev/null 2>&1; then
  echo "FAIL: firebase CLI is required. Install firebase-tools or run npm install in Backend/rules-tests."
  exit 1
fi

PROJECT_ID="${FIREBASE_PROJECT_ID:-}"
if [ -z "$PROJECT_ID" ]; then
  echo "FAIL: set FIREBASE_PROJECT_ID to the production Firebase project id."
  exit 1
fi

echo "Configuring production Trust and Safety secrets for Firebase project: $PROJECT_ID"
echo "Secret values are entered through the Firebase CLI and are not written to this repo."
echo ""

required_secrets=(
  CSAM_HASH_LOOKUP_TOKEN
  PERSPECTIVE_API_KEY
)

optional_payment_secrets=(
  STRIPE_SECRET_KEY
  STRIPE_COVENANT_WEBHOOK_SECRET
)

for secret_name in "${required_secrets[@]}"; do
  echo "Setting required secret: $secret_name"
  firebase --project "$PROJECT_ID" functions:secrets:set "$secret_name"
done

if [ "${CONFIGURE_PAYMENT_SECRETS:-0}" = "1" ]; then
  for secret_name in "${optional_payment_secrets[@]}"; do
    echo "Setting payment secret: $secret_name"
    firebase --project "$PROJECT_ID" functions:secrets:set "$secret_name"
  done
else
  echo "Skipping payment secrets. Set CONFIGURE_PAYMENT_SECRETS=1 when Covenant payments are enabled."
fi

echo ""
echo "Required non-secret production environment values to configure in the deployed function environment:"
echo "REQUIRE_MEDIA_MODERATION_PROVIDERS=true"
echo "CSAM_HASH_LOOKUP_URL=<restricted provider endpoint>"
echo "PERSPECTIVE_API_URL=https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze"
echo ""
echo "After deployment, run:"
echo "REQUIRE_PRODUCTION_SECRETS=1 \\"
echo "REQUIRE_MEDIA_MODERATION_PROVIDERS=true \\"
echo "CSAM_HASH_LOOKUP_URL=<production endpoint> \\"
echo "CSAM_HASH_LOOKUP_TOKEN=<available in deployment environment> \\"
echo "PERSPECTIVE_API_KEY=<available in deployment environment> \\"
echo "scripts/verify_trust_safety_10_go.sh"
