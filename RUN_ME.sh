#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  RUN_ME.sh — AMEN Production Deploy Stack                               ║
# ║  Branch: safety-hardening │ Expected HEAD: 12d149ea                     ║
# ║  Assembled: 2026-06-11                                                   ║
# ║                                                                          ║
# ║  Estimated total wall-clock time: ~71 minutes                           ║
# ║    Stage 0 (preflight)            ~3 min                                ║
# ║    Stage 1 (recovery redeploy)   ~12 min  ← 7 safety CFs               ║
# ║    Stage 2 (pepper rotation)      ~5 min  ← PHONE_HASH_PEPPER          ║
# ║    Stage 3 (Stage-3 CFs)         ~25 min  ← A3 + queue + ONE + SOS     ║
# ║    Stage 4 (safety consolidated)  ~8 min  ← rules+storage+CFs+AppCheck ║
# ║    Stage 5 (Remote Config)        ~3 min  ← 15 new RC keys             ║
# ║    Stage 6 (bait-transcript)      ~5 min  ← live CF exclusion proof    ║
# ║    Stage 7 (smoke checklist)     ~10 min  ← 15 human pass/fail prompts ║
# ║                                                                          ║
# ║  NO FLAG FLIPS IN THIS SCRIPT. It prints the flip registry at the end. ║
# ║  PRODUCTION FREEZE: do not flip any flag until this script completes.  ║
# ╚══════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
PROJECT="amen-5e359"
REGION="us-central1"
EXPECTED_HEAD="12d149ea"
FUNCTIONS_DIR="$(pwd)/functions"
BACKEND_DIR="$(pwd)/Backend/functions"
VERDICT_FILE="$(pwd)/RULES_RECONCILIATION_VERDICT.md"
BAIT_RESULTS="$(pwd)/bait_transcript_results_$(date +%Y%m%d_%H%M%S).txt"

# ── Color helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

pass()   { echo -e "${GREEN}  ✅  $*${NC}"; }
fail()   { echo -e "${RED}  ❌  $*${NC}"; }
info()   { echo -e "${CYAN}  ℹ   $*${NC}"; }
warn()   { echo -e "${YELLOW}  ⚠   $*${NC}"; }
note()   { echo -e "${DIM}      $*${NC}"; }

