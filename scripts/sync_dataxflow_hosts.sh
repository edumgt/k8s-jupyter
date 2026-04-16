#!/usr/bin/env bash
set -euo pipefail

INGRESS_IP="${INGRESS_IP:-<YOUR_LB_IP>}"
WINDOWS_HOSTS_PATH="${WINDOWS_HOSTS_PATH:-/mnt/c/Windows/System32/drivers/etc/hosts}"
BEGIN_MARKER="# BEGIN DATAXFLOW_LOCAL"
END_MARKER="# END DATAXFLOW_LOCAL"
APPLY_WSL=0
APPLY_WINDOWS=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: scripts/sync_dataxflow_hosts.sh [options]

Synchronize hosts entries for dataxflow domains.

Options:
  --ingress-ip <ip>          Ingress/LB IP to map domains to (default: <YOUR_LB_IP>)
  --apply-wsl-hosts          Apply changes to /etc/hosts
  --apply-windows-hosts      Apply changes to Windows hosts file from WSL mount
  --windows-hosts-path <p>   Override Windows hosts path
  --dry-run                  Print resulting block only
  -h, --help                 Show help

Domains:
  dataxflow.local
  api.dataxflow.local
  airflow.dataxflow.local
EOF
}

log() {
  printf '[sync_dataxflow_hosts] %s\n' "$*"
}

render_block() {
  cat <<EOF
${BEGIN_MARKER}
${INGRESS_IP} dataxflow.local api.dataxflow.local airflow.dataxflow.local
${END_MARKER}
EOF
}

strip_block() {
  local src="$1"
  awk -v b="${BEGIN_MARKER}" -v e="${END_MARKER}" '
    BEGIN { skip=0 }
    $0 == b { skip=1; next }
    $0 == e { skip=0; next }
    !skip { print }
  ' "${src}"
}

apply_to_hosts_file() {
  local target="$1"
  local use_sudo="$2"
  local tmp
  tmp="$(mktemp)"
  strip_block "${target}" > "${tmp}"
  {
    cat "${tmp}"
    render_block
  } > "${tmp}.new"

  if [[ "${use_sudo}" == "1" ]]; then
    if ! sudo tee "${target}" < "${tmp}.new" >/dev/null; then
      rm -f "${tmp}" "${tmp}.new"
      return 1
    fi
  else
    if ! cat "${tmp}.new" > "${target}"; then
      rm -f "${tmp}" "${tmp}.new"
      return 1
    fi
  fi
  rm -f "${tmp}" "${tmp}.new"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ingress-ip)
      INGRESS_IP="${2:-}"
      shift 2
      ;;
    --apply-wsl-hosts)
      APPLY_WSL=1
      shift
      ;;
    --apply-windows-hosts)
      APPLY_WINDOWS=1
      shift
      ;;
    --windows-hosts-path)
      WINDOWS_HOSTS_PATH="${2:-}"
      shift 2
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
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${DRY_RUN}" == "1" ]]; then
  render_block
  exit 0
fi

if [[ "${APPLY_WSL}" == "0" && "${APPLY_WINDOWS}" == "0" ]]; then
  log "No apply target selected. Use --apply-wsl-hosts and/or --apply-windows-hosts."
  render_block
  exit 0
fi

if [[ "${APPLY_WSL}" == "1" ]]; then
  log "Applying block to /etc/hosts"
  apply_to_hosts_file "/etc/hosts" "1"
  log "Applied to /etc/hosts"
fi

if [[ "${APPLY_WINDOWS}" == "1" ]]; then
  if [[ ! -f "${WINDOWS_HOSTS_PATH}" ]]; then
    log "Windows hosts file not found: ${WINDOWS_HOSTS_PATH}"
    exit 1
  fi
  if apply_to_hosts_file "${WINDOWS_HOSTS_PATH}" "0"; then
    log "Applied to ${WINDOWS_HOSTS_PATH}"
  else
    log "Failed to update ${WINDOWS_HOSTS_PATH}. Retry from elevated shell."
    exit 1
  fi
fi
