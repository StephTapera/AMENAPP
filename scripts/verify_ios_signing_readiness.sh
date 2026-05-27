#!/usr/bin/env bash
set -euo pipefail

APP_GROUP_ID="${APP_GROUP_ID:-group.com.amenapp.shared}"
PROJECT_FILE="${PROJECT_FILE:-AMENAPP.xcodeproj/project.pbxproj}"
MAIN_DEBUG_ENTITLEMENTS="${MAIN_DEBUG_ENTITLEMENTS:-AMENAPP/AMENAPP.entitlements}"
MAIN_RELEASE_ENTITLEMENTS="${MAIN_RELEASE_ENTITLEMENTS:-AMENAPP/AMENAPP.release.entitlements}"
SHARE_ENTITLEMENTS="${SHARE_ENTITLEMENTS:-AMENShareExtension/AMENShareExtension.entitlements}"
PROFILE_DIR="${PROFILE_DIR:-${HOME}/Library/MobileDevice/Provisioning Profiles}"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "Missing required file: ${path}" >&2
    exit 1
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
}

require_app_group_in_entitlements() {
  local path="$1"
  if ! /usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups" "${path}" 2>/dev/null | grep -q "${APP_GROUP_ID}"; then
    echo "Entitlements file does not include ${APP_GROUP_ID}: ${path}" >&2
    exit 1
  fi
}

require_project_reference() {
  local path="$1"
  if ! grep -q "CODE_SIGN_ENTITLEMENTS = ${path};" "${PROJECT_FILE}"; then
    echo "Xcode project does not reference entitlements file: ${path}" >&2
    exit 1
  fi
}

has_codesigning_identity() {
  security find-identity -p codesigning -v 2>/dev/null | grep -Eq "Apple Development|Apple Distribution|iPhone Developer|iPhone Distribution"
}

profile_contains_app_group() {
  local profile="$1"
  security cms -D -i "${profile}" 2>/dev/null | grep -q "${APP_GROUP_ID}"
}

require_file "${PROJECT_FILE}"
require_file "${MAIN_DEBUG_ENTITLEMENTS}"
require_file "${MAIN_RELEASE_ENTITLEMENTS}"
require_file "${SHARE_ENTITLEMENTS}"
require_command security

echo "Checking App Group entitlement files..."
require_app_group_in_entitlements "${MAIN_DEBUG_ENTITLEMENTS}"
require_app_group_in_entitlements "${MAIN_RELEASE_ENTITLEMENTS}"
require_app_group_in_entitlements "${SHARE_ENTITLEMENTS}"

echo "Checking Xcode project entitlement references..."
require_project_reference "${MAIN_RELEASE_ENTITLEMENTS}"
require_project_reference "${SHARE_ENTITLEMENTS}"

echo "Checking local Apple code signing identities..."
if ! has_codesigning_identity; then
  echo "No Apple code signing identity was found in the local keychain." >&2
  echo "Sign in to Xcode with the Apple Developer account and download/create signing certificates." >&2
  exit 1
fi

echo "Checking installed provisioning profiles for ${APP_GROUP_ID}..."
if [[ ! -d "${PROFILE_DIR}" ]]; then
  echo "No local provisioning profile directory found: ${PROFILE_DIR}" >&2
  echo "Open Xcode Settings > Accounts, select the team, and download profiles after enabling the App Group." >&2
  exit 1
fi

matching_profile=""
while IFS= read -r -d '' profile; do
  if profile_contains_app_group "${profile}"; then
    matching_profile="${profile}"
    break
  fi
done < <(find "${PROFILE_DIR}" -name "*.mobileprovision" -print0 2>/dev/null)

if [[ -z "${matching_profile}" ]]; then
  echo "No installed provisioning profile includes ${APP_GROUP_ID}." >&2
  echo "Enable App Groups for the app ID and share extension in Apple Developer, regenerate profiles, then download them in Xcode." >&2
  exit 1
fi

echo "Found provisioning profile with ${APP_GROUP_ID}: ${matching_profile}"
echo "iOS signing readiness checks passed."