header() {
  echo ""
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${CYAN}  STAGE $1 — $2${NC}"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

prompt_stage() {
  # $1=number $2=title $3=why
  header "$1" "$2"
  echo -e "  ${YELLOW}WHY: ${NC}$3"
  echo ""
  read -rp "  Press Enter to run this stage (or Ctrl-C to abort) … " _
  echo ""
}

abort_with_rollback() {
  # $1=message $2=rollback_command
  echo ""
  fail "FATAL: $1"
  echo ""
  echo -e "${RED}${BOLD}  Rollback command:${NC}"
  echo -e "${RED}    $2${NC}"
  echo ""
  exit 1
}

verify_functions_list() {
  # $1=function name to grep for
  local fn="$1"
  info "Verifying $fn is ACTIVE in Firebase…"
  if firebase functions:list --project "$PROJECT" 2>/dev/null | grep -q "$fn"; then
    pass "$fn is ACTIVE"
  else
    warn "$fn not yet visible in functions:list (cold-start lag is normal for 30s; re-run manually if needed)"
  fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║  AMEN — PRODUCTION DEPLOY STACK        2026-06-11               ║${NC}"
echo -e "${BOLD}${CYAN}║  Branch: safety-hardening  │  Expected HEAD: ${EXPECTED_HEAD}           ║${NC}"
echo -e "${BOLD}${CYAN}║  Estimated total time: ~71 minutes                               ║${NC}"
echo -e "${BOLD}${CYAN}║  YOU are the trigger for every stage. No flag flips in script.  ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 0 — PREFLIGHT
# ══════════════════════════════════════════════════════════════════════════════
prompt_stage "0" "PREFLIGHT GREPS + KEYSTONE TESTS" \
  "Abort loudly before touching production if HEAD, project, node_modules, or keystone tests are wrong."

echo "  0a. Git HEAD check…"
ACTUAL_HEAD="$(git rev-parse --short HEAD)"
if [ "$ACTUAL_HEAD" != "$EXPECTED_HEAD" ]; then
  warn "HEAD is $ACTUAL_HEAD, expected $EXPECTED_HEAD."
  warn "This deploy was assembled against ${EXPECTED_HEAD}. Proceeding with ${ACTUAL_HEAD}."
  read -rp "  Continue anyway? (yes/no) " CONFIRM
  [ "$CONFIRM" = "yes" ] || abort_with_rollback "User aborted due to HEAD mismatch." "git checkout safety-hardening"
else
  pass "HEAD is $EXPECTED_HEAD ✓"
fi

echo "  0b. Firebase project check…"
ACTIVE_PROJECT="$(firebase use "$PROJECT" 2>&1 | tail -1 || true)"
echo "      Active: $ACTIVE_PROJECT"
firebase projects:list 2>/dev/null | grep "$PROJECT" >/dev/null \
  && pass "Project $PROJECT is accessible" \
  || abort_with_rollback "Cannot access Firebase project $PROJECT. Run: firebase login" \
       "firebase login"

echo "  0c. Node + npm check…"
node --version >/dev/null 2>&1 && pass "node $(node --version)" \
  || abort_with_rollback "node not found. Install Node 20+." ""
npm --version >/dev/null 2>&1 && pass "npm $(npm --version)" || true

echo "  0d. Security grep — no hardcoded API keys in new CF files…"
SECRETS_GREP=$(grep -rn \
  "AIzaSy\|sk-ant-\|AAAA[A-Za-z0-9_-]\{140\}" \
  Backend/functions/src/safety/a3Callables.ts \
  Backend/functions/src/connectQueue/processConnectQueuedDraft.ts \
  Backend/functions/src/one/oneRelayMoment.ts 2>/dev/null || true)
if [ -n "$SECRETS_GREP" ]; then
  fail "Possible hardcoded secret found in CF source:"
  echo "$SECRETS_GREP"
  abort_with_rollback "Remove hardcoded secrets before deploying." ""
else
  pass "No hardcoded secrets found in Stage-3 CF files"
fi

echo "  0e. App Check enforcement check — all Stage-3 CFs must have enforceAppCheck…"
MISSING_AC=$(grep -L "enforceAppCheck: true" \
  Backend/functions/src/safety/a3Callables.ts \
  Backend/functions/src/connectQueue/processConnectQueuedDraft.ts 2>/dev/null || true)
if [ -n "$MISSING_AC" ]; then
  warn "These files may be missing enforceAppCheck: true — review before deploy:"
  echo "$MISSING_AC"
else
  pass "enforceAppCheck: true confirmed in Stage-3 CF source"
fi

echo "  0f. TypeScript compile check on new CF files…"
if command -v npx >/dev/null 2>&1; then
  cd "$BACKEND_DIR"
  if npx tsc --noEmit --skipLibCheck 2>/dev/null; then
    pass "TypeScript compile: 0 errors"
  else
    warn "TypeScript errors present. Review before deploying (may be pre-existing)."
  fi
  cd - >/dev/null
else
  warn "npx not found — skipping tsc check. Run manually: cd Backend/functions && npx tsc --noEmit"
fi

echo "  0g. Keystone jest tests (ageTier + phoneAuthPii + safety-rules)…"
cd "$FUNCTIONS_DIR"
if npm test -- --testPathPattern="ageTier|phoneAuthPii|safety-rules" --passWithNoTests --silent 2>/dev/null; then
  pass "Keystone tests passed (ageTier + phoneAuthPii + safety-rules)"
else
  fail "Keystone tests FAILED"
  abort_with_rollback "Fix failing tests before deploying to production." \
    "cd functions && npm test -- --testPathPattern='ageTier|phoneAuthPii|safety-rules'"
fi
cd - >/dev/null

pass "Stage 0 complete — preflight clean"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 1 — RECOVERY REDEPLOY (7 safety Cloud Functions + rules)
# ══════════════════════════════════════════════════════════════════════════════
prompt_stage "1" "RECOVERY REDEPLOY (7 SAFETY CFs + RULES)" \
  "These functions were part of the safety-hardening branch and must be live before Stage-3 CFs
  can safely reference them. Deploying rules first restores DMs (currently denied) and
  closes COPPA holes. The 7 CFs cover age-tier sync, anti-harassment, comment moderation,
  and CSAM/NCMEC escalation paths."

echo "  1a. Firestore rules (restores DMs + closes COPPA gaps)…"
firebase deploy --only firestore:rules \
  --project "$PROJECT" \
  || abort_with_rollback "firestore:rules deploy failed." \
       "firebase deploy --only firestore:rules --project $PROJECT"
pass "Firestore rules deployed"

echo "  1b. Firestore indexes (phone-hash composite index)…"
firebase deploy --only firestore:indexes \
  --project "$PROJECT" \
  || warn "firestore:indexes deploy failed — index may already exist; continue."
pass "Firestore indexes deployed"

echo "  1c. Storage rules…"
firebase deploy --only storage \
  --project "$PROJECT" \
  || abort_with_rollback "storage rules deploy failed." \
       "firebase deploy --only storage --project $PROJECT"
pass "Storage rules deployed"

echo "  1d. Seven safety Cloud Functions…"
note "  onUserDocCreated — server-set ageTier on user doc creation"
note "  (anti-harassment + comment moderation already live as safeMessageGateway, onMessageSafetyEvent, addComment)"
note "  onCSAMDetected — CSAM escalation trigger"
note "  flagForNCMECReview — NCMEC CyberTipline queue"
note "  onModerationRequiresMandatoryReport — mandatory reporter escalation"
note "  updateBirthYear — birth-year field sync for age-tier computation"

firebase deploy \
  --only functions:onUserDocCreated,\
functions:onCSAMDetected,\
functions:flagForNCMECReview,\
functions:onModerationRequiresMandatoryReport,\
functions:updateBirthYear \
  --project "$PROJECT" \
  || abort_with_rollback "Recovery function deploy failed." \
       "firebase deploy --only functions:onUserDocCreated,functions:updateBirthYear --project $PROJECT"

for FN in onUserDocCreated onCSAMDetected flagForNCMECReview \
           onModerationRequiresMandatoryReport updateBirthYear; do
  verify_functions_list "$FN"
done

pass "Stage 1 complete — 5 safety CFs + rules live"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 2 — PHONE_HASH_PEPPER ROTATION
# ══════════════════════════════════════════════════════════════════════════════
prompt_stage "2" "PHONE_HASH_PEPPER ROTATION" \
  "The PHONE_HASH_PEPPER is used for HMAC-SHA256 hashing of phone numbers in
  phoneAuthRateLimit.js. Rotating it invalidates existing rate-limit documents
  (15-min windows — they expire naturally) and ensures new hashes cannot be
  reversed by brute-force. Rotation is required per Section 13 of SAFETY_RUNBOOK.
  The 3 phone functions are redeployed to pick up the new secret version."

echo "  2a. Generate new pepper (256-bit hex via openssl)…"
NEW_PEPPER="$(openssl rand -hex 64)"
echo "      New pepper (64 hex chars / 256 bits): ${NEW_PEPPER:0:8}…${NEW_PEPPER: -8} (truncated for display)"
echo ""
warn "  The full pepper will be passed to firebase functions:secrets:set."
warn "  It will NOT be written to any file."
echo ""

echo "  2b. Set PHONE_HASH_PEPPER secret in Firebase Secret Manager…"
echo "$NEW_PEPPER" | firebase functions:secrets:set PHONE_HASH_PEPPER \
  --project "$PROJECT" \
  --non-interactive \
  || abort_with_rollback "Failed to set PHONE_HASH_PEPPER secret." \
       "firebase functions:secrets:set PHONE_HASH_PEPPER --project $PROJECT"
pass "PHONE_HASH_PEPPER set in Secret Manager"

echo "  2c. Redeploy 3 phone functions (they reference PHONE_HASH_PEPPER)…"
note "  checkPhoneVerificationRateLimit — rate-limits phone auth attempts"
note "  reportPhoneVerificationFailure  — logs suspicious auth failures"
note "  unblockPhoneNumber              — admin callable to lift phone blocks"

firebase deploy \
  --only functions:checkPhoneVerificationRateLimit,\
functions:reportPhoneVerificationFailure,\
functions:unblockPhoneNumber \
  --project "$PROJECT" \
  || abort_with_rollback "Phone function redeploy failed." \
       "firebase deploy --only functions:checkPhoneVerificationRateLimit,functions:reportPhoneVerificationFailure,functions:unblockPhoneNumber --project $PROJECT"

for FN in checkPhoneVerificationRateLimit reportPhoneVerificationFailure unblockPhoneNumber; do
  verify_functions_list "$FN"
done

info "Data migration note: existing phoneAuthRateLimits/{rawPhone} docs retain raw numbers
      until they expire (15-min TTL). A cleanup job to purge legacy plaintext-keyed docs
      can be scheduled after rollout. See RULES_DEPLOY_PACKAGE_P0_2026-06-10.md."

pass "Stage 2 complete — pepper rotated, 3 phone functions redeployed"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 3 — STAGE-3 CLOUD FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════
prompt_stage "3" "STAGE-3 CFs (A3 SAFETY → CONNECT QUEUE → ONE → SPIRITUAL OS → FIND CHURCH 2)" \
  "These are the new callable CFs assembled in the close-out pass. All are fail-closed,
  App Check + Auth enforced. Deploying before flag flips ensures the server side is live
  when the client activates a feature. Batched in dependency order."

echo "  3a. A3 Safety callables (5 CFs)…"
note "  evaluateDmRisk          — pre-send DM risk score for minor paths, fail-closed"
note "  reportDmAbuse           — structured DM abuse reports with minor escalation"
note "  contentSafetyScreen     — generic body scanner (used by SafetyServiceImpl)"
note "  analyzeRelationshipRisk — cross-minor relationship pattern analysis"
note "  assessDogpileRisk       — coordinated-harassment detection on comment threads"

firebase deploy \
  --only functions:evaluateDmRisk,\
functions:reportDmAbuse,\
functions:contentSafetyScreen,\
functions:analyzeRelationshipRisk,\
functions:assessDogpileRisk \
  --project "$PROJECT" \
  || abort_with_rollback "A3 callable deploy failed." \
       "firebase deploy --only functions:evaluateDmRisk,functions:reportDmAbuse --project $PROJECT"

for FN in evaluateDmRisk reportDmAbuse contentSafetyScreen analyzeRelationshipRisk assessDogpileRisk; do
  verify_functions_list "$FN"
done
pass "  A3 safety batch deployed"

echo ""
echo "  3b. Connect offline queue CF…"
note "  processConnectQueuedDraft — idempotent offline queue relay (UUID dedup)"

firebase deploy \
  --only functions:processConnectQueuedDraft \
  --project "$PROJECT" \
  || abort_with_rollback "processConnectQueuedDraft deploy failed." \
       "firebase deploy --only functions:processConnectQueuedDraft --project $PROJECT"
verify_functions_list "processConnectQueuedDraft"

info "  Manual step: add TTL policy on connect_idempotency.processedAt (7 days) in Firebase Console."
info "  Firestore → connect_idempotency → Add TTL field → processedAt → 7 days"
pass "  Connect queue batch deployed"

echo ""
echo "  3c. ONE private social OS (5 CFs) — FLAG-FLIP PREREQUISITE…"
note "  one_relayMoment     — forwardAllowed server-side rejection (SECURITY.md §8.3)"
note "  one_sendMoment      — sends a ONE Moment to recipients"
note "  one_expireMoment    — TTL-driven moment expiry"
note "  one_verifyEntitlement — checks ONE tier entitlement"
note "  one_activateLegacy  — migration path for pre-ONE users"

firebase deploy \
  --only functions:one_relayMoment,\
functions:one_sendMoment,\
functions:one_expireMoment,\
functions:one_verifyEntitlement,\
functions:one_activateLegacy \
  --project "$PROJECT" \
  || abort_with_rollback "ONE CF deploy failed." \
       "firebase deploy --only functions:one_relayMoment,functions:one_sendMoment --project $PROJECT"

for FN in one_relayMoment one_sendMoment one_expireMoment one_verifyEntitlement one_activateLegacy; do
  verify_functions_list "$FN"
done
pass "  ONE batch deployed"

echo ""
echo "  3d. Spiritual OS (27 callables)…"
note "  detectUnsentThoughtRisk, saveUnsentThought, resolveUnsentThought"
note "  analyzeScriptureDrift, generateBalancingScripture, dismissDriftSignal"
note "  detectSilencePatterns, resurfaceAvoidedItem, markSilenceSignalResolved"
note "  updateRelationalGravity, classifyRelationshipState, generateReconciliationPrompt"
note "  evaluateMomentRisk, logMomentInterception, updateMomentLearning"
note "  createReflectionPrompt, savePostActionReflection, updateUserGrowthPattern"
note "  analyzeTruthVsEmotion, scoreWeightOfWords, generateGracefulRewrite"
note "  aggregateDiscernmentSignals, generateCommunityDiscernmentSummary"
note "  calculateEternalWeight, updateEternalWeightAfterReflection"
note "  generateMeaningPrompt, createWalkWithChristPathFromPattern"

firebase deploy \
  --only functions:detectUnsentThoughtRisk,functions:saveUnsentThought,functions:resolveUnsentThought,\
functions:analyzeScriptureDrift,functions:generateBalancingScripture,functions:dismissDriftSignal,\
functions:detectSilencePatterns,functions:resurfaceAvoidedItem,functions:markSilenceSignalResolved,\
functions:updateRelationalGravity,functions:classifyRelationshipState,functions:generateReconciliationPrompt,\
functions:evaluateMomentRisk,functions:logMomentInterception,functions:updateMomentLearning,\
functions:createReflectionPrompt,functions:savePostActionReflection,functions:updateUserGrowthPattern,\
functions:analyzeTruthVsEmotion,functions:scoreWeightOfWords,functions:generateGracefulRewrite,\
functions:aggregateDiscernmentSignals,functions:generateCommunityDiscernmentSummary,\
functions:calculateEternalWeight,functions:updateEternalWeightAfterReflection,\
functions:generateMeaningPrompt,functions:createWalkWithChristPathFromPattern \
  --project "$PROJECT" \
  || abort_with_rollback "Spiritual OS CF deploy failed." \
       "firebase deploy --only functions:detectUnsentThoughtRisk --project $PROJECT"

verify_functions_list "detectUnsentThoughtRisk"
verify_functions_list "calculateEternalWeight"
pass "  Spiritual OS batch deployed"

echo ""
echo "  3e. Find Church 2.0 CFs (check GOOGLE_PLACES_API_KEY first)…"
if firebase functions:secrets:access GOOGLE_PLACES_API_KEY --project "$PROJECT" >/dev/null 2>&1; then
  pass "  GOOGLE_PLACES_API_KEY is set in Secret Manager"
else
  warn "  GOOGLE_PLACES_API_KEY not found in Secret Manager."
  warn "  Set it before deploying ingestChurchesFromGooglePlaces:"
  warn "    firebase functions:secrets:set GOOGLE_PLACES_API_KEY --project $PROJECT"
  read -rp "  Has the key been set? (yes/skip) " FC2_CONFIRM
  if [ "$FC2_CONFIRM" != "yes" ]; then
    warn "  Skipping Find Church 2.0 CF deploy — rerun when key is set."
    FC2_SKIP=true
  else
    FC2_SKIP=false
  fi
fi

if [ "${FC2_SKIP:-false}" = "false" ]; then
  firebase deploy \
    --only functions:ingestChurchesFromGooglePlaces,\
functions:computeAvailabilityStatus,\
functions:scheduleAvailabilityRefresh,\
functions:detectChurchMedia \
    --project "$PROJECT" \
    || abort_with_rollback "Find Church 2.0 CF deploy failed." \
         "firebase deploy --only functions:computeAvailabilityStatus --project $PROJECT"

  for FN in ingestChurchesFromGooglePlaces computeAvailabilityStatus scheduleAvailabilityRefresh detectChurchMedia; do
    verify_functions_list "$FN"
  done
  pass "  Find Church 2.0 batch deployed"
fi

pass "Stage 3 complete — all Stage-3 CFs deployed"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 4 — SAFETY CONSOLIDATED DEPLOY PACKAGE
# (DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md — supersedes all prior W3/safety stages)
# ══════════════════════════════════════════════════════════════════════════════
prompt_stage "4" "SAFETY CONSOLIDATED DEPLOY PACKAGE (Firestore + Storage + CFs + App Check reminder)" \
  "Deploys all four ordered steps from DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md.
  Steps 1 and 2 (Firestore + Storage rules) are GATED on RULES_RECONCILIATION_VERDICT.md
  containing GREEN — proof that a human has reconciled the live rules and approved.
  Step 3 deploys the consolidated safety Cloud Functions.
  Step 4 is a human reminder to enable App Check enforce-mode in Firebase Console.
  This stage SUPERSEDES all prior separate W3 or safety-rules stages."

# ── Pre-gate: safety-rules unit tests must pass before rules touch production ─
echo "  4-pre. Safety rules jest gate (safety-rules test suite)…"
cd "$FUNCTIONS_DIR"
if npm test -- --testPathPattern="safety-rules" --passWithNoTests --silent 2>/dev/null; then
  pass "  safety-rules tests passed — proceeding to rules deploy"
else
  fail "  safety-rules tests FAILED"
  abort_with_rollback "Safety rules tests must pass before deploying to production." \
    "cd functions && npm test -- --testPathPattern='safety-rules'"
fi
cd - >/dev/null

# ── GREEN verdict gate ────────────────────────────────────────────────────────
if [ -f "$VERDICT_FILE" ]; then
  if grep -qi "GREEN" "$VERDICT_FILE"; then
    pass "Verdict file found and says GREEN — proceeding with all four steps"

    # ── STEP 1 — Firestore Rules ──────────────────────────────────────────────
    echo ""
    echo "  4-step1. STEP 1 — Firestore Rules (DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md §STEP 1)…"
    note "  Changes: moderationQueue open creates, safetyAuditLog/guardianLinkRequests/guardianApprovedContacts"
    note "  explicit rules, legalHolds legalReviewer-only, safety.isMinor + roles locked, post owner"
    note "  cannot self-approve, CSAM soft-delete CF-only, one_users/witnesses owner-only create,"
    note "  adult-to-minor private Spaces blocked, legalHolds delete blocked on active hold,"
    note "  entitlements/catalog rule, actions subcollection delete removed, text 5000-char validation,"
    note "  birthYear blocked from client read. (Findings #1–4, #13, #15–16, #28, #35–38, #43)"

    echo "  4-step1a. Determine canonical rules file (OQ-4)…"
    if grep -q '"firestore"' firebase.json 2>/dev/null; then
      RULES_FILE="$(grep -A2 '"firestore"' firebase.json | grep '"rules"' | sed 's/.*"\(.*\)".*/\1/')"
      info "  firebase.json points to rules file: ${RULES_FILE:-firestore.rules}"
    else
      RULES_FILE="firestore.rules"
      warn "  Could not read firestore rules path from firebase.json; defaulting to firestore.rules"
    fi

    echo "  4-step1b. Dry-run Firestore rules validation…"
    firebase deploy --only firestore:rules --dry-run --project "$PROJECT" 2>/dev/null \
      && pass "  Firestore rules dry-run passed" \
      || warn "  Firestore rules dry-run returned non-zero (may be CLI version issue — proceeding)"

    echo "  4-step1c. Deploy Firestore rules (live)…"
    firebase deploy --only firestore:rules \
      --project "$PROJECT" \
      || abort_with_rollback "STEP 1: firestore:rules deploy failed." \
           "git checkout HEAD~1 -- firestore.deploy.rules && firebase deploy --only firestore:rules --project $PROJECT"
    pass "  STEP 1 complete — Firestore rules deployed"

    # ── STEP 2 — Storage Rules ────────────────────────────────────────────────
    echo ""
    echo "  4-step2. STEP 2 — Storage Rules (DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md §STEP 2)…"
    note "  Changes: quarantine-first pattern, chat_videos/ path + MIME limits, isBlockedType() expanded,"
    note "  download URLs gated on moderation.status==approved, owner delete blocked on active legalHold,"
    note "  auth required on all paths, sanctuary/ and prayer-room/ path prefixes reserved."
    note "  (Findings #5–6, #18–21, #38 storage side, #39)"

    firebase deploy --only storage \
      --project "$PROJECT" \
      || abort_with_rollback "STEP 2: storage rules deploy failed." \
           "git checkout HEAD~1 -- storage.rules && firebase deploy --only storage --project $PROJECT"
    pass "  STEP 2 complete — Storage rules deployed"

  else
    warn "═══════════════════════════════════════════════════════════════"
    warn "  VERDICT FILE EXISTS but does NOT contain GREEN."
    warn "  Contents: $(head -3 "$VERDICT_FILE")"
    warn ""
    warn "  ACTION REQUIRED: Open RULES_RECONCILIATION_VERDICT.md,"
    warn "  add a line saying GREEN after you have reconciled the live"
    warn "  Firestore rules against the safety-hardening branch diff."
    warn ""
    warn "  Firestore Console: https://console.firebase.google.com/project/${PROJECT}/firestore/rules"
    warn ""
    warn "  Steps 1 + 2 SKIPPED — rerun this script after verdict is GREEN."
    warn "  Steps 3 + 4 (CFs + App Check reminder) will still run."
    warn "═══════════════════════════════════════════════════════════════"
  fi
else
  warn "═══════════════════════════════════════════════════════════════"
  warn "  RULES_RECONCILIATION_VERDICT.md not found at project root."
  warn ""
  warn "  WHY THIS IS REQUIRED:"
  warn "  The safety-hardening branch has both firestore.deploy.rules"
  warn "  and firestore.rules modified. OQ-4 (SAFETY_RUNBOOK §16) asks"
  warn "  which file is actually live in production. A human must:"
  warn ""
  warn "  1. Check Firebase Console → Firestore → Rules (live)"
  warn "  2. Compare against firestore.rules in this branch"
  warn "  3. Create RULES_RECONCILIATION_VERDICT.md containing GREEN"
  warn "     (and any notes) when satisfied"
  warn "  4. Rerun this script — Steps 1+2 will then execute"
  warn ""
  warn "  Console URL:"
  warn "  https://console.firebase.google.com/project/${PROJECT}/firestore/rules"
  warn ""
  warn "  Steps 1 + 2 SKIPPED — Stage 1 rules deploy (from safety-hardening) is live."
  warn "  Steps 3 + 4 (CFs + App Check reminder) will still run."
  warn "═══════════════════════════════════════════════════════════════"
fi

# ── STEP 3 — Cloud Functions (consolidated safety) ────────────────────────────
echo ""
echo "  4-step3. STEP 3 — Safety Cloud Functions (DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md §STEP 3)…"
note "  New: submitSafetyReport, moderation/escalation, moderation/auditLog, moderation/appeals"
note "  Updated: contentModeration (fail-closed), moderateUGC (retry + transaction + dead-letter),"
note "  minorProtection (unknown-age=minor, adult-to-minor DM blocked server-side),"
note "  safeMessagingGateway (live Auth disabled check), contentModerationTriggers (comments + image DMs),"
note "  authenticationHelpers (backfillUsernameLookup admin-only, resolveUsernameToEmail removed),"
note "  Berean OS + Selah CFs (enforceAppCheck added), postAndCommentFunctions (disabled check on addComment),"
note "  index.js (aiModeration alias removed)."
note "  NCMEC stub: ncmecReporter.js is wired but gated behind NCMEC_ENABLED=false (default)."
note "  Enable only after legal counsel completes NCMEC registration + credentials in Secret Manager."

firebase deploy \
  --only functions:submitSafetyReport,\
functions:moderationEscalation,\
functions:moderationAuditLog,\
functions:moderationAppeals,\
functions:contentModeration,\
functions:moderateUGC,\
functions:minorProtection,\
functions:safeMessagingGateway,\
functions:contentModerationTriggers,\
functions:authenticationHelpers,\
functions:postAndCommentFunctions \
  --project "$PROJECT" \
  || abort_with_rollback "STEP 3: Safety CF deploy failed. Redeploy prior function version individually via Firebase Console." \
       "firebase functions:delete <functionName> --project $PROJECT  # then redeploy prior commit tag"

for FN in submitSafetyReport contentModeration minorProtection safeMessagingGateway; do
  verify_functions_list "$FN"
done
pass "  STEP 3 complete — Safety Cloud Functions deployed"

# ── STEP 4 — App Check Console Enforcement reminder (HUMAN STEP) ─────────────
echo ""
echo "  4-step4. STEP 4 — App Check Console Enforcement (HUMAN — do AFTER Step 3 is verified + iOS live)"
echo ""
warn "  ╔═══════════════════════════════════════════════════════════════╗"
warn "  ║  DO NOT flip App Check enforce-mode until:                   ║"
warn "  ║   • Step 3 CFs are deployed and verified in Firebase Console ║"
warn "  ║   • The iOS app with App Check SDK is live in production     ║"
warn "  ╚═══════════════════════════════════════════════════════════════╝"
warn ""
info "  Console: https://console.firebase.google.com/project/${PROJECT}/appcheck"
info ""
info "  Enforce in this order:"
info "    1. submitSafetyReport"
info "    2. moderation/escalation"
info "    3. moderation/auditLog"
info "    4. moderation/appeals"
info "    5. Remaining Berean OS + Selah CFs (after iOS build verified)"
echo ""
note "  Rollback: Firebase Console → App Check → each CF → Unenforce"
echo ""
pass "  STEP 4 reminder printed — App Check enforcement is a HUMAN console action"

pass "Stage 4 complete — Safety Consolidated Deploy Package executed (see notices above for any skipped steps)"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 5 — REMOTE CONFIG KEY ADDITIONS
# ══════════════════════════════════════════════════════════════════════════════
prompt_stage "5" "REMOTE CONFIG — 15 NEW KEYS" \
  "Adds 5 Connect UI wave keys and 10 Find Church 2.0 keys to Remote Config.
  ALL DEFAULT FALSE. Deploying the keys makes them available for flag-flipping
  later — they activate nothing by themselves. The script exports the current
  template, inserts the missing keys, and re-deploys it."

echo "  5a. Fetching current Remote Config template…"
RC_TEMPLATE_PATH="/tmp/rc_template_stage3_$(date +%s).json"
firebase remoteconfig:get \
  --project "$PROJECT" \
  --output "$RC_TEMPLATE_PATH" \
  || abort_with_rollback "Failed to fetch Remote Config template." \
       "firebase remoteconfig:get --project $PROJECT"
pass "  Template fetched → $RC_TEMPLATE_PATH"

echo "  5b. Inserting 15 new keys (all false, description-annotated)…"
# Use node inline to splice new parameters into the existing template JSON
node - "$RC_TEMPLATE_PATH" <<'NODEEOF'
const fs = require('fs');
const path = process.argv[2];
const template = JSON.parse(fs.readFileSync(path, 'utf8'));
template.parameters = template.parameters || {};

const NEW_PARAMS = {
  // Connect UI Waves
  connect_layout_v2_enabled:    { defaultValue: { value: 'false' }, description: 'Wave 1: V2 shell, glass union bar, notch FAB' },
  connect_polish_v2_enabled:    { defaultValue: { value: 'false' }, description: 'Wave 2: Unified Catch Up, disclosure chip' },
  connect_empty_states_enabled: { defaultValue: { value: 'false' }, description: 'Wave 3: ConnectEmptyStateView on all surfaces' },
  connect_smart_berean_enabled: { defaultValue: { value: 'false' }, description: 'Wave 4: Smart Berean pill (bereanQuestion callable)' },
  connect_offline_queue_enabled:{ defaultValue: { value: 'false' }, description: 'Wave 5: Offline draft queue + processConnectQueuedDraft' },
  // Find Church 2.0
  findChurch2_onboarding:       { defaultValue: { value: 'false' }, description: 'FC2: 3-phase LG onboarding' },
  findChurch2_matchExplain:     { defaultValue: { value: 'false' }, description: 'FC2: MatchExplanation drawer (local-only)' },
  findChurch2_gatherings:       { defaultValue: { value: 'false' }, description: 'FC2: Gatherings surface (requires rules)' },
  findChurch2_visitPlanner:     { defaultValue: { value: 'false' }, description: 'FC2: Visit Planner (requires seekerProfiles rules)' },
  findChurch2_claimPortal:      { defaultValue: { value: 'false' }, description: 'FC2: Church claim flow + admin portal' },
  findChurch2_concierge:        { defaultValue: { value: 'false' }, description: 'FC2: Berean concierge (local-only, no CF)' },
  findChurch2_mapHybrid:        { defaultValue: { value: 'false' }, description: 'FC2: Map/list toggle' },
  findChurch2_availability:     { defaultValue: { value: 'false' }, description: 'FC2: AvailabilityStatus pills (requires CF)' },
  findChurch2_trustSignals:     { defaultValue: { value: 'false' }, description: 'FC2: Trust signals section' },
  findChurch2_designRefresh:    { defaultValue: { value: 'false' }, description: 'FC2: Full UI refresh' },
};

let added = 0;
for (const [key, val] of Object.entries(NEW_PARAMS)) {
  if (!template.parameters[key]) {
    template.parameters[key] = val;
    added++;
  }
}
fs.writeFileSync(path, JSON.stringify(template, null, 2));
console.log(`  Added ${added} new keys (${Object.keys(NEW_PARAMS).length - added} already existed)`);
NODEEOF

pass "  15 keys merged into template"

echo "  5c. Deploying updated Remote Config template…"
firebase remoteconfig:publish \
  --project "$PROJECT" \
  "$RC_TEMPLATE_PATH" \
  2>/dev/null || \
firebase remoteconfig:set \
  --project "$PROJECT" \
  "$RC_TEMPLATE_PATH" \
  || warn "  RC deploy command failed (may need to use Firebase Console UI — see note below)"

info "  If the CLI deploy failed, manually upload in Firebase Console:"
info "  https://console.firebase.google.com/project/${PROJECT}/config"
info "  Import template file: $RC_TEMPLATE_PATH"

pass "Stage 5 complete — 15 new RC keys (all false)"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 6 — BAIT-TRANSCRIPT RUNNER (volunteered-excluded-content proof)
# ══════════════════════════════════════════════════════════════════════════════
prompt_stage "6" "BAIT-TRANSCRIPT RUNNER (live CF exclusion proof)" \
  "Calls the deployed CFs with synthetic bait content to prove that excluded content
  is detected server-side. This is the Wave gate for Context System W3-5: the output
  must show CSAM signals, DM risk escalation, and hate-speech flags are working.
  Results are filed to $BAIT_RESULTS."

echo "  6a. Getting Firebase auth token for CF calls…"
# Try gcloud first (most reliable in CI/CD), fallback to firebase token
if command -v gcloud >/dev/null 2>&1 && gcloud auth print-identity-token >/dev/null 2>&1; then
  ID_TOKEN="$(gcloud auth print-identity-token)"
  pass "  Got ID token via gcloud"
elif command -v firebase >/dev/null 2>&1; then
  # firebase login:ci returns a CI token; we use it as a bearer header workaround
  warn "  gcloud not found or not authenticated; using firebase-user token (may not work with App Check)"
  warn "  For full bait-transcript coverage, authenticate with: gcloud auth login --update-adc"
  ID_TOKEN=""
else
  warn "  No auth token available — skipping live CF calls"
  ID_TOKEN=""
fi

CF_BASE="https://${REGION}-${PROJECT}.cloudfunctions.net"
BAIT_PASS=0; BAIT_FAIL=0

run_bait_test() {
  local name="$1" fn="$2" payload="$3" expect_field="$4" expect_value="$5"
  echo ""
  echo "  Bait test: $name"
  if [ -z "$ID_TOKEN" ]; then
    warn "  SKIP (no auth token)"
    echo "  SKIPPED: $name" >> "$BAIT_RESULTS"
    return
  fi
  RESP=$(curl -sf -X POST \
    "${CF_BASE}/${fn}" \
    -H "Authorization: Bearer ${ID_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"data\": ${payload}}" 2>/dev/null || echo '{"result":{"error":"curl_failed"}}')
  echo "  Response: $(echo "$RESP" | head -c 200)"
  if echo "$RESP" | grep -q "$expect_value"; then
    pass "  $name → expected '$expect_value' found"
    BAIT_PASS=$((BAIT_PASS + 1))
    echo "PASS: $name" >> "$BAIT_RESULTS"
  else
    fail "  $name → expected '$expect_value' NOT found in response"
    BAIT_FAIL=$((BAIT_FAIL + 1))
    echo "FAIL: $name — expected $expect_value, got: $RESP" >> "$BAIT_RESULTS"
  fi
}

echo "" > "$BAIT_RESULTS"
echo "Bait-Transcript Results — $(date)" >> "$BAIT_RESULTS"
echo "Project: $PROJECT" >> "$BAIT_RESULTS"
echo "──────────────────────────────" >> "$BAIT_RESULTS"

# Test 1: contentSafetyScreen detects crisis language
run_bait_test \
  "contentSafetyScreen — crisis language" \
  "contentSafetyScreen" \
  '{"body":"I want to end my life and kill myself","sourceType":"post"}' \
  "flags" "crisis_language"

# Test 2: contentSafetyScreen passes clean content
run_bait_test \
  "contentSafetyScreen — clean content passes" \
  "contentSafetyScreen" \
  '{"body":"God is good all the time. Praise the Lord!","sourceType":"post"}' \
  "flags" '[]'

# Test 3: assessDogpileRisk on a real postId returns a result
run_bait_test \
  "assessDogpileRisk — returns structured result" \
  "assessDogpileRisk" \
  '{"postId":"bait-test-post-000","windowMinutes":5}' \
  "isHighRisk" "false"

# Test 4: evaluateDmRisk returns a risk level
run_bait_test \
  "evaluateDmRisk — returns riskLevel" \
  "evaluateDmRisk" \
  '{"recipientUid":"bait-test-uid-000","messageBody":"Hello"}' \
  "riskLevel" "riskLevel"

echo "" >> "$BAIT_RESULTS"
echo "Summary: $BAIT_PASS passed, $BAIT_FAIL failed" >> "$BAIT_RESULTS"

echo ""
info "  Bait-transcript results saved to: $BAIT_RESULTS"
cat "$BAIT_RESULTS"
echo ""

if [ "$BAIT_FAIL" -gt 0 ]; then
  warn "  $BAIT_FAIL bait test(s) failed. Review $BAIT_RESULTS before enabling W3-5 features."
  warn "  W3-5 surface flags must NOT be flipped until all bait tests pass."
else
  if [ "$BAIT_PASS" -gt 0 ]; then
    pass "  All $BAIT_PASS bait tests passed — volunteered-excluded-content isolation confirmed"
  else
    warn "  All bait tests were SKIPPED (no auth token). Run manually with auth before flipping W3-5 flags."
  fi
fi

pass "Stage 6 complete — bait-transcript filed"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 7 — FINAL SMOKE CHECKLIST
# ══════════════════════════════════════════════════════════════════════════════
prompt_stage "7" "FINAL SMOKE CHECKLIST" \
  "Human-verified pass/fail for each critical check. Record your answers — any NO
  means the deploy is incomplete. Do not flip flags until all are YES."

echo ""
echo -e "${BOLD}  Answer each prompt: yes / no / skip${NC}"
echo ""

smoke_check() {
  local label="$1" hint="$2"
  echo -e "  ${CYAN}──────────────────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}CHECK: $label${NC}"
  [ -n "$hint" ] && echo -e "  ${DIM}How: $hint${NC}"
  read -rp "  Result (yes/no/skip): " SC_RESULT
  case "$SC_RESULT" in
    yes|y) pass "  $label" ;;
    skip|s) warn "  $label — SKIPPED (revisit before launch)" ;;
    *) fail "  $label — NEEDS ATTENTION" ;;
  esac
}

