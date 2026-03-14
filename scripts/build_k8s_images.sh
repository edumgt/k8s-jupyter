#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="${TMP_DIR:-${ROOT_DIR}/.tmp-k8s-images}"
DRY_RUN=0
PUSH_IMAGES=0
LOAD_K3S=1
INCLUDE_SUPPORT_IMAGES=1
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-edumgt}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

usage() {
  cat <<'EOF'
Usage: bash scripts/build_k8s_images.sh [options]

Options:
  --namespace <name>      Docker Hub namespace. Defaults to edumgt.
  --tag <tag>             Tag to apply to platform app images. Defaults to latest.
  --push                  Push mirrored support images and built app images with the current docker login.
  --skip-k3s-import       Skip importing the saved archives into the local k3s containerd cache.
  --skip-support-images   Skip mirroring the upstream base/runtime/CI images into the namespace.
  --dry-run               Print commands without executing them.
  -h, --help              Show this help.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
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

import_to_k3s() {
  local archive="$1"

  if [[ "${LOAD_K3S}" != "1" ]]; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    run_cmd sudo k3s ctr images import "${archive}"
    return 0
  fi

  run_cmd k3s ctr images import "${archive}"
}

sanitize_archive_name() {
  printf '%s' "$1" | tr '/:' '-'
}

save_image_archive() {
  local image="$1"
  local archive="${TMP_DIR}/$(sanitize_archive_name "${image}").tar"

  run_cmd docker save -o "${archive}" "${image}"
  import_to_k3s "${archive}"
}

mirror_support_image() {
  local source_image="$1"
  local target_image="$2"

  run_cmd docker pull "${source_image}"
  run_cmd docker tag "${source_image}" "${target_image}"
  if [[ "${PUSH_IMAGES}" == "1" ]]; then
    run_cmd docker push "${target_image}"
  fi
  save_image_archive "${target_image}"
}

build_platform_image() {
  local name="$1"
  local context="$2"
  local image="$3"
  local frontend_api_url="$4"

  local build_args=(docker build -t "${image}")
  if [[ -n "${frontend_api_url}" ]]; then
    build_args+=(--build-arg "VITE_API_BASE_URL=${frontend_api_url}")
  fi
  build_args+=("${ROOT_DIR}/${context}")

  run_cmd "${build_args[@]}"
  if [[ "${PUSH_IMAGES}" == "1" ]]; then
    run_cmd docker push "${image}"
  fi
  save_image_archive "${image}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      [[ $# -ge 2 ]] || die "--namespace requires a value"
      IMAGE_NAMESPACE="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || die "--tag requires a value"
      IMAGE_TAG="$2"
      shift 2
      ;;
    --push)
      PUSH_IMAGES=1
      shift
      ;;
    --skip-k3s-import)
      LOAD_K3S=0
      shift
      ;;
    --skip-support-images)
      INCLUDE_SUPPORT_IMAGES=0
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

require_command docker
if [[ "${LOAD_K3S}" == "1" ]]; then
  require_command k3s
fi

run_cmd mkdir -p "${TMP_DIR}"

SUPPORT_IMAGES=(
  "python:3.12-slim|docker.io/${IMAGE_NAMESPACE}/platform-python:3.12-slim"
  "python:3.12|docker.io/${IMAGE_NAMESPACE}/platform-python:3.12"
  "node:22.22.0-bookworm-slim|docker.io/${IMAGE_NAMESPACE}/platform-node:22.22.0-bookworm-slim"
  "nginx:1.27-alpine|docker.io/${IMAGE_NAMESPACE}/platform-nginx:1.27-alpine"
  "apache/airflow:2.10.5-python3.12|docker.io/${IMAGE_NAMESPACE}/platform-airflow-base:2.10.5-python3.12"
  "mongo:7.0|docker.io/${IMAGE_NAMESPACE}/platform-mongodb:7.0"
  "redis:7-alpine|docker.io/${IMAGE_NAMESPACE}/platform-redis:7-alpine"
  "gitlab/gitlab-ce:17.10.0-ce.0|docker.io/${IMAGE_NAMESPACE}/platform-gitlab-ce:17.10.0-ce.0"
  "gitlab/gitlab-runner:alpine-v17.10.0|docker.io/${IMAGE_NAMESPACE}/platform-gitlab-runner:alpine-v17.10.0"
  "gcr.io/kaniko-project/executor:v1.23.2-debug|docker.io/${IMAGE_NAMESPACE}/platform-kaniko-executor:v1.23.2-debug"
  "bitnami/kubectl:latest|docker.io/${IMAGE_NAMESPACE}/platform-kubectl:latest"
  "bash:5.2|docker.io/${IMAGE_NAMESPACE}/platform-bash:5.2"
  "alpine:3.20|docker.io/${IMAGE_NAMESPACE}/platform-alpine:3.20"
  "busybox:1.36|docker.io/${IMAGE_NAMESPACE}/platform-busybox:1.36"
)

PLATFORM_IMAGES=(
  "backend|apps/backend|docker.io/${IMAGE_NAMESPACE}/k8s-data-platform-backend:${IMAGE_TAG}|"
  "frontend|apps/frontend|docker.io/${IMAGE_NAMESPACE}/k8s-data-platform-frontend:${IMAGE_TAG}|http://localhost:30081"
  "airflow|apps/airflow|docker.io/${IMAGE_NAMESPACE}/k8s-data-platform-airflow:${IMAGE_TAG}|"
  "jupyter|apps/jupyter|docker.io/${IMAGE_NAMESPACE}/k8s-data-platform-jupyter:${IMAGE_TAG}|"
)

if [[ "${INCLUDE_SUPPORT_IMAGES}" == "1" ]]; then
  for item in "${SUPPORT_IMAGES[@]}"; do
    IFS='|' read -r source_image target_image <<<"${item}"
    mirror_support_image "${source_image}" "${target_image}"
  done
fi

for item in "${PLATFORM_IMAGES[@]}"; do
  IFS='|' read -r name context image frontend_api_url <<<"${item}"
  build_platform_image "${name}" "${context}" "${image}" "${frontend_api_url}"
done
