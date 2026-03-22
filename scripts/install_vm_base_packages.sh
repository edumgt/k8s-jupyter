#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKER_VARS="${PACKER_VARS:-${ROOT_DIR}/packer/variables.vmware.auto.pkrvars.hcl}"
CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-192.168.56.10}"
WORKER1_IP="${WORKER1_IP:-192.168.56.11}"
WORKER2_IP="${WORKER2_IP:-192.168.56.12}"
SSH_USER="${SSH_USER:-}"
SSH_PASSWORD="${SSH_PASSWORD:-}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SSH_PORT="${SSH_PORT:-22}"
PLAYWRIGHT_IMAGE="${PLAYWRIGHT_IMAGE:-mcr.microsoft.com/playwright:v1.58.2-jammy}"
INSTALL_PLAYWRIGHT_IMAGE=1

DEFAULT_PACKAGES=(
  apt-transport-https
  build-essential
  ca-certificates
  curl
  dnsutils
  ftp
  git
  gnupg
  htop
  iproute2
  iputils-ping
  jq
  less
  lftp
  lsb-release
  lsof
  net-tools
  python3
  python3-dev
  python3-pip
  python3-venv
  rsync
  software-properties-common
  telnet
  tmux
  traceroute
  tree
  unzip
  vim
  vsftpd
  wget
  zip
  openjdk-17-jdk-headless
)

usage() {
  cat <<'EOF'
Usage: bash scripts/install_vm_base_packages.sh [options]

Installs common Linux utility packages on the three VMware nodes and optionally
pulls the Playwright Docker image onto each VM.

Options:
  --vars-file PATH            Packer vars file for SSH defaults.
  --control-plane-ip IP       Control-plane VM IP.
  --worker1-ip IP             Worker 1 VM IP.
  --worker2-ip IP             Worker 2 VM IP.
  --ssh-user USER             SSH username override.
  --ssh-password PASS         SSH password override.
  --ssh-key-path PATH         SSH private key override.
  --ssh-port PORT             SSH port override (default: 22).
  --playwright-image IMAGE    Playwright Docker image to pull on each VM.
  --skip-playwright-image     Skip Docker pull on the VMs.
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

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

ssh_opts=()

build_ssh_opts() {
  ssh_opts=(
    -p "${SSH_PORT}"
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=10
  )

  if [[ -n "${SSH_KEY_PATH}" ]]; then
    ssh_opts+=(-i "${SSH_KEY_PATH}")
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
    --vars-file)
      PACKER_VARS="$2"
      shift 2
      ;;
    --control-plane-ip)
      CONTROL_PLANE_IP="$2"
      shift 2
      ;;
    --worker1-ip)
      WORKER1_IP="$2"
      shift 2
      ;;
    --worker2-ip)
      WORKER2_IP="$2"
      shift 2
      ;;
    --ssh-user)
      SSH_USER="$2"
      shift 2
      ;;
    --ssh-password)
      SSH_PASSWORD="$2"
      shift 2
      ;;
    --ssh-key-path)
      SSH_KEY_PATH="$2"
      shift 2
      ;;
    --ssh-port)
      SSH_PORT="$2"
      shift 2
      ;;
    --playwright-image)
      PLAYWRIGHT_IMAGE="$2"
      shift 2
      ;;
    --skip-playwright-image)
      INSTALL_PLAYWRIGHT_IMAGE=0
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
if [[ -z "${SSH_USER}" ]]; then
  SSH_USER="$(read_optional_packer_var ssh_username)"
fi
if [[ -z "${SSH_PASSWORD}" && -z "${SSH_KEY_PATH}" ]]; then
  SSH_PASSWORD="$(read_optional_packer_var ssh_password)"
fi

[[ -n "${SSH_USER}" ]] || die "Unable to determine SSH user."
[[ -n "${SSH_PASSWORD}" || -n "${SSH_KEY_PATH}" ]] || die "Provide --ssh-password or --ssh-key-path."

require_command ssh
if [[ -n "${SSH_PASSWORD}" ]]; then
  require_command sshpass
fi

build_ssh_opts

package_list="$(printf '%s ' "${DEFAULT_PACKAGES[@]}")"
package_list="${package_list% }"

hosts=(
  "${CONTROL_PLANE_IP}:control-plane"
  "${WORKER1_IP}:worker-1"
  "${WORKER2_IP}:worker-2"
)

for item in "${hosts[@]}"; do
  IFS=':' read -r host label <<<"${item}"
  log "Installing base packages on ${label} (${host})"
  remote_sudo "${host}" "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ${package_list}
    systemctl enable vsftpd >/dev/null 2>&1 || true
    systemctl restart vsftpd >/dev/null 2>&1 || true
    java -version >/dev/null 2>&1
    python3 --version >/dev/null 2>&1
  "

  if [[ "${INSTALL_PLAYWRIGHT_IMAGE}" == "1" ]]; then
    log "Pulling Playwright image on ${label} (${host})"
    remote_sudo "${host}" "docker pull '${PLAYWRIGHT_IMAGE}'"
  fi
done

log "VM base package installation completed."
