#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-data-platform-dev}"
NEXUS_URL="${NEXUS_URL:-http://127.0.0.1:30091}"
TARGET_PASSWORD="${TARGET_PASSWORD:-nexus123!}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/dist/nexus-prime}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash scripts/setup_nexus_offline.sh [options]

Options:
  --namespace <name>       Kubernetes namespace where Nexus is deployed.
  --nexus-url <url>        Reachable Nexus base URL.
  --target-password <pw>   Password to set for the admin account after bootstrap.
  --out-dir <path>         Output directory for warmed Python/npm caches.
  --dry-run                Print commands without executing them.
  -h, --help               Show this help.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

run_subcommand() {
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
    --namespace)
      [[ $# -ge 2 ]] || die "--namespace requires a value"
      NAMESPACE="$2"
      shift 2
      ;;
    --nexus-url)
      [[ $# -ge 2 ]] || die "--nexus-url requires a value"
      NEXUS_URL="$2"
      shift 2
      ;;
    --target-password)
      [[ $# -ge 2 ]] || die "--target-password requires a value"
      TARGET_PASSWORD="$2"
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

run_subcommand bash "${ROOT_DIR}/scripts/bootstrap_nexus_repos.sh" \
  --namespace "${NAMESPACE}" \
  --nexus-url "${NEXUS_URL}" \
  --target-password "${TARGET_PASSWORD}" \
  $( [[ "${DRY_RUN}" == "1" ]] && printf '%s' '--dry-run' )

run_subcommand bash "${ROOT_DIR}/scripts/prime_nexus_caches.sh" \
  --nexus-url "${NEXUS_URL}" \
  --out-dir "${OUT_DIR}" \
  $( [[ "${DRY_RUN}" == "1" ]] && printf '%s' '--dry-run' )