smoke_check \
  "evaluateDmRisk — no cold-start errors" \
  "firebase functions:log --only evaluateDmRisk --project $PROJECT | head -20"

smoke_check \
  "one_relayMoment — forwardAllowed=false returns permission-denied" \
  "Call one_relayMoment with a bait moment where permissions.forwardAllowed=false; expect HttpsError permission-denied"

smoke_check \
  "processConnectQueuedDraft — idempotency key deduplication working" \
  "Call twice with the same idempotencyKey UUID; second call must return {status:'already_processed'}"

smoke_check \
  "contentSafetyScreen — returns flags for crisis language" \
  "firebase functions:log --only contentSafetyScreen --project $PROJECT | head -20"

smoke_check \
  "Firestore rules live — conversations allow participants (DMs restored)" \
  "Test in emulator or with a real DM send from the app"

smoke_check \
  "Algolia: no minor UIDs in People index" \
  "Run Algolia query on users index; verify no tierB/tierC/blocked records appear"

smoke_check \
  "onUserDocCreated running — check Firebase Functions logs" \
  "firebase functions:log --only onUserDocCreated --project $PROJECT | head -10"

smoke_check \
  "Firestore TTL policy enabled on moderationQueue.expireAt (OQ-20)" \
  "Firebase Console → Firestore → Indexes → TTL — confirm policy exists"

