#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/kubernetes_runtime.sh
source "${SCRIPT_DIR}/lib/kubernetes_runtime.sh"

ENVIRONMENT="dev"
TARGET_HOST="${TARGET_HOST:-127.0.0.1}"
HTTP_TIMEOUT=5
SKIP_HTTP=0

usage() {
  cat <<'EOF'
Usage: bash scripts/verify.sh [options]

Options:
  --env <dev|prod>     Verify the selected environment. Defaults to dev.
  --host <addr>        HTTP target host for NodePort checks. Defaults to 127.0.0.1.
  --http-timeout <n>   curl timeout in seconds. Defaults to 5.
  --skip-http          Skip NodePort endpoint checks.
  -h, --help           Show this help.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || die "--env requires a value"
      ENVIRONMENT="$2"
      shift 2
      ;;
    --host)
      [[ $# -ge 2 ]] || die "--host requires a value"
      TARGET_HOST="$2"
      shift 2
      ;;
    --http-timeout)
      [[ $# -ge 2 ]] || die "--http-timeout requires a value"
      HTTP_TIMEOUT="$2"
      shift 2
      ;;
    --skip-http)
      SKIP_HTTP=1
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

case "${ENVIRONMENT}" in
  dev|prod) ;;
  *)
    die "Unsupported environment: ${ENVIRONMENT}"
    ;;
esac

NAMESPACE="data-platform-${ENVIRONMENT}"

printf '[verify] checking container runtime services\n'
kubernetes_services_ready

printf '[verify] checking cluster node readiness\n'
run_kubectl get nodes --no-headers | grep -q ' Ready'

printf '[verify] checking platform pods in %s\n' "${NAMESPACE}"
run_kubectl get pods -n "${NAMESPACE}" --no-headers

printf '[verify] checking platform services in %s\n' "${NAMESPACE}"
run_kubectl get svc -n "${NAMESPACE}" --no-headers

printf '[verify] checking persistent volumes in %s\n' "${NAMESPACE}"
run_kubectl get pvc -n "${NAMESPACE}" --no-headers >/dev/null

if [[ "${SKIP_HTTP}" == "1" ]]; then
  exit 0
fi

command -v curl >/dev/null 2>&1 || die "Required command not found: curl"

check_http() {
  local name="$1"
  local port="$2"
  local url="http://${TARGET_HOST}:${port}"

  printf '[verify] %s -> %s\n' "${name}" "${url}"
  curl --silent --show-error --fail --max-time "${HTTP_TIMEOUT}" --output /dev/null "${url}"
}

check_http "frontend" 30080
check_http "backend" 30081
check_http "jupyter" 30088
check_http "gitlab" 30089
check_http "nexus" 30091
check_http "harbor" 30092
check_http "code-server" 30100
