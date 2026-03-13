#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WITH_RUNNER=0
DRY_RUN=0
ENVIRONMENT="dev"
NAMESPACE=""

usage() {
  cat <<'EOF'
Usage: bash scripts/apply_k8s.sh [options]

Options:
  --env <dev|prod> Apply the selected k8s environment overlay. Defaults to dev.
  --with-runner    Apply the optional GitLab Runner k8s overlay too.
  --dry-run        Print commands without executing them.
  -h, --help       Show this help.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

set_environment() {
  case "$1" in
    dev|prod)
      ENVIRONMENT="$1"
      NAMESPACE="data-platform-${ENVIRONMENT}"
      ;;
    *)
      die "Unsupported environment: $1 (expected: dev or prod)"
      ;;
  esac
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || die "--env requires a value"
      set_environment "$2"
      shift 2
      ;;
    --with-runner)
      WITH_RUNNER=1
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

require_command kubectl
set_environment "${ENVIRONMENT}"

run_cmd kubectl apply -k "${ROOT_DIR}/infra/k8s/overlays/${ENVIRONMENT}"

if [[ "${WITH_RUNNER}" == "1" ]]; then
  run_cmd kubectl apply -k "${ROOT_DIR}/infra/k8s/runner/overlays/${ENVIRONMENT}"
fi

if [[ "${DRY_RUN}" != "1" ]]; then
  kubectl get pods -n "${NAMESPACE}"
fi
