#!/usr/bin/env bash
# setup-spm-artifacts.sh
# AMENAPP — Binary SPM Package Setup
#
# Run this script once on a fresh machine or CI agent when the build fails with:
#   "No XCFramework found at artifacts/abseil-cpp-binary/absl/absl.xcframework"
#
# Root cause: Xcode resolves these binary packages (abseil, grpc, WebRTC) successfully
# but the SPM extractor silently fails to place XCFrameworks in the artifacts/ directory.
# This script downloads the ZIPs and extracts them manually.
#
# Usage:
#   chmod +x scripts/setup-spm-artifacts.sh
#   ./scripts/setup-spm-artifacts.sh
#
# Versions pinned to Package.resolved (update if SPM versions change):
#   abseil-cpp-binary  1.2024072200.0
#   grpc-binary        1.69.1
#   webrtc-xcframework 144.7559.6

set -euo pipefail

DERIVED_DATA=$(xcodebuild -project AMENAPP.xcodeproj -showBuildSettings 2>/dev/null \
  | grep -m 1 " BUILT_PRODUCTS_DIR " | awk '{print $3}' \
  | sed 's|/Build/Products/.*||')

if [[ -z "$DERIVED_DATA" ]]; then
  # Fallback: find AMEN DerivedData directory
  DERIVED_DATA=$(ls ~/Library/Developer/Xcode/DerivedData/ 2>/dev/null \
    | grep "^AMENAPP-" | head -1 | xargs -I{} echo "$HOME/Library/Developer/Xcode/DerivedData/{}")
fi

ARTIFACTS_DIR="$DERIVED_DATA/SourcePackages/artifacts"
WORK_DIR=$(mktemp -d)

echo "📦 AMEN SPM Binary Artifact Setup"
echo "Artifacts dir: $ARTIFACTS_DIR"
echo "Temp work dir: $WORK_DIR"

# ── abseil-cpp-binary ────────────────────────────────────────────────────────

ABSL_DEST="$ARTIFACTS_DIR/abseil-cpp-binary/absl/absl.xcframework"
if [ -d "$ABSL_DEST" ]; then
  echo "✅ abseil-cpp-binary already present — skipping"
else
  echo "⬇️  Downloading abseil-cpp-binary 1.2024072200.0..."
  ABSL_ZIP="$WORK_DIR/absl.zip"
  curl -L --fail -o "$ABSL_ZIP" \
    "https://github.com/google/abseil-cpp-binary/releases/download/1.2024072200.0/absl.xcframework.zip"
  mkdir -p "$ARTIFACTS_DIR/abseil-cpp-binary/absl"
  unzip -q "$ABSL_ZIP" -d "$WORK_DIR/absl"
  cp -R "$WORK_DIR/absl/absl.xcframework" "$ARTIFACTS_DIR/abseil-cpp-binary/absl/"
  echo "✅ abseil-cpp-binary installed"
fi

# ── grpc-binary ──────────────────────────────────────────────────────────────

GRPC_DEST="$ARTIFACTS_DIR/grpc-binary/grpc/grpc.xcframework"
if [ -d "$GRPC_DEST" ]; then
  echo "✅ grpc-binary already present — skipping"
else
  echo "⬇️  Downloading grpc-binary 1.69.1..."
  mkdir -p "$ARTIFACTS_DIR/grpc-binary/grpc"
  mkdir -p "$ARTIFACTS_DIR/grpc-binary/grpcpp"
  mkdir -p "$ARTIFACTS_DIR/grpc-binary/openssl_grpc"

  for target in grpc grpcpp openssl_grpc; do
    ZIP="$WORK_DIR/${target}.zip"
    curl -L --fail -o "$ZIP" \
      "https://github.com/google/grpc-binary/releases/download/1.69.1/${target}.xcframework.zip"
    unzip -q "$ZIP" -d "$WORK_DIR/${target}"
    cp -R "$WORK_DIR/${target}/${target}.xcframework" \
      "$ARTIFACTS_DIR/grpc-binary/${target}/"
  done
  echo "✅ grpc-binary installed"
fi

# ── webrtc-xcframework ───────────────────────────────────────────────────────

WEBRTC_DEST="$ARTIFACTS_DIR/webrtc-xcframework/LiveKitWebRTC/LiveKitWebRTC.xcframework"
if [ -d "$WEBRTC_DEST" ]; then
  echo "✅ webrtc-xcframework already present — skipping"
else
  echo "⬇️  Downloading webrtc-xcframework 144.7559.6..."
  WEBRTC_ZIP="$WORK_DIR/LiveKitWebRTC.zip"
  curl -L --fail -o "$WEBRTC_ZIP" \
    "https://github.com/livekit/webrtc-xcframework/releases/download/144.7559.6/LiveKitWebRTC.xcframework.zip"
  mkdir -p "$ARTIFACTS_DIR/webrtc-xcframework/LiveKitWebRTC"
  unzip -q "$WEBRTC_ZIP" -d "$WORK_DIR/webrtc"
  cp -R "$WORK_DIR/webrtc/LiveKitWebRTC.xcframework" \
    "$ARTIFACTS_DIR/webrtc-xcframework/LiveKitWebRTC/"
  echo "✅ webrtc-xcframework installed"
fi

# ── Cleanup ──────────────────────────────────────────────────────────────────

rm -rf "$WORK_DIR"

echo ""
echo "🎉 All binary SPM artifacts are in place. You can now build the project."
