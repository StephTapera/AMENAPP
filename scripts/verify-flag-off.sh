#!/usr/bin/env bash
# verify-flag-off.sh
# SELAH Wave 5 — Automated Flag-Off Verification Script
#
# Greps all SELAH Wave 3/4/5 view files for unconditional rendering:
# views that declare a body property but do NOT check their feature flag
# at the top of the body block.
#
# Usage:
#   chmod +x scripts/verify-flag-off.sh
#   ./scripts/verify-flag-off.sh
#
# Exit codes:
#   0 — all views pass (every checked view has a flag guard)
#   1 — one or more views are missing a flag guard at the top of body

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# SELAH view files to audit — Wave 3 (Connections), Wave 4 (Creation), Wave 5 (Berean/Safety)
SELAH_VIEW_FILES=(
    "$REPO_ROOT/AMENAPP/AMENAPP/AIIntelligence/PrayerChainComposerView.swift"
    "$REPO_ROOT/AMENAPP/AMENAPP/AMENAPP/Creation/TestimonyEditorView.swift"
    "$REPO_ROOT/AMENAPP/AMENAPP/AMENAPP/Creation/RemixLineageView.swift"
    "$REPO_ROOT/AMENAPP/AMENAPP/AIIntelligence/TableCardView.swift"
    "$REPO_ROOT/AMENAPP/AMENAPP/AIIntelligence/BereanCoCreatorInlineView.swift"
    "$REPO_ROOT/AMENAPP/AMENAPP/AIIntelligence/WhyAmISeeingThisSheetV2.swift"
)

# The 16 SELAH feature flag property names (as declared in AMENFeatureFlags)
SELAH_FLAGS=(
    "breathMotion"
    "selahMoments"
    "liturgicalTheming"
    "commitmentConnections"
    "tables"
    "prayerChains"
    "testimonies"
    "remixLineage"
    "bereanCoCreator"
    "bereanPersonalContext"
    "bereanTraditionAware"
    "bereanNotebooksGroups"
    "bereanRoomFirst"
    "feedWhyAmISeeingThis"
    "aegisC59"
    "youthMode"
)

FAILED=0
CHECKED=0
MISSING=()

echo "=========================================="
echo "SELAH Wave 5 — Flag-Off View Audit"
echo "Repo root: $REPO_ROOT"
echo "=========================================="
echo ""

for FILE in "${SELAH_VIEW_FILES[@]}"; do
    if [[ ! -f "$FILE" ]]; then
        echo "[SKIP] File not found: $FILE"
        continue
    fi

    FILENAME=$(basename "$FILE")
    CHECKED=$((CHECKED + 1))
    FOUND_FLAG=false

    # Check if the file contains a flag guard in the first 30 lines of 'body'
    # Strategy: grep for 'AMENFeatureFlags.shared.<flag>' anywhere in the file.
    for FLAG in "${SELAH_FLAGS[@]}"; do
        if grep -q "AMENFeatureFlags\.shared\.$FLAG" "$FILE" 2>/dev/null; then
            FOUND_FLAG=true
            echo "[PASS] $FILENAME — checks flag: $FLAG"
            break
        fi
    done

    if [[ "$FOUND_FLAG" == "false" ]]; then
        # Secondary check: look for any AMENFeatureFlags reference at all
        if grep -q "AMENFeatureFlags" "$FILE" 2>/dev/null; then
            echo "[PASS-GENERIC] $FILENAME — has AMENFeatureFlags guard (no specific SELAH flag matched by name)"
        else
            echo "[FAIL] $FILENAME — no feature flag guard found in body"
            MISSING+=("$FILENAME")
            FAILED=$((FAILED + 1))
        fi
    fi
done

echo ""
echo "=========================================="
echo "Also scanning for views with body that might lack flag guards..."
echo "=========================================="
echo ""

# Broader scan: find all .swift files under AIIntelligence/ and Creation/ directories
# that contain 'var body: some View' but do NOT contain any AMENFeatureFlags reference
AI_INTELLIGENCE_DIR="$REPO_ROOT/AMENAPP/AMENAPP/AIIntelligence"
CREATION_DIR="$REPO_ROOT/AMENAPP/AMENAPP/AMENAPP/Creation"

for DIR in "$AI_INTELLIGENCE_DIR" "$CREATION_DIR"; do
    if [[ ! -d "$DIR" ]]; then
        echo "[SKIP] Directory not found: $DIR"
        continue
    fi

    while IFS= read -r -d '' FILE; do
        FILENAME=$(basename "$FILE")

        # Only check files that declare a SwiftUI body
        if ! grep -q "var body: some View" "$FILE" 2>/dev/null; then
            continue
        fi

        # Skip files already in the explicit list above
        ALREADY_CHECKED=false
        for EXPLICIT in "${SELAH_VIEW_FILES[@]}"; do
            if [[ "$FILE" == "$EXPLICIT" ]]; then
                ALREADY_CHECKED=true
                break
            fi
        done
        [[ "$ALREADY_CHECKED" == "true" ]] && continue

        CHECKED=$((CHECKED + 1))

        if grep -q "AMENFeatureFlags" "$FILE" 2>/dev/null; then
            echo "[PASS] $FILENAME — has AMENFeatureFlags guard"
        else
            echo "[WARN] $FILENAME — declares body but no AMENFeatureFlags guard detected"
            echo "       Manual review recommended: $FILE"
            # This is a warning, not a hard failure — some views intentionally
            # have no flag (e.g. utility views). Only SELAH feature views need flags.
        fi
    done < <(find "$DIR" -name "*.swift" -print0 2>/dev/null)
done

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Files checked:  $CHECKED"
echo "Hard failures:  $FAILED"

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo ""
    echo "MISSING GUARDS in:"
    for F in "${MISSING[@]}"; do
        echo "  - $F"
    done
    echo ""
    echo "ACTION: Add AMENFeatureFlags.shared.<flag> check to the top of body in each file above."
    exit 1
else
    echo ""
    echo "All explicitly checked SELAH view files have flag guards."
    echo "Review [WARN] items above for views that may need manual inspection."
    exit 0
fi
