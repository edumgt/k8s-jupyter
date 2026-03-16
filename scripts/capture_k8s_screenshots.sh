#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/docs/screenshots}"
PLAYWRIGHT_IMAGE="${PLAYWRIGHT_IMAGE:-mcr.microsoft/playwright:v1.53.0-jammy}"
DRY_RUN=0
ENV_VARS=(
  CAPTURE_TARGETS
  PLAYWRIGHT_IMAGE
  FRONTEND_URL
  BACKEND_URL
  AIRFLOW_URL
  JUPYTER_URL
  GITLAB_URL
  GITLAB_USERNAME
  GITLAB_PASSWORD
  GITLAB_ROOT_PASSWORD
  GITLAB_DEV1_USERNAME
  GITLAB_DEV1_PASSWORD
  GITLAB_DEV2_USERNAME
  GITLAB_DEV2_PASSWORD
  BACKEND_GIT_FLOW_FILE
  FRONTEND_GIT_FLOW_FILE
  BROWSER_CDP_URL
  ADMIN_USERNAME
  ADMIN_PASSWORD
  CONTROL_PLANE_USERNAME
  CONTROL_PLANE_PASSWORD
  TEST1_USERNAME
  TEST1_PASSWORD
  TEST1_LAB_URL
)

usage() {
  cat <<'EOF'
Usage: bash scripts/capture_k8s_screenshots.sh [options]

Options:
  --dry-run   Print the Playwright container command without executing it.
  -h, --help  Show this help.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

build_env_args() {
  local item
  for item in "${ENV_VARS[@]}"; do
    if [[ -n "${!item:-}" ]]; then
      DOCKER_ENV_ARGS+=(-e "${item}=${!item}")
    fi
  done
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

while [[ $# -gt 0 ]]; do
  case "$1" in
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

require_command docker
run_cmd mkdir -p "${OUTPUT_DIR}"
if [[ "${OUTPUT_DIR}" == "${ROOT_DIR}"/* ]]; then
  CONTAINER_OUTPUT_DIR="${CONTAINER_OUTPUT_DIR:-/workspace/${OUTPUT_DIR#${ROOT_DIR}/}}"
else
  CONTAINER_OUTPUT_DIR="${CONTAINER_OUTPUT_DIR:-/workspace/docs/screenshots}"
fi
DOCKER_ENV_ARGS=()
build_env_args

run_cmd docker run --rm \
  --network host \
  -v "${ROOT_DIR}:/workspace" \
  -w /workspace \
  -e "OUTPUT_DIR=${CONTAINER_OUTPUT_DIR}" \
  "${DOCKER_ENV_ARGS[@]}" \
  "${PLAYWRIGHT_IMAGE}" \
  bash -lc 'created_link=0; if [[ ! -e /workspace/node_modules && -d /opt/playwright-runner/node_modules ]]; then ln -s /opt/playwright-runner/node_modules /workspace/node_modules; created_link=1; fi; node scripts/playwright/capture.mjs; status=$?; if [[ "${created_link}" == "1" ]]; then rm -f /workspace/node_modules; fi; exit "${status}"'
