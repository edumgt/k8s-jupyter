#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/dist/offline-bundle}"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-edumgt}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DRY_RUN=0
SKIP_IMAGES=0

usage() {
  cat <<'EOF'
Usage: bash scripts/prepare_offline_bundle.sh [options]

Options:
  --out-dir <path>    Output directory for offline images and package caches.
  --namespace <name>  Docker Hub namespace used for mirrored images. Defaults to edumgt.
  --tag <tag>         Platform app image tag. Defaults to latest.
  --skip-images       Reuse an existing image archive directory and only refresh library caches.
  --dry-run           Print commands without executing them.
  -h, --help          Show this help.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
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

download_python_requirements() {
  local app_name="$1"
  local requirements_file="$2"
  local target_dir="${OUT_DIR}/wheels/${app_name}"

  run_cmd mkdir -p "${target_dir}"
  run_cmd python3 -m pip download --dest "${target_dir}" -r "${requirements_file}"
}

cache_frontend_packages() {
  local cache_dir="${OUT_DIR}/npm-cache"
  local temp_dir

  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '+ %q %q\n' "npm install --prefix <temp-dir> --cache ${cache_dir} --ignore-scripts" "<package.json>"
    return 0
  fi

  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  mkdir -p "${cache_dir}" "${temp_dir}/home"
  cp "${ROOT_DIR}/apps/frontend/package.json" "${temp_dir}/package.json"
  (
    cd "${temp_dir}"
    HOME="${temp_dir}/home" npm install --cache "${cache_dir}" --ignore-scripts
  )
  cp "${temp_dir}/package-lock.json" "${OUT_DIR}/frontend-package-lock.json"
  rm -rf "${temp_dir}"
  trap - RETURN
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      [[ $# -ge 2 ]] || die "--out-dir requires a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --namespace)
      [[ $# -ge 2 ]] || die "--namespace requires a value"
      IMAGE_NAMESPACE="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || die "--tag requires a value"
      IMAGE_TAG="$2"
      shift 2
      ;;
    --skip-images)
      SKIP_IMAGES=1
      shift
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

require_command bash
require_command docker
require_command python3
require_command npm

run_cmd mkdir -p "${OUT_DIR}" "${OUT_DIR}/images"

if [[ "${SKIP_IMAGES}" != "1" ]]; then
  run_cmd env TMP_DIR="${OUT_DIR}/images" IMAGE_NAMESPACE="${IMAGE_NAMESPACE}" IMAGE_TAG="${IMAGE_TAG}" \
    bash "${ROOT_DIR}/scripts/build_k8s_images.sh" --namespace "${IMAGE_NAMESPACE}" --tag "${IMAGE_TAG}" --skip-k3s-import
fi

download_python_requirements backend "${ROOT_DIR}/apps/backend/requirements.txt"
download_python_requirements jupyter "${ROOT_DIR}/apps/jupyter/requirements.txt"
download_python_requirements airflow "${ROOT_DIR}/apps/airflow/requirements.txt"
cache_frontend_packages
