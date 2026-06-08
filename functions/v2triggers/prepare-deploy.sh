#!/bin/bash
# prepare-deploy.sh
# Pre-deploy script for the v2triggers codebase.
#
# Copies files from the parent functions/ directory into v2triggers/
# so that the Firebase CLI can bundle a self-contained codebase.
#
# Called by firebase.json predeploy hook:
#   "predeploy": ["bash $RESOURCE_DIR/prepare-deploy.sh"]
#
# Files copied (relative to functions/):
#   v2entry.js
#   v2functions.js
#   v2intelligenceFunctions.js
#   shabbatMiddleware.js
#   intelligence/ (entire directory, for digestBuilder + contracts)

set -e

# $RESOURCE_DIR is set by Firebase CLI to the source directory (functions/v2triggers)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_DIR="$SCRIPT_DIR"

echo "[prepare-deploy] Source parent: $PARENT_DIR"
echo "[prepare-deploy] Target:        $TARGET_DIR"

# Copy top-level v2 files
for FILE in v2entry.js v2functions.js v2intelligenceFunctions.js shabbatMiddleware.js \
            biblicalAlignmentFunctions.js feedContextFunctions.js smartInboxDenormalization.js \
            alignmentPipeline.js rateLimiter.js 242hub.js; do
    echo "[prepare-deploy] Copying $FILE"
    cp "$PARENT_DIR/$FILE" "$TARGET_DIR/$FILE"
done

# Copy intelligence/ directory (needed by digestBuilder.js, contracts.js, etc.)
echo "[prepare-deploy] Copying intelligence/ directory"
rm -rf "$TARGET_DIR/intelligence"
cp -r "$PARENT_DIR/intelligence" "$TARGET_DIR/intelligence"

# Copy router/ directory (needed by Berean callables via callModel.js)
echo "[prepare-deploy] Copying router/ directory"
rm -rf "$TARGET_DIR/router"
cp -r "$PARENT_DIR/router" "$TARGET_DIR/router"

# Copy mlClients.js (needed by router/callModel.js)
echo "[prepare-deploy] Copying mlClients.js"
cp "$PARENT_DIR/mlClients.js" "$TARGET_DIR/mlClients.js"

# Copy selah/ directory (needed by Selah corpus + discernment callables)
echo "[prepare-deploy] Copying selah/ directory (js files only)"
rm -rf "$TARGET_DIR/selah"
mkdir -p "$TARGET_DIR/selah"
for SF in bibleProviderAdapter.js discernmentEngine.js discernmentPrompts.js \
          openLicenseVerseService.js selahCorpusService.js selahCorpusUtils.js; do
    cp "$PARENT_DIR/selah/$SF" "$TARGET_DIR/selah/$SF"
done

# Copy node_modules symlink reference by creating a symlink to parent node_modules
# (Firebase CLI will not follow this symlink during upload; instead we copy the
#  package.json so npm install runs in the target directory)
if [ -L "$TARGET_DIR/node_modules" ]; then
    rm "$TARGET_DIR/node_modules"
fi

echo "[prepare-deploy] Done — v2triggers bundle is ready"
