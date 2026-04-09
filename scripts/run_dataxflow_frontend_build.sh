#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_DIR="${APP_DIR:-/opt/k8s-data-platform/apps/dataxflow-frontend}"

exec bash "${SCRIPT_DIR}/run_frontend_build.sh" \
  --app-dir "${APP_DIR}" \
  "$@"
