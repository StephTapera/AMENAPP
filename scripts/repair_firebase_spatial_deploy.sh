#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-amen-5e359}"
APP_ENGINE_REGION="${APP_ENGINE_REGION:-us-central}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_NODE="$ROOT_DIR/.local/node/node-v20.19.0-darwin-arm64/bin"

if [[ -d "$LOCAL_NODE" ]]; then
  export PATH="$LOCAL_NODE:$PATH"
fi

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/private/tmp/amen-config}"
export npm_config_cache="${npm_config_cache:-/private/tmp/amen-npm-cache}"
export CI="${CI:-true}"

cd "$ROOT_DIR"

if ! command -v firebase >/dev/null 2>&1; then
  FIREBASE=(npx firebase-tools)
else
  FIREBASE=(firebase)
fi

echo "== Firebase project =="
"${FIREBASE[@]}" use "$PROJECT_ID"

echo "== Required APIs =="
if command -v gcloud >/dev/null 2>&1; then
  gcloud services enable \
    appengine.googleapis.com \
    cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    run.googleapis.com \
    eventarc.googleapis.com \
    secretmanager.googleapis.com \
    firebaserules.googleapis.com \
    firestore.googleapis.com \
    --project "$PROJECT_ID"

  if ! gcloud app describe --project "$PROJECT_ID" >/dev/null 2>&1; then
    echo "Creating App Engine app in $APP_ENGINE_REGION for Cloud Functions Gen 1 compatibility..."
    gcloud app create --project "$PROJECT_ID" --region "$APP_ENGINE_REGION"
  else
    echo "App Engine app already exists."
  fi
else
  echo "gcloud is not installed; skipping App Engine/API repair."
  echo "Install Google Cloud SDK, then rerun this script if Functions deploy still fails with FAILED_PRECONDITION."
fi

echo "== Local validation =="
npm --prefix Backend/spatial-functions run typecheck
npm --prefix Backend/spatial-functions run build
npm --prefix Backend/functions run build

echo "== Deploy indexes and storage =="
"${FIREBASE[@]}" deploy --project "$PROJECT_ID" --only firestore:indexes,storage

echo "== Deploy Spatial Rooms Functions =="
"${FIREBASE[@]}" deploy --project "$PROJECT_ID" --only functions:spatial

echo "Spatial Rooms deploy completed."
