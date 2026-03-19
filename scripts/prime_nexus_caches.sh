#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEXUS_URL="${NEXUS_URL:-http://127.0.0.1:30091}"
NEXUS_USERNAME="${NEXUS_USERNAME:-}"
NEXUS_PASSWORD="${NEXUS_PASSWORD:-}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/dist/nexus-prime}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash scripts/prime_nexus_caches.sh [options]

Options:
  --nexus-url <url>  Reachable Nexus base URL. Defaults to http://127.0.0.1:30091.
  --username <name>  Nexus repository username (optional).
  --password <pw>    Nexus repository password (optional).
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

urlencode() {
  python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

index_url_with_auth() {
  local base_url="$1"
  local scheme
  local remainder
  local user_enc
  local pass_enc

  if [[ -z "${NEXUS_USERNAME}" || -z "${NEXUS_PASSWORD}" ]]; then
    printf '%s' "${base_url}"
    return 0
  fi

  scheme="${base_url%%://*}"
  remainder="${base_url#*://}"
  user_enc="$(urlencode "${NEXUS_USERNAME}")"
  pass_enc="$(urlencode "${NEXUS_PASSWORD}")"
  printf '%s://%s:%s@%s' "${scheme}" "${user_enc}" "${pass_enc}" "${remainder}"
}

registry_scope() {
  local url="$1"
  local scope="${url#http://}"
  scope="${scope#https://}"
  printf '%s' "${scope}"
}

download_python_requirements() {
  local app_name="$1"
  local requirements_file="$2"
  local index_url
  local shown_index_url
  local host_name="${NEXUS_URL#http://}"
  host_name="${host_name#https://}"
  host_name="${host_name%%/*}"
  host_name="${host_name%%:*}"
  index_url="$(index_url_with_auth "${NEXUS_URL}/repository/pypi-all/simple")"

  run_cmd mkdir -p "${OUT_DIR}/wheels/${app_name}"
  if [[ "${DRY_RUN}" == "1" ]]; then
    shown_index_url="${NEXUS_URL}/repository/pypi-all/simple"
    if [[ -n "${NEXUS_USERNAME}" && -n "${NEXUS_PASSWORD}" ]]; then
      shown_index_url="${shown_index_url} (auth)"
    fi
    printf '+ python3 -m pip download --dest %q --index-url %q --trusted-host %q --disable-pip-version-check -r %q\n' \
      "${OUT_DIR}/wheels/${app_name}" "${shown_index_url}" "${host_name}" "${requirements_file}"
    return 0
  fi
  run_cmd python3 -m pip download \
    --dest "${OUT_DIR}/wheels/${app_name}" \
    --index-url "${index_url}" \
    --trusted-host "${host_name}" \
    --disable-pip-version-check \
    -r "${requirements_file}"
}

prime_frontend_registry() {
  local cache_dir="${OUT_DIR}/npm-cache"
  local registry_url="${NEXUS_URL}/repository/npm-all/"
  local npm_scope
  local auth_b64
  local temp_dir

  npm_scope="$(registry_scope "${registry_url}")"

  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '+ %q\n' "npm install --cache ${cache_dir} --ignore-scripts --registry ${registry_url}"
    if [[ -n "${NEXUS_USERNAME}" && -n "${NEXUS_PASSWORD}" ]]; then
      printf '+ %q\n' "npm auth configured for //${npm_scope}"
    fi
    return 0
  fi

  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  mkdir -p "${cache_dir}" "${temp_dir}/home"
  cp "${ROOT_DIR}/apps/frontend/package.json" "${temp_dir}/package.json"
  if [[ -n "${NEXUS_USERNAME}" && -n "${NEXUS_PASSWORD}" ]]; then
    auth_b64="$(printf '%s:%s' "${NEXUS_USERNAME}" "${NEXUS_PASSWORD}" | base64 | tr -d '\n')"
    {
      printf 'registry=%s\n' "${registry_url}"
      printf 'always-auth=true\n'
      printf '//%s:_auth=%s\n' "${npm_scope}" "${auth_b64}"
    } > "${temp_dir}/home/.npmrc"
  fi
  (
    cd "${temp_dir}"
    HOME="${temp_dir}/home" npm install --cache "${cache_dir}" --ignore-scripts --registry "${registry_url}"
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
    --username)
      [[ $# -ge 2 ]] || die "--username requires a value"
      NEXUS_USERNAME="$2"
      shift 2
      ;;
    --password)
      [[ $# -ge 2 ]] || die "--password requires a value"
      NEXUS_PASSWORD="$2"
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
require_command base64

if [[ -n "${NEXUS_USERNAME}" && -z "${NEXUS_PASSWORD}" ]]; then
  die "--username is set but --password is empty"
fi

if [[ -z "${NEXUS_USERNAME}" && -n "${NEXUS_PASSWORD}" ]]; then
  die "--password is set but --username is empty"
fi

run_cmd mkdir -p "${OUT_DIR}"
download_python_requirements backend "${ROOT_DIR}/apps/backend/requirements.txt"
download_python_requirements jupyter "${ROOT_DIR}/apps/jupyter/requirements.txt"
download_python_requirements airflow "${ROOT_DIR}/apps/airflow/requirements.txt"
prime_frontend_registry

printf 'Nexus caches warmed via %s\n' "${NEXUS_URL}"
