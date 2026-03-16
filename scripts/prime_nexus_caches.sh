#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEXUS_URL="${NEXUS_URL:-http://127.0.0.1:30091}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/dist/nexus-prime}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash scripts/prime_nexus_caches.sh [options]

Options:
  --nexus-url <url>  Reachable Nexus base URL. Defaults to http://127.0.0.1:30091.
  --out-dir <path>   Directory where the warmed cache artifacts will be stored.
  --dry-run          Print commands without executing them.
  -h, --help         Show this help.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

run_cmd() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

download_python_requirements() {
  local app_name="$1"
  local requirements_file="$2"
  local host_name="${NEXUS_URL#http://}"
  host_name="${host_name#https://}"
  host_name="${host_name%%/*}"
  host_name="${host_name%%:*}"

  run_cmd mkdir -p "${OUT_DIR}/wheels/${app_name}"
  run_cmd python3 -m pip download \
    --dest "${OUT_DIR}/wheels/${app_name}" \
    --index-url "${NEXUS_URL}/repository/pypi-all/simple" \
    --trusted-host "${host_name}" \
    -r "${requirements_file}"
}

prime_frontend_registry() {
  local cache_dir="${OUT_DIR}/npm-cache"
  local temp_dir

  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '+ %q\n' "npm install --cache ${cache_dir} --ignore-scripts --registry ${NEXUS_URL}/repository/npm-all/"
    return 0
  fi

  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  mkdir -p "${cache_dir}" "${temp_dir}/home"
  cp "${ROOT_DIR}/apps/frontend/package.json" "${temp_dir}/package.json"
  (
    cd "${temp_dir}"
    HOME="${temp_dir}/home" npm install --cache "${cache_dir}" --ignore-scripts --registry "${NEXUS_URL}/repository/npm-all/"
  )
  cp "${temp_dir}/package-lock.json" "${OUT_DIR}/frontend-package-lock.json"
  rm -rf "${temp_dir}"
  trap - RETURN
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nexus-url)
      [[ $# -ge 2 ]] || die "--nexus-url requires a value"
      NEXUS_URL="$2"
      shift 2
      ;;
    --out-dir)
      [[ $# -ge 2 ]] || die "--out-dir requires a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

require_command python3
require_command npm

run_cmd mkdir -p "${OUT_DIR}"
download_python_requirements backend "${ROOT_DIR}/apps/backend/requirements.txt"
download_python_requirements jupyter "${ROOT_DIR}/apps/jupyter/requirements.txt"
download_python_requirements airflow "${ROOT_DIR}/apps/airflow/requirements.txt"
prime_frontend_registry

printf 'Nexus caches warmed via %s\n' "${NEXUS_URL}"
