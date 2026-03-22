#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKER_VARS="${PACKER_VARS:-${ROOT_DIR}/packer/variables.vmware.auto.pkrvars.hcl}"
BUNDLE_DIR="${BUNDLE_DIR:-${ROOT_DIR}/dist/offline-bundle}"
REMOTE_BUNDLE_DIR="${REMOTE_BUNDLE_DIR:-/opt/k8s-data-platform/offline-bundle}"
CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-}"
SSH_USER="${SSH_USER:-}"
SSH_PASSWORD="${SSH_PASSWORD:-}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SSH_PORT="${SSH_PORT:-22}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-edumgt}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
SKIP_BUILD=0
APPLY_MANIFESTS=0
WITH_RUNNER=0

usage() {
  cat <<'EOF'
Usage: bash scripts/preload_offline_bundle_to_vm.sh [options]

Builds or reuses the offline bundle on the local machine, copies it to the
target VM, then imports image archives into Docker/containerd on the VM.

Options:
  --control-plane-ip IP       Target VM IP (required unless env is set).
  --vars-file PATH            Packer vars file for default SSH credentials.
  --bundle-dir PATH           Local offline bundle directory.
  --remote-bundle-dir PATH    Remote bundle directory on the VM.
  --ssh-user USER             SSH username override.
  --ssh-password PASS         SSH password override.
  --ssh-key-path PATH         SSH private key override.
  --ssh-port PORT             SSH port override (default: 22).
  --env dev|prod              Overlay env for optional --apply.
  --namespace NAME            Image namespace for bundle build (default: edumgt).
  --tag TAG                   App image tag for bundle build (default: latest).
  --skip-build                Reuse an existing local offline bundle.
  --apply                     Apply bundled manifests after import.
  --with-runner               Apply runner overlay too (requires --apply).
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

trim() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

read_optional_packer_var() {
  local key="$1"
  local raw_value

  raw_value="$(
    awk -F '=' -v key="${key}" '
      $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
        sub(/^[^=]*=/, "", $0)
        print $0
        exit
      }
    ' "${PACKER_VARS}"
  )"
  raw_value="$(trim "${raw_value}")"
  raw_value="${raw_value#\"}"
  raw_value="${raw_value%\"}"
  printf '%s' "${raw_value}"
}

ssh_opts=()
scp_opts=()

build_ssh_opts() {
  ssh_opts=(
    -p "${SSH_PORT}"
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=8
  )
  scp_opts=(
    -P "${SSH_PORT}"
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=8
  )

  if [[ -n "${SSH_KEY_PATH}" ]]; then
    ssh_opts+=(-i "${SSH_KEY_PATH}")
    scp_opts+=(-i "${SSH_KEY_PATH}")
  fi
}

ssh_run() {
  local host="$1"
  shift

  if [[ -n "${SSH_PASSWORD}" ]]; then
    SSHPASS="${SSH_PASSWORD}" sshpass -e ssh "${ssh_opts[@]}" "${SSH_USER}@${host}" "$@"
    return
  fi

  ssh "${ssh_opts[@]}" "${SSH_USER}@${host}" "$@"
}

scp_copy_dir() {
  local src="$1"
  local host="$2"
  local dst="$3"

  if [[ -n "${SSH_PASSWORD}" ]]; then
    SSHPASS="${SSH_PASSWORD}" sshpass -e scp "${scp_opts[@]}" -r "${src}" "${SSH_USER}@${host}:${dst}"
    return
  fi

  scp "${scp_opts[@]}" -r "${src}" "${SSH_USER}@${host}:${dst}"
}

