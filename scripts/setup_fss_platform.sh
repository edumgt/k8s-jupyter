#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENVIRONMENT="${ENVIRONMENT:-dev}"
SETUP_MODERN_STACK=1
METALLB_RANGE="${METALLB_RANGE:-}"
INGRESS_LB_IP="${INGRESS_LB_IP:-}"
HEADLAMP_HOST="${HEADLAMP_HOST:-headlamp.platform.local}"
WAIT_TIMEOUT_SEC="${WAIT_TIMEOUT_SEC:-420}"

HARBOR_SERVER="${HARBOR_SERVER:-}"
HARBOR_USERNAME="${HARBOR_USERNAME:-}"
HARBOR_PASSWORD="${HARBOR_PASSWORD:-}"
HARBOR_SECRET_NAME="${HARBOR_SECRET_NAME:-harbor-pull}"
PATCH_DEFAULT_SA=1

SKIP_MODERN_STACK=0
SKIP_HARBOR_SECRET=0

usage() {
  cat <<'EOF'
Usage: bash scripts/setup_fss_platform.sh [options]

Applies FSS requirements:
  - namespace set: app/dis/infra/sample/unitest
  - optional modern addons: ingress-nginx + MetalLB + metrics-server + Headlamp
  - optional Harbor pull secret bootstrap for app/dis/infra
  - FSS overlay apply (infra/k8s/fss/overlays/<env>)

Options:
  --env dev|prod             Overlay environment (default: dev)
  --metallb-range RANGE      MetalLB pool range (required unless --skip-modern-stack)
  --ingress-lb-ip IP         Optional fixed ingress LB IP
  --headlamp-host HOST       Headlamp ingress host (default: headlamp.platform.local)
  --wait-timeout-sec N       Wait timeout for addon install

  --harbor-server HOSTPORT   Harbor registry endpoint (e.g. 192.168.56.72:80)
  --harbor-username USER     Harbor robot username (quote if includes $)
  --harbor-password PASS     Harbor robot password
  --harbor-secret-name NAME  K8s docker-registry secret name (default: harbor-pull)
  --skip-harbor-secret       Skip Harbor secret creation
  --skip-default-sa-patch    Do not patch default SA imagePullSecrets

  --skip-modern-stack        Skip ingress/metallb/metrics/headlamp install
  -h, --help                 Show this help

Examples:
  bash scripts/setup_fss_platform.sh \
    --env dev \
    --metallb-range 192.168.56.77-192.168.56.77 \
    --ingress-lb-ip 192.168.56.77 \
    --harbor-server 192.168.56.72:80 \
    --harbor-username 'robot$dis' \
    --harbor-password '<password>'
EOF
}

