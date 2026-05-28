#!/usr/bin/env bash
set -euo pipefail

RESOURCE_DIR="${1:?RESOURCE_DIR is required}"
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
npm --prefix "${RESOURCE_DIR}" run build
