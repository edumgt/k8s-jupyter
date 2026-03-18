#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/k8s-data-platform/apps/frontend}"
CACHE_DIR="${CACHE_DIR:-/opt/k8s-data-platform/offline-bundle/npm-cache}"
NPM_REGISTRY="${NPM_REGISTRY:-http://127.0.0.1:30091/repository/npm-group/}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash scripts/frontend_dev_setup.sh [options]

Options:
  --app-dir <path>      Frontend application directory.
  --cache-dir <path>    Offline npm cache directory.
  --registry <url>      Preferred Nexus npm registry URL.
  --dry-run             Print commands without executing them.
  -h, --help            Show this help.
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-dir)
      [[ $# -ge 2 ]] || die "--app-dir requires a value"
      APP_DIR="$2"
      shift 2
      ;;
    --cache-dir)
      [[ $# -ge 2 ]] || die "--cache-dir requires a value"
      CACHE_DIR="$2"
      shift 2
      ;;
    --registry)
      [[ $# -ge 2 ]] || die "--registry requires a value"
      NPM_REGISTRY="$2"
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

require_command npm
[[ -d "${APP_DIR}" ]] || die "Frontend app directory not found: ${APP_DIR}"

run_cmd mkdir -p "${CACHE_DIR}"

if [[ "${DRY_RUN}" == "1" ]]; then
  printf '+ (cd %q && npm config set registry %q)\n' "${APP_DIR}" "${NPM_REGISTRY}"
  printf '+ (cd %q && npm install --cache %q --prefer-offline)\n' "${APP_DIR}" "${CACHE_DIR}"
  printf '+ (cd %q && npm install --cache %q --offline)\n' "${APP_DIR}" "${CACHE_DIR}"
  exit 0
fi

(
  cd "${APP_DIR}"
  npm config set registry "${NPM_REGISTRY}"
  if npm install --cache "${CACHE_DIR}" --prefer-offline; then
    exit 0
  fi

  printf '[frontend_dev_setup] Nexus install failed, retrying with offline cache only.\n' >&2
  npm install --cache "${CACHE_DIR}" --offline
)
