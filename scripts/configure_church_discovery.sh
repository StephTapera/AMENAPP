#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${FIREBASE_PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Set FIREBASE_PROJECT_ID or GOOGLE_CLOUD_PROJECT before running." >&2
  exit 1
fi

gcloud services enable \
  places.googleapis.com \
  maps-ios-backend.googleapis.com \
  firestore.googleapis.com \
  cloudfunctions.googleapis.com \
  --project "${PROJECT_ID}"

firebase functions:secrets:set OPENAI_API_KEY --project "${PROJECT_ID}"
firebase functions:secrets:set ANTHROPIC_API_KEY --project "${PROJECT_ID}"
firebase functions:secrets:set GOOGLE_MAPS_API_KEY --project "${PROJECT_ID}"
firebase functions:secrets:set GOOGLE_PLACES_API_KEY --project "${PROJECT_ID}"

firebase functions:config:set \
  amen.ai_provider_mode="${AMEN_AI_PROVIDER_MODE:-openai}" \
  amen.church_discovery_enabled=true \
  --project "${PROJECT_ID}"

echo "Church discovery APIs, secrets, and Firebase config are ready for deploy."
