#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_MANIFEST_DIR_DEFAULT="${ROOT_DIR}/offline/manifests"
REMOTE_BUNDLE_MANIFEST_DIR="/opt/k8s-data-platform/offline-bundle/k8s/manifests"

DASHBOARD_NAMESPACE="kubernetes-dashboard"
DASHBOARD_MANIFEST="${DASHBOARD_MANIFEST:-}"
INGRESS_NAME="${INGRESS_NAME:-kubernetes-dashboard-ingress}"
INGRESS_CLASS_NAME="${INGRESS_CLASS_NAME:-nginx}"
INGRESS_HOST="${INGRESS_HOST:-dashboard.platform.local}"
TOKEN_DURATION="${TOKEN_DURATION:-24h}"

SKIP_INGRESS=0
SKIP_ADMIN_BINDING=0
PRINT_TOKEN=0

usage() {
  cat <<'EOF'
Usage: bash scripts/setup_kubernetes_dashboard.sh [options]

Installs Kubernetes Dashboard from the air-gap manifest, then optionally
creates ingress and an admin ServiceAccount binding.

Options:
  --manifest PATH             Dashboard manifest path.
                              Defaults:
                                1) /opt/k8s-data-platform/offline-bundle/k8s/manifests/kubernetes-dashboard.yaml
                                2) ./offline/manifests/kubernetes-dashboard.yaml
  --ingress-host HOST         Dashboard ingress host (default: dashboard.platform.local)
  --ingress-name NAME         Ingress resource name (default: kubernetes-dashboard-ingress)
  --ingress-class NAME        IngressClass name (default: nginx)
  --token-duration DURATION   Token duration for --print-token (default: 24h)
  --skip-ingress              Skip ingress creation.
  --skip-admin-binding        Skip cluster-admin ServiceAccount binding.
  --print-token               Print dashboard-admin login token after setup.
  -h, --help                  Show this help.
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

resolve_manifest_path() {
  if [[ -n "${DASHBOARD_MANIFEST}" ]]; then
    printf '%s' "${DASHBOARD_MANIFEST}"
    return 0
  fi

  if [[ -f "${REMOTE_BUNDLE_MANIFEST_DIR}/kubernetes-dashboard.yaml" ]]; then
    printf '%s' "${REMOTE_BUNDLE_MANIFEST_DIR}/kubernetes-dashboard.yaml"
    return 0
  fi

  printf '%s' "${LOCAL_MANIFEST_DIR_DEFAULT}/kubernetes-dashboard.yaml"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      [[ $# -ge 2 ]] || die "--manifest requires a value"
      DASHBOARD_MANIFEST="$2"
      shift 2
      ;;
    --ingress-host)
      [[ $# -ge 2 ]] || die "--ingress-host requires a value"
      INGRESS_HOST="$2"
      shift 2
      ;;
    --ingress-name)
      [[ $# -ge 2 ]] || die "--ingress-name requires a value"
      INGRESS_NAME="$2"
      shift 2
      ;;
    --ingress-class)
      [[ $# -ge 2 ]] || die "--ingress-class requires a value"
      INGRESS_CLASS_NAME="$2"
      shift 2
      ;;
    --token-duration)
      [[ $# -ge 2 ]] || die "--token-duration requires a value"
      TOKEN_DURATION="$2"
      shift 2
      ;;
    --skip-ingress)
      SKIP_INGRESS=1
      shift
      ;;
    --skip-admin-binding)
      SKIP_ADMIN_BINDING=1
      shift
      ;;
    --print-token)
      PRINT_TOKEN=1
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

MANIFEST_PATH="$(resolve_manifest_path)"
[[ -f "${MANIFEST_PATH}" ]] || die "Dashboard manifest not found: ${MANIFEST_PATH}"

log "Applying dashboard manifest: ${MANIFEST_PATH}"
run_kubectl apply -f "${MANIFEST_PATH}"

log "Waiting for dashboard rollouts"
run_kubectl -n "${DASHBOARD_NAMESPACE}" rollout status deploy/kubernetes-dashboard --timeout=300s
run_kubectl -n "${DASHBOARD_NAMESPACE}" rollout status deploy/dashboard-metrics-scraper --timeout=300s

if [[ "${SKIP_INGRESS}" == "0" ]]; then
  log "Creating/updating dashboard ingress (${INGRESS_HOST})"
  cat <<EOF_ING | run_kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${INGRESS_NAME}
  namespace: ${DASHBOARD_NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/service-upstream: "true"
spec:
  ingressClassName: ${INGRESS_CLASS_NAME}
  rules:
    - host: ${INGRESS_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kubernetes-dashboard
                port:
                  number: 443
EOF_ING
fi

if [[ "${SKIP_ADMIN_BINDING}" == "0" ]]; then
  log "Creating/updating dashboard-admin ServiceAccount + cluster-admin binding"
  run_kubectl -n "${DASHBOARD_NAMESPACE}" create serviceaccount dashboard-admin --dry-run=client -o yaml | run_kubectl apply -f -
  run_kubectl create clusterrolebinding dashboard-admin \
    --clusterrole=cluster-admin \
    --serviceaccount="${DASHBOARD_NAMESPACE}:dashboard-admin" \
    --dry-run=client -o yaml | run_kubectl apply -f -
fi

ingress_ip="$(
  run_kubectl -n ingress-nginx get svc ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
)"

printf '\n'
log "Dashboard URL: http://${INGRESS_HOST}/"
if [[ -n "${ingress_ip}" ]]; then
  log "hosts entry: ${ingress_ip} ${INGRESS_HOST}"
fi
log "Token command: kubectl -n ${DASHBOARD_NAMESPACE} create token dashboard-admin --duration=${TOKEN_DURATION}"

if [[ "${PRINT_TOKEN}" == "1" && "${SKIP_ADMIN_BINDING}" == "0" ]]; then
  printf '\n'
  run_kubectl -n "${DASHBOARD_NAMESPACE}" create token dashboard-admin --duration="${TOKEN_DURATION}"
fi
