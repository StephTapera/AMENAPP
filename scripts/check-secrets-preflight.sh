#!/bin/bash
# check-secrets-preflight.sh
# Pre-commit secrets detection for the AMEN repository.
# Run from repo root before every commit or add to .git/hooks/pre-commit.
#
# Usage:
#   bash scripts/check-secrets-preflight.sh
#   # Or as a git pre-commit hook: copy/symlink to .git/hooks/pre-commit
#
# Exit codes:
#   0 — clean, no secrets detected
#   1 — one or more secret patterns found; commit blocked

set -euo pipefail

FAIL=0
WARNINGS=0

echo "=== AMEN Preflight Secrets Check ==="

STAGED_DIFF=$(git diff --cached 2>/dev/null || true)
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || true)

# ------------------------------------------------------------
# Pattern checks against staged diff content
# ------------------------------------------------------------

# Firebase / Google API keys (AIzaSy…)
if echo "$STAGED_DIFF" | grep -qE 'AIza[0-9A-Za-z_-]{35}'; then
    echo ""
    echo "FAIL [S-001]: Firebase/Google API key pattern (AIzaSy...) detected in staged diff."
    echo "  -> Remove the literal key value."
    echo "  -> Firebase API keys belong in GoogleService-Info.plist injected via CI — do NOT commit the real file."
    echo "  -> Add GoogleService-Info.plist to .gitignore and inject via CI secrets."
    FAIL=1
fi

# OpenAI API keys (sk-…)
if echo "$STAGED_DIFF" | grep -qE "sk-[a-zA-Z0-9]{48}"; then
    echo ""
    echo "FAIL [S-002]: OpenAI API key pattern (sk-...) detected in staged diff."
    echo "  -> Store the key in Firebase Secret Manager: firebase functions:secrets:set OPENAI_API_KEY"
    echo "  -> Reference via defineSecret('OPENAI_API_KEY') in Cloud Functions."
    FAIL=1
fi

# Anthropic / Claude API keys (sk-ant-…)
if echo "$STAGED_DIFF" | grep -qE 'sk-ant-[a-zA-Z0-9_-]{40,}'; then
    echo ""
    echo "FAIL [S-003]: Anthropic API key pattern (sk-ant-...) detected in staged diff."
    echo "  -> Store the key in Firebase Secret Manager: firebase functions:secrets:set CLAUDE_API_KEY"
    echo "  -> Reference via defineSecret('CLAUDE_API_KEY') in Cloud Functions."
    FAIL=1
fi

# Stripe live secret keys (sk_live_…)
if echo "$STAGED_DIFF" | grep -qE 'sk_live_[0-9a-zA-Z]{24,}'; then
    echo ""
    echo "FAIL [S-004]: Stripe live secret key (sk_live_...) detected in staged diff."
    echo "  -> Store in Firebase Secret Manager: firebase functions:secrets:set STRIPE_SECRET_KEY"
    echo "  -> NEVER embed Stripe live keys in source code or xcconfig."
    FAIL=1
fi

# Stripe test secret keys in non-test files (sk_test_…)
if echo "$STAGED_DIFF" | grep -qE 'sk_test_[0-9a-zA-Z]{24,}'; then
    echo ""
    echo "WARNING [S-005]: Stripe test secret key (sk_test_...) detected in staged diff."
    echo "  -> Test keys can be committed only inside files that are 100% test-only and never shipped."
    echo "  -> If this is in any production source, move to Firebase Secret Manager."
    WARNINGS=$((WARNINGS + 1))
fi

# Algolia API key literals (not xcconfig substitution)
if echo "$STAGED_DIFF" | grep -qE "(algolia|ALGOLIA).*['\"][0-9a-fA-F]{32}['\"]"; then
    echo ""
    echo "FAIL [S-006]: Algolia API key literal detected in staged diff."
    echo "  -> Algolia search keys must use xcconfig substitution: \$(ALGOLIA_SEARCH_KEY)"
    echo "  -> Algolia admin keys must NEVER appear in client source; move to Firebase Secret Manager."
    FAIL=1
fi