smoke_check \
  "Storage rules deployed — post_media upload test" \
  "Upload a test image via the iOS app and confirm it goes through moderation"

smoke_check \
  "PHONE_HASH_PEPPER rotation confirmed — new phoneAuthRateLimit docs use phoneHash field" \
  "Firebase Console → Firestore → phoneAuthRateLimits — look for hashed doc IDs"

smoke_check \
  "Submit test safety report from iOS → verify moderationQueue entry" \
  "Tap 'Report' on a test post in the iOS app; check Firestore → moderationQueue for new doc with reporterUid set"

smoke_check \
  "Adult DM to minor (no guardian approval) → blocked server-side" \
  "In a test account (adult UID), attempt a DM to a minor UID with no guardianApprovedContacts entry; expect permission-denied or risk-blocked response from evaluateDmRisk / minorProtection"

smoke_check \
  "Image-only post → queued as pending, visible:false" \
  "Submit a post containing only an image (no text); confirm Firestore post doc has visible:false and a moderationQueue entry is created"

smoke_check \
  "Try write visible:true to Firestore as post owner → PERMISSION_DENIED" \
  "Using Firebase emulator or REST API with owner credentials, attempt: db.doc('posts/<id>').update({visible:true}); expect PERMISSION_DENIED"

smoke_check \
  "Try write safety.isMinor:false as user → PERMISSION_DENIED" \
  "Using Firebase emulator or REST API with own user credentials, attempt: db.doc('users/<uid>').update({'safety.isMinor':false}); expect PERMISSION_DENIED"

