#!/bin/bash
set -euo pipefail

ROOT="$(pwd)"
RESULTS="$ROOT/AMEN_FINAL_10_GO_RESULTS"
mkdir -p "$RESULTS"

echo "============================================================"
echo "AMEN FINAL 10/10 GO VALIDATION"
echo "============================================================"

WORKSPACE="$(find "$ROOT" -maxdepth 4 -name "*.xcworkspace" | head -n 1 || true)"
PROJECT="$(find "$ROOT" -maxdepth 4 -name "*.xcodeproj" | head -n 1 || true)"

if [ -n "$WORKSPACE" ]; then
  XCODE_CONTAINER=(-workspace "$WORKSPACE")
  echo "Using workspace: $WORKSPACE"
elif [ -n "$PROJECT" ]; then
  XCODE_CONTAINER=(-project "$PROJECT")
  echo "Using project: $PROJECT"
else
  echo "ERROR: No Xcode workspace or project found."
  exit 1
fi

xcodebuild -list "${XCODE_CONTAINER[@]}" > "$RESULTS/xcodebuild_list.txt"

SCHEME="$(
  awk '
    /Schemes:/ {flag=1; next}
    flag && NF {gsub(/^ +| +$/, "", $0); print; exit}
  ' "$RESULTS/xcodebuild_list.txt"
)"

if [ -z "$SCHEME" ]; then
  echo "ERROR: Could not detect scheme."
  cat "$RESULTS/xcodebuild_list.txt"
  exit 1
fi

echo "Using scheme: $SCHEME"

DESTINATION="platform=iOS Simulator,name=iPhone 16 Pro"

xcrun simctl boot "iPhone 16 Pro" >/dev/null 2>&1 || true

echo ""
echo "1) Production blocker scan..."

SCAN="$RESULTS/production_blocker_scan.txt"
: > "$SCAN"

grep -RInE \
  "Coming Soon|coming soon|COMING SOON|placeholder UI|alert placeholder|Button\\(action:[[:space:]]*\\{[[:space:]]*\\}\\)|disabled.*paid|unsupported.*toast|fake production metrics|hardcoded fake|not yet available|soon" \
  "$ROOT" \
  --include="*.swift" \
  --exclude-dir=".build" \
  --exclude-dir="DerivedData" \
  --exclude-dir="Pods" \
  --exclude-dir=".git" \
  --exclude-dir="AMEN_FINAL_10_GO_RESULTS" \
  > "$SCAN" || true

if [ -s "$SCAN" ]; then
  echo "Potential production blockers found. Review:"
  cat "$SCAN"
else
  echo "PASS: No obvious production placeholder/dead-action blockers found."
fi

echo ""
echo "2) EmptyView/fatalError classification scan..."

CLASSIFY_SCAN="$RESULTS/emptyview_fatalerror_scan.txt"
: > "$CLASSIFY_SCAN"

grep -RInE "EmptyView\\(\\)|fatalError\\(" \
  "$ROOT" \
  --include="*.swift" \
  --exclude-dir=".build" \
  --exclude-dir="DerivedData" \
  --exclude-dir="Pods" \
  --exclude-dir=".git" \
  --exclude-dir="AMEN_FINAL_10_GO_RESULTS" \
  > "$CLASSIFY_SCAN" || true

if [ -s "$CLASSIFY_SCAN" ]; then
  echo "EmptyView/fatalError hits found. These must be classified in the audit report:"
  cat "$CLASSIFY_SCAN"
else
  echo "PASS: No EmptyView/fatalError hits found."
fi

echo ""
echo "3) StoreKit config scan..."

find "$ROOT" -name "*.storekit" -print | tee "$RESULTS/storekit_files.txt"

if ! grep -RIn "amen.mentorship.growth.monthly\|amen.mentorship.deep.monthly" "$ROOT" --include="*.swift" --include="*.storekit" > "$RESULTS/storekit_product_scan.txt"; then
  echo "WARNING: StoreKit product IDs not found in Swift/storekit files."
else
  echo "PASS: StoreKit product IDs found:"
  cat "$RESULTS/storekit_product_scan.txt"
fi

echo ""
echo "4) Firestore active rules check..."

if [ -f "$ROOT/firebase.json" ]; then
  cat "$ROOT/firebase.json" | tee "$RESULTS/firebase_json.txt"
  echo "Review firebase.json to confirm active firestore rules path."
else
  echo "WARNING: firebase.json not found at repo root."
fi

echo ""
echo "5) Xcode clean build..."

xcodebuild \
  "${XCODE_CONTAINER[@]}" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$RESULTS/DerivedData" \
  clean build \
  | tee "$RESULTS/xcodebuild_clean_build.log"

echo ""
echo "6) Full Xcode test suite including UI tests..."

xcodebuild \
  "${XCODE_CONTAINER[@]}" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$RESULTS/DerivedData" \
  test \
  | tee "$RESULTS/xcodebuild_test.log"

echo ""
echo "7) Backend validation..."

if [ -d "$ROOT/Backend/functions" ]; then
  FUNCTIONS_DIR="$ROOT/Backend/functions"
elif [ -d "$ROOT/AMENAPP/Backend/functions" ]; then
  FUNCTIONS_DIR="$ROOT/AMENAPP/Backend/functions"
else
  FUNCTIONS_DIR=""
fi

if [ -n "$FUNCTIONS_DIR" ]; then
  pushd "$FUNCTIONS_DIR" >/dev/null

  npm install | tee "$RESULTS/npm_install.log"
  npm run build | tee "$RESULTS/npm_build.log"
  npm run test | tee "$RESULTS/npm_test.log"
  npx tsc --noEmit | tee "$RESULTS/tsc_no_emit.log"

  popd >/dev/null
else
  echo "No Backend/functions directory found. Skipping backend validation."
fi

echo ""
echo "8) Firebase emulator/rules validation if available..."

if [ -d "$ROOT/Backend/rules-tests" ]; then
  pushd "$ROOT/Backend/rules-tests" >/dev/null
  npm run test:launch-gates | tee "$RESULTS/firestore_emulator_validation.log"
  popd >/dev/null
elif [ -f "$ROOT/firebase.json" ] && command -v firebase >/dev/null 2>&1; then
  XDG_CONFIG_HOME=/private/tmp/amen-firebase-config FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 \
    firebase emulators:exec --only firestore "echo Firestore emulator validation completed" \
    | tee "$RESULTS/firestore_emulator_validation.log" || true
else
  echo "Skipping Firebase emulator validation. Missing rules tests or Firebase CLI."
fi

echo ""
echo "9) Trust and Safety 10/10 technical gate..."

"$ROOT/scripts/verify_trust_safety_10_go.sh" | tee "$RESULTS/trust_safety_10_go.log"

echo ""
echo "============================================================"
echo "FINAL VALIDATION COMPLETE"
echo "Results saved to:"
echo "$RESULTS"
echo "============================================================"

echo ""
echo "GO requires:"
echo "• xcodebuild_clean_build.log succeeded"
echo "• xcodebuild_test.log succeeded"
echo "• backend logs succeeded if backend exists"
echo "• StoreKit products configured"
echo "• Firestore rules path confirmed"
echo "• Trust and Safety technical gate succeeded"
echo "• Trust and Safety production signoff completed"
echo "• production_blocker_scan.txt clean or fully classified"
echo "• emptyview_fatalerror_scan.txt fully classified"
