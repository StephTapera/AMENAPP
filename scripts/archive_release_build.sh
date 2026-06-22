#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SCHEME="${XCODE_SCHEME:-AMENAPP}"
CONFIGURATION="${XCODE_CONFIGURATION:-Release}"
ARCHIVE_DIR="${ARCHIVE_DIR:-$ROOT/AMEN_FINAL_10_GO_RESULTS/archives}"
ARCHIVE_PATH="$ARCHIVE_DIR/${SCHEME}.xcarchive"

mkdir -p "$ARCHIVE_DIR"

echo "Archiving scheme '$SCHEME' with configuration '$CONFIGURATION'"
echo "Archive path: $ARCHIVE_PATH"

xcodebuild archive \
  -project "$ROOT/AMENAPP.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH"

echo ""
echo "Archive complete. Smoke test the archived build, then update Docs/RELEASE_ARCHIVE_TEST_RECORD.md with:"
echo "RELEASE_ARCHIVE_CREATED=true"
echo "RELEASE_ARCHIVE_TESTED=true"
echo "RELEASE_ARCHIVE_SCHEME=$SCHEME"
echo "RELEASE_ARCHIVE_CONFIGURATION=$CONFIGURATION"
echo "RELEASE_ARCHIVE_BUILD_NUMBER=<build number from archived build>"
echo "RELEASE_ARCHIVE_TEST_DEVICE_OR_SIMULATOR=<tested device>"