log() {
  printf '[%s] %s\n' "$(basename "$0")" "$*"
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

run_kubectl() {
  if [[ -n "${KUBECONFIG:-}" ]]; then
    kubectl "$@"
    return
  fi
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    KUBECONFIG=/etc/kubernetes/admin.conf kubectl "$@"
    return
  fi
  kubectl "$@"
}

ensure_harbor_secret() {
  local namespace="$1"
  run_kubectl -n "${namespace}" create secret docker-registry "${HARBOR_SECRET_NAME}" \
    --docker-server="${HARBOR_SERVER}" \
    --docker-username="${HARBOR_USERNAME}" \
    --docker-password="${HARBOR_PASSWORD}" \
    --dry-run=client -o yaml | run_kubectl apply -f -
}

patch_default_sa_for_pull_secret() {
  local namespace="$1"
  run_kubectl -n "${namespace}" patch serviceaccount default --type merge \
    -p "{\"imagePullSecrets\":[{\"name\":\"${HARBOR_SECRET_NAME}\"}]}" >/dev/null
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || die "--env requires a value"
      ENVIRONMENT="$2"
      shift 2
      ;;
    --metallb-range)
      [[ $# -ge 2 ]] || die "--metallb-range requires a value"
      METALLB_RANGE="$2"
      shift 2
      ;;
    --ingress-lb-ip)
      [[ $# -ge 2 ]] || die "--ingress-lb-ip requires a value"
      INGRESS_LB_IP="$2"
      shift 2
      ;;
    --headlamp-host)
      [[ $# -ge 2 ]] || die "--headlamp-host requires a value"
      HEADLAMP_HOST="$2"
      shift 2
      ;;
    --wait-timeout-sec)
      [[ $# -ge 2 ]] || die "--wait-timeout-sec requires a value"
      WAIT_TIMEOUT_SEC="$2"
      shift 2
      ;;
    --harbor-server)
      [[ $# -ge 2 ]] || die "--harbor-server requires a value"
      HARBOR_SERVER="$2"
      shift 2
      ;;
    --harbor-username)
      [[ $# -ge 2 ]] || die "--harbor-username requires a value"
      HARBOR_USERNAME="$2"
      shift 2
      ;;
    --harbor-password)
      [[ $# -ge 2 ]] || die "--harbor-password requires a value"
      HARBOR_PASSWORD="$2"
      shift 2
      ;;
    --harbor-secret-name)
      [[ $# -ge 2 ]] || die "--harbor-secret-name requires a value"
      HARBOR_SECRET_NAME="$2"
      shift 2
      ;;
    --skip-harbor-secret)
      SKIP_HARBOR_SECRET=1
      shift
      ;;
    --skip-default-sa-patch)
      PATCH_DEFAULT_SA=0
      shift
      ;;
    --skip-modern-stack)
      SKIP_MODERN_STACK=1
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
require_command bash

case "${ENVIRONMENT}" in
  dev|prod) ;;
  *) die "--env must be dev or prod" ;;
esac

if [[ "${SKIP_MODERN_STACK}" -eq 0 ]]; then
  [[ -n "${METALLB_RANGE}" ]] || die "--metallb-range is required unless --skip-modern-stack is used."
  modern_args=(
    --metallb-range "${METALLB_RANGE}"
    --headlamp-ingress-host "${HEADLAMP_HOST}"
    --wait-timeout-sec "${WAIT_TIMEOUT_SEC}"
  )
  if [[ -n "${INGRESS_LB_IP}" ]]; then
    modern_args+=(--ingress-lb-ip "${INGRESS_LB_IP}")
  fi
  log "Installing ingress/metallb/metrics/headlamp stack"
  bash "${SCRIPT_DIR}/setup_k8s_modern_stack.sh" "${modern_args[@]}"
else
  log "Skipping modern stack setup (--skip-modern-stack)"
fi

log "Applying FSS overlay: infra/k8s/fss/overlays/${ENVIRONMENT}"
run_kubectl apply -k "${ROOT_DIR}/infra/k8s/fss/overlays/${ENVIRONMENT}"

if [[ "${SKIP_HARBOR_SECRET}" -eq 0 ]]; then
  [[ -n "${HARBOR_SERVER}" ]] || die "--harbor-server is required unless --skip-harbor-secret"
  [[ -n "${HARBOR_USERNAME}" ]] || die "--harbor-username is required unless --skip-harbor-secret"
  [[ -n "${HARBOR_PASSWORD}" ]] || die "--harbor-password is required unless --skip-harbor-secret"

  for ns in app dis infra; do
    log "Ensuring harbor pull secret in namespace ${ns}"
    ensure_harbor_secret "${ns}"
    if [[ "${PATCH_DEFAULT_SA}" -eq 1 ]]; then
      log "Patching default serviceaccount imagePullSecrets in ${ns}"
      patch_default_sa_for_pull_secret "${ns}"
    fi
  done
else
  log "Skipping Harbor secret setup (--skip-harbor-secret)"
fi

log "Namespace summary"
run_kubectl get namespace app dis infra sample unitest

log "Metrics APIService status"
run_kubectl get apiservice v1beta1.metrics.k8s.io -o wide

log "FSS platform setup completed."

