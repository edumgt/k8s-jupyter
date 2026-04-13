#!/usr/bin/env bash
set -euo pipefail

CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-}"
SSH_USER="${SSH_USER:-disadm}"
SSH_PORT="${SSH_PORT:-10022}"
SSH_PASSWORD="${SSH_PASSWORD:-}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
REMOTE_ADMIN_CONF="${REMOTE_ADMIN_CONF:-/etc/kubernetes/admin.conf}"
API_SERVER_HOST="${API_SERVER_HOST:-}"
API_SERVER_PORT="${API_SERVER_PORT:-6443}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$HOME/.kube/config}"
SKIP_ACTIVATE=0
SKIP_VERIFY=0

usage() {
  cat <<'EOF'
Usage: bash scripts/setup_wsl_kubectl.sh [options]

Fetches Kubernetes admin kubeconfig from control-plane and configures
WSL default kubectl context for real-time pod verification.

Options:
  --control-plane-ip IP      Required SSH target IP (example: 192.168.56.10)
  --ssh-user USER            SSH user (default: disadm)
  --ssh-port PORT            SSH port (default: 10022)
  --ssh-password PASS        SSH password (optional)
  --ssh-key-path PATH        SSH private key path (optional)
  --remote-admin-conf PATH   Remote kubeconfig path (default: /etc/kubernetes/admin.conf)

  --api-server-host HOST     kube-apiserver endpoint host in kubeconfig
                             (default: --control-plane-ip)
  --api-server-port PORT     kube-apiserver endpoint port (default: 6443)
  --kubeconfig-path PATH     Local target path (default: ~/.kube/config)

  --skip-activate            Do not overwrite/export default ~/.kube/config
  --skip-verify              Skip kubectl connectivity checks
  -h, --help                 Show help

Examples:
  bash scripts/setup_wsl_kubectl.sh \
    --control-plane-ip 192.168.56.10 \
    --ssh-user disadm \
    --ssh-port 10022 \
    --ssh-password 'P@ssw0rd1!'
EOF
}

log() {
  printf '[setup_wsl_kubectl] %s\n' "$*"
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --control-plane-ip)
      [[ $# -ge 2 ]] || die "--control-plane-ip requires a value"
      CONTROL_PLANE_IP="$2"
      shift 2
      ;;
    --ssh-user)
      [[ $# -ge 2 ]] || die "--ssh-user requires a value"
      SSH_USER="$2"
      shift 2
      ;;
    --ssh-port)
      [[ $# -ge 2 ]] || die "--ssh-port requires a value"
      SSH_PORT="$2"
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
    --remote-admin-conf)
      [[ $# -ge 2 ]] || die "--remote-admin-conf requires a value"
      REMOTE_ADMIN_CONF="$2"
      shift 2
      ;;
    --api-server-host)
      [[ $# -ge 2 ]] || die "--api-server-host requires a value"
      API_SERVER_HOST="$2"
      shift 2
      ;;
    --api-server-port)
      [[ $# -ge 2 ]] || die "--api-server-port requires a value"
      API_SERVER_PORT="$2"
      shift 2
      ;;
    --kubeconfig-path)
      [[ $# -ge 2 ]] || die "--kubeconfig-path requires a value"
      KUBECONFIG_PATH="$2"
      shift 2
      ;;
    --skip-activate)
      SKIP_ACTIVATE=1
      shift
      ;;
    --skip-verify)
      SKIP_VERIFY=1
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

[[ -n "${CONTROL_PLANE_IP}" ]] || die "--control-plane-ip is required."
if [[ -z "${API_SERVER_HOST}" ]]; then
  API_SERVER_HOST="${CONTROL_PLANE_IP}"
fi

require_command ssh
require_command kubectl
if [[ -n "${SSH_PASSWORD}" ]]; then
  require_command sshpass
fi

mkdir -p "$(dirname "${KUBECONFIG_PATH}")"

SSH_OPTS=(
  -p "${SSH_PORT}"
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=8
)
if [[ -n "${SSH_KEY_PATH}" ]]; then
  SSH_OPTS+=(-i "${SSH_KEY_PATH}")
fi

fetch_remote_admin_conf() {
  local target_file="$1"
  local remote_cmd="sudo cat '${REMOTE_ADMIN_CONF}'"
  if [[ -n "${SSH_PASSWORD}" ]]; then
    local escaped_pw
    escaped_pw="$(printf '%s' "${SSH_PASSWORD}" | sed "s/'/'\"'\"'/g")"
    SSHPASS="${SSH_PASSWORD}" sshpass -e ssh "${SSH_OPTS[@]}" "${SSH_USER}@${CONTROL_PLANE_IP}" \
      "printf '%s\n' '${escaped_pw}' | sudo -S -p '' cat '${REMOTE_ADMIN_CONF}'" > "${target_file}"
    return
  fi
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${CONTROL_PLANE_IP}" "${remote_cmd}" > "${target_file}"
}

tmp_kubeconfig="$(mktemp)"
trap 'rm -f "${tmp_kubeconfig}"' EXIT

log "Fetching ${REMOTE_ADMIN_CONF} from ${SSH_USER}@${CONTROL_PLANE_IP}:${SSH_PORT}"
fetch_remote_admin_conf "${tmp_kubeconfig}"

chmod 600 "${tmp_kubeconfig}"
kubectl --kubeconfig "${tmp_kubeconfig}" config set-cluster kubernetes \
  --server="https://${API_SERVER_HOST}:${API_SERVER_PORT}" >/dev/null

if [[ "${SKIP_ACTIVATE}" -eq 0 ]]; then
  if [[ -f "${KUBECONFIG_PATH}" ]]; then
    backup_path="${KUBECONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
    cp -f "${KUBECONFIG_PATH}" "${backup_path}"
    log "Backed up existing kubeconfig to ${backup_path}"
  fi
  cp -f "${tmp_kubeconfig}" "${KUBECONFIG_PATH}"
  chmod 600 "${KUBECONFIG_PATH}"
  log "Activated kubeconfig at ${KUBECONFIG_PATH}"
else
  out_path="${KUBECONFIG_PATH}.platform"
  cp -f "${tmp_kubeconfig}" "${out_path}"
  chmod 600 "${out_path}"
  log "Saved kubeconfig to ${out_path} (default not changed)"
fi

if [[ "${SKIP_VERIFY}" -eq 0 ]]; then
  log "Verifying cluster connectivity"
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get nodes -o wide
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get pods -A
fi

log "Done."
