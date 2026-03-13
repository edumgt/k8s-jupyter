#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="dev"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || { printf '--env requires a value\n' >&2; exit 1; }
      ENVIRONMENT="$2"
      shift 2
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

case "${ENVIRONMENT}" in
  dev|prod) ;;
  *)
    printf 'Unsupported environment: %s\n' "${ENVIRONMENT}" >&2
    exit 1
    ;;
esac

NAMESPACE="data-platform-${ENVIRONMENT}"

systemctl is-active --quiet k3s
kubectl get nodes >/dev/null 2>&1 || sudo k3s kubectl get nodes >/dev/null
kubectl get pods -n "${NAMESPACE}" >/dev/null 2>&1 || sudo k3s kubectl get pods -n "${NAMESPACE}" >/dev/null
exit 0
