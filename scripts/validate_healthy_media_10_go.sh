#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/AMENAPP.xcodeproj"
SCHEME="${AMEN_SCHEME:-AMENAPP}"
DESTINATION="${AMEN_DESTINATION:-platform=iOS Simulator,name=iPhone 16}"
DERIVED_DATA="${AMEN_DERIVED_DATA:-${ROOT_DIR}/.derivedData/HealthyMediaGO}"
SOURCE_PACKAGES="${AMEN_SOURCE_PACKAGES:-${ROOT_DIR}/.sourcePackages/HealthyMediaGO}"
FUNCTIONS_DIR="${ROOT_DIR}/functions"

section() {
  printf '\n== %s ==\n' "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 127
  fi
}

section "Toolchain"
require_command xcodebuild
require_command node
require_command npm
require_command firebase
node -v
npm -v
firebase --version

section "Writable validation caches"
mkdir -p "${DERIVED_DATA}" "${SOURCE_PACKAGES}"
test -w "${DERIVED_DATA}"
test -w "${SOURCE_PACKAGES}"

section "Xcode package resolution"
xcodebuild \
  -resolvePackageDependencies \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES}"

section "iOS clean build"
xcodebuild \
  clean build \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES}"

section "iOS full test suite"
xcodebuild \
  test \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES}"

section "Backend dependencies"
cd "${FUNCTIONS_DIR}"
npm install

section "Backend media tests"
npm run test:media

section "Backend lint"
npm run lint

section "Backend TypeScript gates"
if [ -f tsconfig.json ]; then
  npx tsc --noEmit
else
  printf 'No functions/tsconfig.json found; skipping general TypeScript noEmit.\n'
fi

if npm run | grep -q "build:notifications"; then
  npm run build:notifications
fi

section "Firebase emulator rules tests"
npm run test:media:rules

section "10/10 GO gate passed"
printf 'Healthy Immersive Media validation completed successfully.\n'