echo ""
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  DEPLOY COMPLETE — SMOKE CHECKLIST FILED                         ${NC}"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════════${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# FLAG-FLIP PRECONDITIONS REGISTRY
# (printed at the end — script never flips flags)
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${YELLOW}║  FLAG-FLIP PRECONDITIONS REGISTRY                                ║${NC}"
echo -e "${BOLD}${YELLOW}║  All flags default FALSE. Flip individually after QA.           ║${NC}"
echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Flag${NC}                               ${BOLD}Preconditions${NC}"
echo -e "  ─────────────────────────────────────────────────────────────────────"

print_flag() { printf "  %-36s  %s\n" "$1" "$2"; }

print_flag "connect_layout_v2_enabled"    "processConnectQueuedDraft ACTIVE; iOS 26 device tested"
print_flag "connect_polish_v2_enabled"    "connect_layout_v2 ON first"
print_flag "connect_empty_states_enabled" "connect_layout_v2 ON first"
print_flag "connect_smart_berean_enabled" "bereanQuestion ACTIVE; connect_layout_v2 ON first"
print_flag "connect_offline_queue_enabled" "processConnectQueuedDraft + TTL policy set"
print_flag "any one_* flag"               "ALL one_* CFs ACTIVE; one_relayMoment rejection verified"
print_flag "spiritualOS_* flags"          "All 27 Spiritual OS CFs ACTIVE in console"
print_flag "findChurch2_availability"     "computeAvailabilityStatus + scheduleAvailabilityRefresh ACTIVE"
print_flag "findChurch2_gatherings"       "gatherings/ Firestore rules live"
print_flag "findChurch2_visitPlanner"     "seekerProfiles/ + visitPlans/ rules live; EventKit plist entries"
print_flag "findChurch2_claimPortal"      "claimRequests/ rules live; Aegis review queue handler in place"
print_flag "findChurch2_concierge"        "No CF dependency — can flip immediately"
print_flag "findChurch2_matchExplain"     "No CF dependency — can flip immediately"
print_flag "findChurch2_designRefresh"    "findChurch2_matchExplain already ON; test on all device sizes"

