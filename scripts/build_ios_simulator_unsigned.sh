#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-AMENAPP.xcodeproj}"
SCHEME="${SCHEME:-AMENAPP}"
SDK="${SDK:-iphonesimulator}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/amen-xcode-derived-data}"
SOURCE_PACKAGES_PATH="${SOURCE_PACKAGES_PATH:-/private/tmp/amen-xcode-source-packages}"
XCODEBUILD_CMD="${XCODEBUILD_CMD:-xcodebuild}"

if [[ ! -d "${PROJECT_PATH}" ]]; then
  echo "Missing Xcode project: ${PROJECT_PATH}" >&2
  exit 1
fi

mkdir -p "${DERIVED_DATA_PATH}" "${SOURCE_PACKAGES_PATH}"

echo "Building ${SCHEME} for ${SDK} with code signing disabled..."
echo "DerivedData: ${DERIVED_DATA_PATH}"
echo "SourcePackages: ${SOURCE_PACKAGES_PATH}"

"${XCODEBUILD_CMD}" \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -sdk "${SDK}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_PATH}" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
