#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_DIR="${APP_DIR:-/opt/k8s-data-platform/apps/dataxflow-frontend}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-31080}"
API_BASE_URL="${VITE_API_BASE_URL:-http://api.dataxflow.local}"

exec bash "${SCRIPT_DIR}/run_frontend_dev.sh" \
  --app-dir "${APP_DIR}" \
  --host "${HOST}" \
  --port "${PORT}" \
  --api-base "${API_BASE_URL}" \
  "$@"
