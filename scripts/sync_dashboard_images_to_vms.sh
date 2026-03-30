#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/image_registry.sh
source "${SCRIPT_DIR}/lib/image_registry.sh"

SYNC_SCRIPT="${ROOT_DIR}/scripts/sync_docker_image_to_vms.sh"

SOURCE_DASHBOARD_IMAGE="${SOURCE_DASHBOARD_IMAGE:-kubernetesui/dashboard:v2.7.0}"
SOURCE_SCRAPER_IMAGE="${SOURCE_SCRAPER_IMAGE:-kubernetesui/metrics-scraper:v1.0.8}"
TARGET_DASHBOARD_IMAGE="${TARGET_DASHBOARD_IMAGE:-$(platform_support_image platform-kubernetes-dashboard v2.7.0)}"
TARGET_SCRAPER_IMAGE="${TARGET_SCRAPER_IMAGE:-$(platform_support_image platform-kubernetes-dashboard-metrics-scraper v1.0.8)}"
ALLOW_UPSTREAM_PULL=0

SYNC_ARGS=()

usage() {
  cat <<'EOF'
Usage: bash scripts/sync_dashboard_images_to_vms.sh [options]

Retags Kubernetes Dashboard images to the platform registry naming scheme and
copies them from this WSL host into VM Docker/containerd caches.

By default, this script does NOT pull from upstream registries. Prepare source
images locally first (for example via scripts/build_k8s_images.sh), or pass
--allow-upstream-pull explicitly.

Options:
  --source-dashboard-image REF   Source dashboard image (default: kubernetesui/dashboard:v2.7.0)
  --source-scraper-image REF     Source metrics scraper image (default: kubernetesui/metrics-scraper:v1.0.8)
  --target-dashboard-image REF   Target image tag to preload on VMs.
  --target-scraper-image REF     Target image tag to preload on VMs.
  --allow-upstream-pull          Pull missing source images from upstream registry.

  The options below are forwarded to scripts/sync_docker_image_to_vms.sh:
  --vars-file PATH
  --control-plane-ip IP
  --worker1-ip IP
  --worker2-ip IP
  --worker3-ip IP
  --remote-archive PATH
  --ssh-user USER
  --ssh-password PASS
  --ssh-key-path PATH
  --ssh-port PORT
  --skip-containerd-import

  -h, --help                     Show this help.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

ensure_source_image() {
  local source_ref="$1"
  if docker image inspect "${source_ref}" >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${ALLOW_UPSTREAM_PULL}" == "1" ]]; then
    docker pull "${source_ref}"
    return 0
  fi

  die "Source image missing locally: ${source_ref}. Prepare it first or use --allow-upstream-pull."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dashboard-image)
      [[ $# -ge 2 ]] || die "--source-dashboard-image requires a value"
      SOURCE_DASHBOARD_IMAGE="$2"
      shift 2
      ;;
    --source-scraper-image)
      [[ $# -ge 2 ]] || die "--source-scraper-image requires a value"
      SOURCE_SCRAPER_IMAGE="$2"
      shift 2
      ;;
    --target-dashboard-image)
      [[ $# -ge 2 ]] || die "--target-dashboard-image requires a value"
      TARGET_DASHBOARD_IMAGE="$2"
      shift 2
      ;;
    --target-scraper-image)
      [[ $# -ge 2 ]] || die "--target-scraper-image requires a value"
      TARGET_SCRAPER_IMAGE="$2"
      shift 2
      ;;
    --allow-upstream-pull)
      ALLOW_UPSTREAM_PULL=1
      shift
      ;;
    --vars-file|--control-plane-ip|--worker1-ip|--worker2-ip|--worker3-ip|--remote-archive|--ssh-user|--ssh-password|--ssh-key-path|--ssh-port)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      SYNC_ARGS+=("$1" "$2")
      shift 2
      ;;
    --skip-containerd-import)
      SYNC_ARGS+=("$1")
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
[[ -x "${SYNC_SCRIPT}" ]] || die "Sync script not executable: ${SYNC_SCRIPT}"

ensure_source_image "${SOURCE_DASHBOARD_IMAGE}"
ensure_source_image "${SOURCE_SCRAPER_IMAGE}"

docker tag "${SOURCE_DASHBOARD_IMAGE}" "${TARGET_DASHBOARD_IMAGE}"
docker tag "${SOURCE_SCRAPER_IMAGE}" "${TARGET_SCRAPER_IMAGE}"

bash "${SYNC_SCRIPT}" \
  --image-ref "${TARGET_DASHBOARD_IMAGE}" \
  --archive-path /tmp/platform-kubernetes-dashboard-v2.7.0.tar \
  --remote-archive /tmp/platform-kubernetes-dashboard-v2.7.0.tar \
  "${SYNC_ARGS[@]}"

bash "${SYNC_SCRIPT}" \
  --image-ref "${TARGET_SCRAPER_IMAGE}" \
  --archive-path /tmp/platform-kubernetes-dashboard-metrics-scraper-v1.0.8.tar \
  --remote-archive /tmp/platform-kubernetes-dashboard-metrics-scraper-v1.0.8.tar \
  "${SYNC_ARGS[@]}"

printf '[%s] Synced dashboard images:\n' "$(basename "$0")"
printf '  %s\n' "${TARGET_DASHBOARD_IMAGE}"
printf '  %s\n' "${TARGET_SCRAPER_IMAGE}"
