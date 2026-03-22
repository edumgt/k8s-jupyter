#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUNDLE_DIR="${BUNDLE_DIR:-/opt/k8s-data-platform/offline-bundle}"
MANIFEST_DIR_REPO="${ROOT_DIR}/offline/manifests"
MANIFEST_DIR_BUNDLE="${BUNDLE_DIR}/k8s/manifests"
EXIT_CODE=0

log() {
  printf '[%s] %s\n' "$(basename "$0")" "$*"
}

warn() {
  printf '[%s] WARNING: %s\n' "$(basename "$0")" "$*" >&2
  EXIT_CODE=1
}

check_file() {
  local path="$1"
  local label="$2"
  if [[ -f "${path}" ]]; then
    log "OK: ${label} -> ${path}"
  else
    warn "Missing ${label}: ${path}"
  fi
}

check_image_ref() {
  local ref="$1"
  if sudo ctr -n k8s.io images ls -q | grep -Fqx "${ref}"; then
    log "OK: image present in containerd -> ${ref}"
  else
    warn "Missing image in containerd: ${ref}"
  fi
}

check_k8s() {
  if [[ ! -f /etc/kubernetes/admin.conf ]]; then
    warn "Missing /etc/kubernetes/admin.conf"
    return
  fi

  if ! sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes >/dev/null 2>&1; then
    warn "kubectl cannot reach the cluster with /etc/kubernetes/admin.conf"
    return
  fi

  log "Kubernetes API reachable"

  if sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A --no-headers 2>/dev/null | awk '$4 ~ /ImagePullBackOff|ErrImagePull/ {found=1} END{exit found?0:1}'; then
    warn "Found pods with ImagePullBackOff/ErrImagePull"
  else
    log "No current ImagePullBackOff/ErrImagePull pods detected"
  fi

  if sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get svc -n ingress-nginx ingress-nginx-controller >/dev/null 2>&1; then
    local ingress_ip
    ingress_ip="$(
      sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get svc -n ingress-nginx ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
    )"
    if [[ -n "${ingress_ip}" ]]; then
      log "Ingress LoadBalancer IP assigned -> ${ingress_ip}"
    else
      warn "Ingress LoadBalancer IP is still pending"
    fi
  else
    warn "ingress-nginx-controller service not found"
  fi
}

main() {
  check_file "${MANIFEST_DIR_REPO}/kube-flannel.yml" "repo flannel manifest"
  check_file "${MANIFEST_DIR_REPO}/ingress-nginx.yaml" "repo ingress manifest"
  check_file "${MANIFEST_DIR_REPO}/metallb-native.yaml" "repo MetalLB manifest"

  if [[ -d "${BUNDLE_DIR}" ]]; then
    check_file "${MANIFEST_DIR_BUNDLE}/kube-flannel.yml" "bundle flannel manifest"
    check_file "${MANIFEST_DIR_BUNDLE}/ingress-nginx.yaml" "bundle ingress manifest"
    check_file "${MANIFEST_DIR_BUNDLE}/metallb-native.yaml" "bundle MetalLB manifest"
  else
    warn "Offline bundle directory not found: ${BUNDLE_DIR}"
  fi

  if command -v ctr >/dev/null 2>&1; then
    check_image_ref "docker.io/edumgt/platform-flannel:v0.28.1"
    check_image_ref "docker.io/edumgt/platform-flannel-cni-plugin:v1.9.0-flannel1"
    check_image_ref "docker.io/edumgt/platform-metallb-controller:v0.14.8"
    check_image_ref "docker.io/edumgt/platform-metallb-speaker:v0.14.8"
    check_image_ref "docker.io/edumgt/platform-ingress-nginx-controller:v1.12.2"
    check_image_ref "docker.io/edumgt/platform-ingress-nginx-kube-webhook-certgen:v1.5.3"
    check_image_ref "docker.io/edumgt/platform-gitlab-ce:17.10.0-ce.0"
    check_image_ref "docker.io/edumgt/platform-nexus3:3.90.1-alpine"
    check_image_ref "docker.io/edumgt/k8s-data-platform-backend:latest"
    check_image_ref "docker.io/edumgt/k8s-data-platform-frontend:latest"
    check_image_ref "docker.io/edumgt/k8s-data-platform-jupyter:latest"
    check_image_ref "docker.io/edumgt/k8s-data-platform-airflow:latest"
  else
    warn "ctr command not found; cannot verify containerd image cache"
  fi

  check_k8s
  exit "${EXIT_CODE}"
}

main "$@"
