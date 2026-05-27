#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${FIREBASE_PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}"
FUNCTIONS_DIR="Backend/functions"
FIREBASE_CMD="${FIREBASE_CMD:-firebase}"
GCLOUD_CMD="${GCLOUD_CMD:-gcloud}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Set FIREBASE_PROJECT_ID or GOOGLE_CLOUD_PROJECT before running." >&2
  exit 1
fi

if [[ ! -d "${FUNCTIONS_DIR}" ]]; then
  echo "Run this script from the repository root." >&2
  exit 1
fi

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
}

require_enabled_service() {
  local service_name="$1"
  if ! "${GCLOUD_CMD}" services list \
    --enabled \
    --project "${PROJECT_ID}" \
    --filter="config.name:${service_name}" \
    --format="value(config.name)" | grep -qx "${service_name}"; then
    echo "Required Google Cloud API is not enabled: ${service_name}" >&2
    exit 1
  fi
}

require_secret() {
  local secret_name="$1"
  if ! "${FIREBASE_CMD}" functions:secrets:access "${secret_name}" \
    --project "${PROJECT_ID}" \
    --non-interactive >/dev/null 2>&1; then
    echo "Required Firebase Functions secret is missing or inaccessible: ${secret_name}" >&2
    exit 1
  fi
}

require_source_export() {
  local export_name="$1"
  if ! grep -R "export const ${export_name}" "${FUNCTIONS_DIR}/src/churchDiscovery" >/dev/null; then
    echo "Missing church discovery callable export in source: ${export_name}" >&2
    exit 1
  fi
}

require_command "${FIREBASE_CMD}"
require_command "${GCLOUD_CMD}"

echo "Checking Google Cloud APIs for ${PROJECT_ID}..."
require_enabled_service "places.googleapis.com"
require_enabled_service "maps-ios-backend.googleapis.com"
require_enabled_service "cloudfunctions.googleapis.com"
require_enabled_service "firestore.googleapis.com"

echo "Checking Firebase Functions secrets..."
require_secret "OPENAI_API_KEY"
require_secret "GOOGLE_PLACES_API_KEY"
require_secret "GOOGLE_MAPS_API_KEY"

echo "Checking callable source exports..."
require_source_export "parseChurchSearchIntent"
require_source_export "searchChurchesAndCommunities"
require_source_export "getChurchDiscoveryDetails"
require_source_export "saveChurchDiscoveryPreference"
require_source_export "saveChurchCandidate"
require_source_export "logChurchDiscoveryInteraction"
require_source_export "clearChurchDiscoveryHistory"
require_source_export "refreshChurchPlaceDetails"

echo "Running backend compile/lint/tests..."
(
  cd "${FUNCTIONS_DIR}"
  npm run build
  npm run typecheck
  npm run lint -- --quiet
  npm run test -- --runTestsByPath src/churchDiscovery/churchDiscovery.test.ts
)

echo "Church discovery live readiness checks passed for ${PROJECT_ID}."