remote_sudo() {
  local host="$1"
  local command="$2"

  if [[ -n "${SSH_PASSWORD}" ]]; then
    ssh_run "${host}" "printf '%s\n' '${SSH_PASSWORD}' | sudo -S -p '' bash -lc $(printf '%q' "${command}")"
    return
  fi

  ssh_run "${host}" "sudo bash -lc $(printf '%q' "${command}")"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --control-plane-ip)
      [[ $# -ge 2 ]] || die "--control-plane-ip requires a value"
      CONTROL_PLANE_IP="$2"
      shift 2
      ;;
    --vars-file)
      [[ $# -ge 2 ]] || die "--vars-file requires a value"
      PACKER_VARS="$2"
      shift 2
      ;;
    --bundle-dir)
      [[ $# -ge 2 ]] || die "--bundle-dir requires a value"
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --remote-bundle-dir)
      [[ $# -ge 2 ]] || die "--remote-bundle-dir requires a value"
      REMOTE_BUNDLE_DIR="$2"
      shift 2
      ;;
    --ssh-user)
      [[ $# -ge 2 ]] || die "--ssh-user requires a value"
      SSH_USER="$2"
      shift 2
      ;;
    --ssh-password)
      [[ $# -ge 2 ]] || die "--ssh-password requires a value"
      SSH_PASSWORD="$2"
      shift 2
      ;;
    --ssh-key-path)
      [[ $# -ge 2 ]] || die "--ssh-key-path requires a value"
      SSH_KEY_PATH="$2"
      shift 2
      ;;
    --ssh-port)
      [[ $# -ge 2 ]] || die "--ssh-port requires a value"
      SSH_PORT="$2"
      shift 2
      ;;
    --env)
      [[ $# -ge 2 ]] || die "--env requires a value"
      ENVIRONMENT="$2"
      shift 2
      ;;
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
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --apply)
      APPLY_MANIFESTS=1
      shift
      ;;
    --with-runner)
      WITH_RUNNER=1
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

[[ -f "${PACKER_VARS}" ]] || die "Packer vars file not found: ${PACKER_VARS}"
[[ -n "${CONTROL_PLANE_IP}" ]] || die "--control-plane-ip is required"
if [[ -z "${SSH_USER}" ]]; then
  SSH_USER="$(read_optional_packer_var ssh_username)"
fi
if [[ -z "${SSH_PASSWORD}" && -z "${SSH_KEY_PATH}" ]]; then
  SSH_PASSWORD="$(read_optional_packer_var ssh_password)"
fi
[[ -n "${SSH_USER}" ]] || die "Unable to determine SSH user."
[[ -n "${SSH_PASSWORD}" || -n "${SSH_KEY_PATH}" ]] || die "Provide --ssh-password or --ssh-key-path."
[[ "${WITH_RUNNER}" != "1" || "${APPLY_MANIFESTS}" == "1" ]] || die "--with-runner requires --apply"

require_command bash
require_command scp
require_command ssh
if [[ -n "${SSH_PASSWORD}" ]]; then
  require_command sshpass
fi

build_ssh_opts

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  log "Building offline bundle locally: ${BUNDLE_DIR}"
  IMAGE_NAMESPACE="${IMAGE_NAMESPACE}" IMAGE_TAG="${IMAGE_TAG}" \
    bash "${ROOT_DIR}/scripts/prepare_offline_bundle.sh" --out-dir "${BUNDLE_DIR}"
else
  log "Reusing existing offline bundle: ${BUNDLE_DIR}"
fi

[[ -d "${BUNDLE_DIR}/images" ]] || die "Offline bundle images directory missing: ${BUNDLE_DIR}/images"
[[ -d "${BUNDLE_DIR}/k8s" ]] || die "Offline bundle k8s directory missing: ${BUNDLE_DIR}/k8s"

log "Preparing remote bundle directory: ${REMOTE_BUNDLE_DIR}"
remote_sudo "${CONTROL_PLANE_IP}" "rm -rf '${REMOTE_BUNDLE_DIR}' && mkdir -p '${REMOTE_BUNDLE_DIR}' && chown '${SSH_USER}:${SSH_USER}' '${REMOTE_BUNDLE_DIR}'"

log "Copying offline bundle to ${CONTROL_PLANE_IP}"
scp_copy_dir "${BUNDLE_DIR}/." "${CONTROL_PLANE_IP}" "${REMOTE_BUNDLE_DIR}/"

log "Importing image archives on target VM"
import_cmd="bash /opt/k8s-data-platform/scripts/import_offline_bundle.sh --bundle-dir '${REMOTE_BUNDLE_DIR}' --env '${ENVIRONMENT}'"
if [[ "${APPLY_MANIFESTS}" == "1" ]]; then
  import_cmd="${import_cmd} --apply"
fi
if [[ "${WITH_RUNNER}" == "1" ]]; then
  import_cmd="${import_cmd} --with-runner"
fi
remote_sudo "${CONTROL_PLANE_IP}" "${import_cmd}"

log "Offline bundle preload completed."
log "Target VM: ${CONTROL_PLANE_IP}"
log "Remote bundle path: ${REMOTE_BUNDLE_DIR}"
