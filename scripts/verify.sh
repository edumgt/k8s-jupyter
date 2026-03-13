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

echo '[1] k3s service'
systemctl --no-pager --full status k3s | sed -n '1,60p'

echo '[2] Cluster nodes'
kubectl get nodes || sudo k3s kubectl get nodes

echo '[3] Platform pods'
kubectl get pods -n "${NAMESPACE}" || sudo k3s kubectl get pods -n "${NAMESPACE}"

echo '[4] Services'
kubectl get svc -n "${NAMESPACE}" || sudo k3s kubectl get svc -n "${NAMESPACE}"

echo '[5] Persistent volumes'
kubectl get pvc -n "${NAMESPACE}" || sudo k3s kubectl get pvc -n "${NAMESPACE}"