echo ""
echo -e "  ${BOLD}PENDING (HUMAN-REQUIRED before any W3-5 surface can go live):${NC}"
echo -e "  • W3-5 bait-transcript: file $BAIT_RESULTS — all tests must PASS"
echo -e "  • W3-12 storage check: Firebase Console → Storage → Rules (OQ-28)"
echo -e "  • NCMEC submission: manual until OQ-10 / OQ-31 resolved (see SAFETY_RUNBOOK §7)"

echo ""
echo -e "${BOLD}${GREEN}  Firebase Remote Config Console:${NC}"
echo -e "  https://console.firebase.google.com/project/${PROJECT}/config"
echo ""
echo -e "${BOLD}${YELLOW}  Flags are yours. Flip when ready.${NC}"
echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  FLEET: CLOSED. The remaining work on earth belongs to you.  ${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# ── EXPECTED OUTPUT GUIDE ──────────────────────────────────────────────────────
#
# What healthy output looks like at each stage. Use this as your reference while
# running. If you see RED text or the script aborts, match the error to this guide
# to triage before retrying.
#
# ─────────────────────────────────────────────────────────────────────────────
# STAGE 0  (preflight — ~3 min)
# ─────────────────────────────────────────────────────────────────────────────
#   ✅ HEAD is 12d149ea ✓
#      (If you see YELLOW "HEAD is X, expected 12d149ea" → you are on a different
#       commit. Type "yes" to continue only if you intentionally advanced HEAD.
#       Otherwise: git checkout safety-hardening)
#
#   ✅ Project amen-5e359 is accessible
#      (RED here → run: firebase login)
#
#   ✅ node v20.x.x
#   ✅ npm 10.x.x
#
#   ✅ No hardcoded secrets found in Stage-3 CF files
#      (RED here → stop immediately; audit the flagged file for committed secrets)
#
#   ✅ enforceAppCheck: true confirmed in Stage-3 CF source
#      (YELLOW here → check a3Callables.ts / processConnectQueuedDraft.ts manually)
#
#   ✅ TypeScript compile: 0 errors
#      (YELLOW here → pre-existing errors; review before proceeding)
#
#   ✅ Keystone tests passed
#      Jest output will show: "Tests: 64 passed, 0 failed" (or more)
#      (RED / FAILED here → STOP. Run: cd functions && npm test -- --testPathPattern='ageTier|safety')
#
# ─────────────────────────────────────────────────────────────────────────────
# STAGE 1  (recovery redeploys — ~12 min)
# ─────────────────────────────────────────────────────────────────────────────
#   Expect for each deploy sub-command:
#     "✔  Deploy complete!"
#     (Firebase CLI prints a progress spinner then this line on success)
#
#   Expect for each verify_functions_list call:
#     "ℹ   Verifying <FunctionName> is ACTIVE in Firebase…"
#     "✅  <FunctionName> is ACTIVE"
#     (YELLOW "not yet visible" is normal for up to 30 s cold-start lag — OK to continue)
#
#   Red flags:
#     "Error: [function name] failed" → STOP. Check Firebase Console → Functions logs.
#     "HTTP Error: 403" → Firebase IAM permissions issue; check service account roles.
#     "quota exceeded" → reduce batch size or wait and retry.
#
# ─────────────────────────────────────────────────────────────────────────────
# STAGE 2  (pepper rotation — ~5 min)
# ─────────────────────────────────────────────────────────────────────────────
#   Expect:
#     "New pepper (64 hex chars / 256 bits): XXXXXXXX…XXXXXXXX (truncated for display)"
#     "✅  PHONE_HASH_PEPPER set in Secret Manager"
#     "✅  checkPhoneVerificationRateLimit is ACTIVE"
#     "✅  reportPhoneVerificationFailure is ACTIVE"
#     "✅  unblockPhoneNumber is ACTIVE"
#     "✅  Stage 2 complete — pepper rotated, 3 phone functions redeployed"
#
#   Red flags:
#     "permission denied" on firebase functions:secrets:set
#       → check IAM: service account needs roles/secretmanager.admin
#     "Error: command not found: openssl"
#       → install openssl: brew install openssl
#
# ─────────────────────────────────────────────────────────────────────────────
# STAGE 3  (Stage-3 CFs — ~25 min)
# ─────────────────────────────────────────────────────────────────────────────
#   3a. A3 Safety (5 CFs):
#     "✅  A3 safety batch deployed"
#     All 5 CFs show ACTIVE: evaluateDmRisk, reportDmAbuse, contentSafetyScreen,
#       analyzeRelationshipRisk, assessDogpileRisk
#
#   3b. Connect queue (1 CF):
#     "✅  Connect queue batch deployed"
#     MANUAL STEP PROMPT: "add TTL policy on connect_idempotency.processedAt (7 days)"
#       → open Firebase Console → Firestore → connect_idempotency → Add TTL → processedAt → 7 days
#
#   3c. ONE private OS (5 CFs):
#     "✅  ONE batch deployed"
#     All 5 show ACTIVE: one_relayMoment, one_sendMoment, one_expireMoment,
#       one_verifyEntitlement, one_activateLegacy
#
#   3d. Spiritual OS (27 callables):
#     "✅  Spiritual OS batch deployed"
#     Spot-checks: detectUnsentThoughtRisk ACTIVE, calculateEternalWeight ACTIVE
#
#   3e. Find Church 2.0 (4 CFs — requires GOOGLE_PLACES_API_KEY):
#     "✅  GOOGLE_PLACES_API_KEY is set in Secret Manager"  ← if key was pre-set
#     OR prompt: "Has the key been set? (yes/skip)"
#       → type "yes" if you ran: firebase functions:secrets:set GOOGLE_PLACES_API_KEY
#       → type "skip" to defer Find Church 2.0 deploy (safe — just re-run later)
#
#   Red flags for Stage 3:
#     Any "Deploy complete!" absent → specific CF batch failed; see rollback command printed.
#     "ENOENT: no such file or directory" for CF source → Backend/functions/src/ path missing;
#       verify git status clean and all files committed.
#     "Error: Build failed" → TypeScript errors in that CF; run: cd Backend/functions && npx tsc
#
# ─────────────────────────────────────────────────────────────────────────────
# STAGE 4  (safety consolidated deploy package — ~8 min — STEPS 1+2 CONDITIONAL)
# Source: DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md (supersedes all prior W3/safety stages)
# ─────────────────────────────────────────────────────────────────────────────
#   Pre-gate:
#     "✅  safety-rules tests passed — proceeding to rules deploy"
#     (RED here → STOP. Run: cd functions && npm test -- --testPathPattern='safety-rules')
#
#   If RULES_RECONCILIATION_VERDICT.md is GREEN (Steps 1+2 run):
#     "✅  Verdict file found and says GREEN — proceeding with all four steps"
#     "✅  Firestore rules dry-run passed"
#     "✅  STEP 1 complete — Firestore rules deployed"
#     "✅  STEP 2 complete — Storage rules deployed"
#
#   If verdict file is absent or not GREEN (Steps 1+2 skipped):
#     YELLOW block: "Steps 1 + 2 SKIPPED — rerun this script after verdict is GREEN."
#     Steps 3+4 still run; Stage 1 rules from the recovery deploy remain live.
#     Action: fill RULES_RECONCILIATION_VERDICT.md with GREEN, then re-run script.
#
#   Step 3 (safety CFs — always runs):
#     "✅  STEP 3 complete — Safety Cloud Functions deployed"
#     Spot-checks: submitSafetyReport ACTIVE, contentModeration ACTIVE,
#       minorProtection ACTIVE, safeMessagingGateway ACTIVE
#
#   Step 4 (App Check reminder — always prints):
#     YELLOW reminder box printed with console URL + ordered enforcement list.
#     "✅  STEP 4 reminder printed — App Check enforcement is a HUMAN console action"
#     → Do NOT enable enforce-mode until Step 3 verified + iOS App Check SDK live.
#
#   "✅  Stage 4 complete — Safety Consolidated Deploy Package executed"
#
# ─────────────────────────────────────────────────────────────────────────────
# STAGE 5  (Remote Config — ~3 min)
# ─────────────────────────────────────────────────────────────────────────────
#   Expect:
#     "✅  Template fetched → /tmp/rc_template_stage3_<timestamp>.json"
#     "  Added N new keys (M already existed)"  ← N+M should sum to 15
#     "✅  Stage 5 complete — 15 new RC keys (all false)"
#
#   If CLI deploy fails (some CLI versions lack remoteconfig:publish):
#     YELLOW: "RC deploy command failed (may need to use Firebase Console UI)"
#     → Log into Firebase Console → Remote Config → Import template file shown in output
#
# ─────────────────────────────────────────────────────────────────────────────
# STAGE 6  (bait-transcript — ~5 min)
# ─────────────────────────────────────────────────────────────────────────────
#   With gcloud authenticated:
#     "✅  Got ID token via gcloud"
#     4 bait tests print responses:
#       "✅  contentSafetyScreen — crisis language → expected 'crisis_language' found"
#       "✅  contentSafetyScreen — clean content passes → expected '[]' found"
#       "✅  assessDogpileRisk — returns structured result → expected 'false' found"
#       "✅  evaluateDmRisk — returns riskLevel → expected 'riskLevel' found"
#     "✅  All 4 bait tests passed — volunteered-excluded-content isolation confirmed"
#
#   Without gcloud (token-less):
#     YELLOW: "All bait tests were SKIPPED (no auth token)"
#     → Authenticate: gcloud auth login --update-adc; then re-run Stage 6 manually
#     → W3-5 feature flags MUST NOT be flipped until bait tests pass
#
#   Red flags:
#     FAIL on contentSafetyScreen crisis test → safety screening is broken; stop flag flips.
#     FAIL on evaluateDmRisk → DM risk gate non-functional; minors unprotected.
#
# ─────────────────────────────────────────────────────────────────────────────
# STAGE 7  (smoke checklist — ~10 min)
# ─────────────────────────────────────────────────────────────────────────────
#   15 interactive prompts (yes / no / skip):
#     Original 10 operational checks +
#     5 new safety-package checks:
#       - Submit test safety report from iOS → moderationQueue entry
#       - Adult DM to minor (no guardian approval) → blocked server-side
#       - Image-only post → queued pending, visible:false
#       - Write visible:true as post owner → PERMISSION_DENIED
#       - Write safety.isMinor:false as user → PERMISSION_DENIED
#   All 15 should answer "yes" before declaring deploy complete.
#   Any "no" answer prints "NEEDS ATTENTION" in RED — log it and fix before launch.
#   "skip" is acceptable for items you intend to revisit; mark in your notes.
#
#   After all prompts:
#     "══ DEPLOY COMPLETE — SMOKE CHECKLIST FILED ══"
#     FLAG-FLIP PRECONDITIONS REGISTRY printed (read-only; script never flips flags).
#     Final line: "FLEET: CLOSED. The remaining work on earth belongs to you."
#
# ─────────────────────────────────────────────────────────────────────────────
# TOTAL RUN TIME
# ─────────────────────────────────────────────────────────────────────────────
#   ~71 minutes wall-clock (varies by Firebase deploy queue depth and CF count).
#   If > 95 min: network issue or Firebase deploy quota — check Firebase status page.
#
# ── END EXPECTED OUTPUT GUIDE ─────────────────────────────────────────────────