# Google Vision / Vertex AI keys
if echo "$STAGED_DIFF" | grep -qE '(GOOGLE_VISION_API_KEY|VERTEX_AI_KEY)\s*=\s*AIza'; then
    echo ""
    echo "FAIL [S-007]: Google Vision or Vertex AI key literal detected in staged diff."
    echo "  -> These keys must only appear as xcconfig variables: \$(GOOGLE_VISION_API_KEY)"
    echo "  -> Prefer moving AI calls behind Cloud Function callables so the key is never in the binary."
    FAIL=1
fi

# FCM server keys (AAAA…)
if echo "$STAGED_DIFF" | grep -qE 'AAAA[A-Za-z0-9_-]{140}'; then
    echo ""
    echo "FAIL [S-008]: FCM server/legacy key pattern detected in staged diff."
    echo "  -> FCM server keys must be stored in Firebase Secret Manager, not in source."
    FAIL=1
fi

# Private key PEM blocks
if echo "$STAGED_DIFF" | grep -q 'BEGIN PRIVATE KEY\|BEGIN RSA PRIVATE KEY\|BEGIN EC PRIVATE KEY'; then
    echo ""
    echo "FAIL [S-009]: PEM private key block detected in staged diff."
    echo "  -> Private keys must NEVER be committed. Use Secret Manager or Apple Developer portal."
    FAIL=1
fi

# Generic high-entropy password assignments (heuristic — may have false positives)
if echo "$STAGED_DIFF" | grep -qE '(password|passwd|secret|token)\s*=\s*["\x27][A-Za-z0-9!@#\$%\^&\*\(\)_\+\-=]{16,}["\x27]'; then
    echo ""
    echo "WARNING [S-010]: Possible hardcoded credential assignment detected in staged diff."
    echo "  -> Review staged diff manually: git diff --cached"
    echo "  -> If this is a real credential, move it to Firebase Secret Manager or xcconfig."
    WARNINGS=$((WARNINGS + 1))
fi

# ------------------------------------------------------------
# File-level checks
# ------------------------------------------------------------

# GoogleService-Info.plist being staged
if echo "$STAGED_FILES" | grep -q 'GoogleService-Info\.plist'; then
    echo ""
    echo "WARNING [S-011]: GoogleService-Info.plist is staged."
    echo "  -> This file contains the Firebase API key (AIzaSy...)."
    echo "  -> The key is bundle-restricted, but the file should NOT be committed to a shared repo."
    echo "  -> Add it to .gitignore and inject via CI. See SECURITY_AND_SECRETS.md S-001."
    WARNINGS=$((WARNINGS + 1))
fi

# xcconfig files being staged (may contain literal key values)
if echo "$STAGED_FILES" | grep -q '\.xcconfig$'; then
    echo ""
    echo "WARNING [S-012]: .xcconfig file is staged."
    echo "  -> Verify it contains only \$(VAR_NAME) references, not literal API key values."
    echo "  -> Config.xcconfig should be in .gitignore per repo conventions."
    WARNINGS=$((WARNINGS + 1))
fi

# .env files
if echo "$STAGED_FILES" | grep -qE '(^|/)\.env($|\.)'; then
    echo ""
    echo "FAIL [S-013]: .env file is staged."
    echo "  -> .env files must NEVER be committed. Add to .gitignore."
    FAIL=1
fi

# service-account JSON
if echo "$STAGED_FILES" | grep -qiE 'service.?account.*\.json$|firebase.?adminsdk.*\.json$'; then
    echo ""
    echo "FAIL [S-014]: Possible Firebase service account JSON is staged."
    echo "  -> Service account keys must NEVER be committed. Use Workload Identity or CI secrets."
    FAIL=1
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

echo ""
if [ "$FAIL" -eq 1 ]; then
    echo "BLOCKED: One or more secret patterns were detected. Fix the items above, then re-stage and commit."
    echo "         See SECURITY_AND_SECRETS.md for rotation guidance."
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    echo "PASS with $WARNINGS warning(s). Review the warnings above before pushing."
    exit 0
else
    echo "PASS: No secret patterns detected in staged files."
    exit 0
fi
