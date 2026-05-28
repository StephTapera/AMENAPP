#!/usr/bin/env bash
# deploy-verification.sh
#
# Deploys System 39 (Verification & Trust) to Firebase.
# Run from the Backend/ directory: bash deploy-verification.sh
#
# Prerequisites:
#   - firebase CLI installed: npm install -g firebase-tools
#   - Logged in: firebase login
#   - firebase use <your-project-id>
#
# KYC provider config (set before running, or set manually via console):
#   PERSONA: firebase functions:config:set kyc.provider="persona" kyc.persona_api_key="..." kyc.persona_template_id="itmpl_..." kyc.persona_webhook_secret="..."
#   STRIPE:  firebase functions:config:set kyc.provider="stripe" kyc.stripe_secret_key="sk_live_..." kyc.stripe_webhook_secret="whsec_..."

set -euo pipefail

echo "=== Amen System 39: Verification & Trust Deployment ==="
echo ""

# ── 1. Deploy Firestore rules (zero downtime, fail-closed protections first) ──
echo "Step 1/4: Deploying Firestore rules..."
firebase deploy --only firestore:rules
echo "✅ Firestore rules deployed"
echo ""

# ── 2. Run tests before deploying functions ───────────────────────────────────
echo "Step 2/4: Running backend tests..."
cd functions
npm test -- --passWithNoTests
cd ..
echo "✅ All tests passed"
echo ""

# ── 3. Deploy Cloud Functions ─────────────────────────────────────────────────
echo "Step 3/4: Deploying Cloud Functions..."
firebase deploy --only functions:startIdentityVerification,\
functions:handleIdentityVerificationWebhook,\
functions:requestOrganizationVerification,\
functions:verifyOrganizationDomain,\
functions:requestRoleVerification,\
functions:approveRoleVerification,\
functions:revokeRoleVerification,\
functions:requestCreatorVerification,\
functions:refreshVerificationSummary,\
functions:reportImpersonation
echo "✅ Cloud Functions deployed"
echo ""

# ── 4. Remote Config reminder ─────────────────────────────────────────────────
echo "Step 4/4: Remote Config"
echo ""
echo "All System 39 feature flags default to false (fail-closed)."
echo "To enable for internal beta, import this template in the Firebase console:"
echo "  Backend/remote-config-verification-template.json"
echo ""
echo "Staged rollout order:"
echo "  1. verification_center_enabled = true  (shows the center, no flows yet)"
echo "  2. organization_verification_enabled = true  (domain email challenge, no KYC)"
echo "  3. role_verification_enabled = true"
echo "  4. creator_verification_enabled = true  (requires identity first)"
echo "  5. public_trust_badges_enabled = true  (shows badges once users are verified)"
echo "  6. impersonation_reports_enabled = true  (once moderation queue is staffed)"
echo "  7. identity_verification_enabled = true  (LAST — only after KYC provider is tested)"
echo ""
echo "=== Deployment complete ==="
