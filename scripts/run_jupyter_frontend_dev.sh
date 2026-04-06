#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_DIR="${APP_DIR:-/opt/k8s-data-platform/apps/jupyter-frontend}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-31320}"
API_BASE_URL="${VITE_API_BASE_URL:-http://adw.local}"

exec bash "${SCRIPT_DIR}/run_frontend_dev.sh" \
  --app-dir "${APP_DIR}" \
  --host "${HOST}" \
  --port "${PORT}" \
  --api-base "${API_BASE_URL}" \
  "$@"
