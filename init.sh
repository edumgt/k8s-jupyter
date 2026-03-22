#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WSL_HOSTS_FILE="/etc/hosts"
WINDOWS_HOSTS_FILE_WIN='C:\Windows\System32\drivers\etc\hosts'

CONTROL_PLANE_HOSTNAME="${CONTROL_PLANE_HOSTNAME:-k8s-data-platform}"
WORKER1_HOSTNAME="${WORKER1_HOSTNAME:-k8s-worker-1}"
WORKER2_HOSTNAME="${WORKER2_HOSTNAME:-k8s-worker-2}"

CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-192.168.56.10}"
WORKER1_IP="${WORKER1_IP:-192.168.56.11}"
WORKER2_IP="${WORKER2_IP:-192.168.56.12}"
GATEWAY="${GATEWAY:-192.168.56.1}"
DNS_SERVERS="${DNS_SERVERS:-192.168.56.1,1.1.1.1,8.8.8.8}"
NETWORK_CIDR_PREFIX="${NETWORK_CIDR_PREFIX:-24}"
INGRESS_LB_IP="${INGRESS_LB_IP:-192.168.56.240}"
METALLB_RANGE="${METALLB_RANGE:-192.168.56.240-192.168.56.250}"
NET_INTERFACE="${NET_INTERFACE:-}"
WSL_ROUTE_GATEWAY="${WSL_ROUTE_GATEWAY:-}"
BUNDLE_DIR="${BUNDLE_DIR:-${ROOT_DIR}/dist/offline-bundle}"
REMOTE_BUNDLE_DIR="${REMOTE_BUNDLE_DIR:-/opt/k8s-data-platform/offline-bundle}"
OFFLINE_ENV="${OFFLINE_ENV:-dev}"
OFFLINE_NAMESPACE="${OFFLINE_NAMESPACE:-edumgt}"
OFFLINE_TAG="${OFFLINE_TAG:-latest}"

HOSTS_DOMAIN_LINE=""
RUN_STAGE_VM_COMMANDS=0
RUN_STAGE_WSL_ROUTE=0
RUN_STAGE_WSL_HOSTS=0
RUN_STAGE_WINDOWS_HOSTS=0
RUN_STAGE_PRELOAD=0
RUN_STAGE_START=0
PRINT_ONLY=0
PRELOAD_SKIP_BUILD=0
PRELOAD_APPLY=0
PRELOAD_WITH_RUNNER=0
EXTRA_ARGS=()

usage() {
  cat <<'EOF'
Usage: bash init.sh [options] [-- <extra start.sh args>]

init.sh helps with the post-import VMware OVA workflow:
  1) Print the exact per-VM commands for static IP + hostname setup
  2) Add a WSL route for 192.168.56.0/24 via the Windows/WSL gateway
  3) Preload an offline bundle into the control-plane VM
  4) Update WSL /etc/hosts for ingress domains
  5) Update Windows hosts file for ingress domains
  6) Run start.sh with the recommended static-network arguments

Important:
  - If the 3 imported VMs currently share the same IP, you must first log into
    each VM console separately in VMware and run the printed commands.
  - init.sh cannot safely change 3 different VMs remotely while they all answer
    on the same address.
  - The WSL route step assumes Windows/VMware networking is already configured
    so the Windows host can reach 192.168.56.0/24.

Options:
  --control-plane-ip IP       Default: 192.168.56.10
  --worker1-ip IP             Default: 192.168.56.11
  --worker2-ip IP             Default: 192.168.56.12
  --gateway IP                Default: 192.168.56.1
  --dns-servers CSV           Default: 192.168.56.1,1.1.1.1,8.8.8.8
  --network-cidr-prefix N     Default: 24
  --net-interface IFACE       Optional net interface for VM static IP script
  --ingress-lb-ip IP          Default: 192.168.56.240
  --metallb-range RANGE       Default: 192.168.56.240-192.168.56.250
  --wsl-hosts-file PATH       Default: /etc/hosts
  --wsl-route-gateway IP      Override WSL route gateway
                               Default: current WSL default gateway
  --bundle-dir PATH           Offline bundle directory for preload
  --remote-bundle-dir PATH    Remote bundle directory on the VM
  --offline-env dev|prod      Overlay env for preload/import (default: dev)
  --offline-namespace NAME    Image namespace for bundle build (default: edumgt)
  --offline-tag TAG           App image tag for bundle build (default: latest)
  --preload-skip-build        Reuse an existing offline bundle
  --preload-apply             Apply bundled manifests after preload
  --preload-with-runner       Apply runner overlay too with preload

Stages:
  --vm-commands               Print per-VM commands only
  --apply-wsl-route           Add/replace WSL route for 192.168.56.0/24
  --preload-offline-bundle    Build/reuse and copy the offline bundle to the control-plane VM
  --apply-wsl-hosts           Update WSL hosts file
  --apply-windows-hosts       Update Windows hosts file via powershell.exe
  --run-start                 Run start.sh with --always-provision
  --all                       Run vm-commands + WSL route + preload + WSL hosts + Windows hosts + start.sh
  --print-only                Print actions without applying local changes
  -h, --help                  Show this help

Examples:
  bash init.sh --vm-commands
  bash init.sh --apply-wsl-route
  bash init.sh --preload-offline-bundle --preload-skip-build
  bash init.sh --apply-wsl-hosts --apply-windows-hosts
  bash init.sh --run-start -- --skip-nexus-prime --skip-export
  bash init.sh --all -- --skip-nexus-prime --skip-export
EOF
}

log() {
  printf '[init.sh] %s\n' "$*"
}

die() {
  printf '[init.sh] ERROR: %s\n' "$*" >&2
  exit 1
}

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

require_ipv4() {
  local label="$1"
  local value="$2"
  is_ipv4 "${value}" || die "${label} must be an IPv4 address: ${value}"
}

build_domain_line() {
  printf '%s %s\n' "${INGRESS_LB_IP}" "platform.local jupyter.platform.local gitlab.platform.local airflow.platform.local nexus.platform.local"
}

discover_wsl_default_gateway() {
  ip route | awk '/^default / {print $3; exit}'
}

print_vm_section() {
  local label="$1"
  local node_ip="$2"
  local node_hostname="$3"
  local iface_args=()

  if [[ -n "${NET_INTERFACE}" ]]; then
    iface_args=(--iface "${NET_INTERFACE}")
  fi

  printf '\n[%s]\n' "${label}"
  printf '%s\n' "sudo bash /opt/k8s-data-platform/scripts/set_static_ip.sh --ip ${node_ip} --prefix ${NETWORK_CIDR_PREFIX} --gateway ${GATEWAY} --dns ${DNS_SERVERS}${NET_INTERFACE:+ --iface ${NET_INTERFACE}}"
  printf '%s\n' "sudo bash /opt/k8s-data-platform/scripts/set_hostname_hosts.sh --hostname ${node_hostname} --entry \"${CONTROL_PLANE_IP} ${CONTROL_PLANE_HOSTNAME}\" --entry \"${WORKER1_IP} ${WORKER1_HOSTNAME}\" --entry \"${WORKER2_IP} ${WORKER2_HOSTNAME}\""
  printf '%s\n' "hostname"
  printf '%s\n' "hostname -I"
  printf '%s\n' "ip route"
}

print_vm_commands() {
  log "If the 3 imported VMs currently share the same IP, do this first in each VMware console."
  print_vm_section "control-plane VM" "${CONTROL_PLANE_IP}" "${CONTROL_PLANE_HOSTNAME}"
  print_vm_section "worker-1 VM" "${WORKER1_IP}" "${WORKER1_HOSTNAME}"
  print_vm_section "worker-2 VM" "${WORKER2_IP}" "${WORKER2_HOSTNAME}"
}

apply_wsl_route() {
  local gateway="$1"
  local target_cidr

  target_cidr="$(printf '%s.0/24' "${CONTROL_PLANE_IP%.*}")"

  if [[ "${PRINT_ONLY}" -eq 1 ]]; then
    log "Would add/replace WSL route: ${target_cidr} via ${gateway} dev eth0"
    return 0
  fi

  sudo ip route replace "${target_cidr}" via "${gateway}" dev eth0
  log "Applied WSL route: ${target_cidr} via ${gateway} dev eth0"
}

run_preload() {
  local cmd=(
    bash "${ROOT_DIR}/scripts/preload_offline_bundle_to_vm.sh"
    --control-plane-ip "${CONTROL_PLANE_IP}"
    --vars-file "${ROOT_DIR}/packer/variables.vmware.auto.pkrvars.hcl"
    --bundle-dir "${BUNDLE_DIR}"
    --remote-bundle-dir "${REMOTE_BUNDLE_DIR}"
    --env "${OFFLINE_ENV}"
    --namespace "${OFFLINE_NAMESPACE}"
    --tag "${OFFLINE_TAG}"
  )

  if [[ "${PRELOAD_SKIP_BUILD}" -eq 1 ]]; then
    cmd+=(--skip-build)
  fi
  if [[ "${PRELOAD_APPLY}" -eq 1 ]]; then
    cmd+=(--apply)
  fi
  if [[ "${PRELOAD_WITH_RUNNER}" -eq 1 ]]; then
    cmd+=(--with-runner)
  fi

  if [[ "${PRINT_ONLY}" -eq 1 ]]; then
    log "Would preload offline bundle with:"
    printf '%q ' "${cmd[@]}"
    printf '\n'
    return 0
  fi

  "${cmd[@]}"
}

upsert_wsl_hosts() {
  local hosts_file="$1"
  local line="$2"

  [[ -f "${hosts_file}" ]] || die "WSL hosts file not found: ${hosts_file}"

  if [[ "${PRINT_ONLY}" -eq 1 ]]; then
    log "Would update WSL hosts file: ${hosts_file}"
    printf '%s\n' "${line}"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "${tmp}"' RETURN

  awk '
    /platform\.local|jupyter\.platform\.local|gitlab\.platform\.local|airflow\.platform\.local|nexus\.platform\.local/ { next }
    { print }
  ' "${hosts_file}" > "${tmp}"
  printf '%s\n' "${line}" >> "${tmp}"

  if [[ "${EUID}" -eq 0 ]]; then
    cat "${tmp}" > "${hosts_file}"
  else
    sudo cp "${tmp}" "${hosts_file}"
  fi
  log "Updated WSL hosts file: ${hosts_file}"
}

apply_windows_hosts() {
  local line="$1"
  local escaped_line

  command -v powershell.exe >/dev/null 2>&1 || die "powershell.exe is required to update Windows hosts from WSL."

  escaped_line="${line//\'/''}"

  if [[ "${PRINT_ONLY}" -eq 1 ]]; then
    log "Would update Windows hosts file: ${WINDOWS_HOSTS_FILE_WIN}"
    printf '%s\n' "${line}"
    return 0
  fi

  powershell.exe -NoProfile -Command "
    \$hostsPath = '${WINDOWS_HOSTS_FILE_WIN}';
    \$newLine = '${escaped_line}';
    \$content = @();
    if (Test-Path -LiteralPath \$hostsPath) {
      \$content = Get-Content -LiteralPath \$hostsPath | Where-Object {
        \$_ -notmatch 'platform\.local|jupyter\.platform\.local|gitlab\.platform\.local|airflow\.platform\.local|nexus\.platform\.local'
      }
    }
    \$content += \$newLine
    Set-Content -LiteralPath \$hostsPath -Value \$content -Encoding ASCII
  " >/dev/null

  log "Updated Windows hosts file: ${WINDOWS_HOSTS_FILE_WIN}"
}

run_start() {
  local cmd=(
    bash "${ROOT_DIR}/start.sh"
    --vars-file "${ROOT_DIR}/packer/variables.vmware.auto.pkrvars.hcl"
    --static-network
    --control-plane-ip "${CONTROL_PLANE_IP}"
    --worker1-ip "${WORKER1_IP}"
    --worker2-ip "${WORKER2_IP}"
    --gateway "${GATEWAY}"
    --dns-servers "${DNS_SERVERS}"
    --metallb-range "${METALLB_RANGE}"
    --ingress-lb-ip "${INGRESS_LB_IP}"
    --always-provision
  )

  if [[ -n "${NET_INTERFACE}" ]]; then
    cmd+=(--net-interface "${NET_INTERFACE}")
  fi
  if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi

  if [[ "${PRINT_ONLY}" -eq 1 ]]; then
    log "Would run start.sh with:"
    printf '%q ' "${cmd[@]}"
    printf '\n'
    return 0
  fi

  exec "${cmd[@]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --control-plane-ip)
      [[ $# -ge 2 ]] || die "--control-plane-ip requires a value"
      CONTROL_PLANE_IP="$2"
      shift 2
      ;;
    --worker1-ip)
      [[ $# -ge 2 ]] || die "--worker1-ip requires a value"
      WORKER1_IP="$2"
      shift 2
      ;;
    --worker2-ip)
      [[ $# -ge 2 ]] || die "--worker2-ip requires a value"
      WORKER2_IP="$2"
      shift 2
      ;;
    --gateway)
      [[ $# -ge 2 ]] || die "--gateway requires a value"
      GATEWAY="$2"
      shift 2
      ;;
    --dns-servers)
      [[ $# -ge 2 ]] || die "--dns-servers requires a value"
      DNS_SERVERS="$2"
      shift 2
      ;;
    --network-cidr-prefix)
      [[ $# -ge 2 ]] || die "--network-cidr-prefix requires a value"
      NETWORK_CIDR_PREFIX="$2"
      shift 2
      ;;
    --net-interface)
      [[ $# -ge 2 ]] || die "--net-interface requires a value"
      NET_INTERFACE="$2"
      shift 2
      ;;
    --ingress-lb-ip)
      [[ $# -ge 2 ]] || die "--ingress-lb-ip requires a value"
      INGRESS_LB_IP="$2"
      shift 2
      ;;
    --metallb-range)
      [[ $# -ge 2 ]] || die "--metallb-range requires a value"
      METALLB_RANGE="$2"
      shift 2
      ;;
    --wsl-hosts-file)
      [[ $# -ge 2 ]] || die "--wsl-hosts-file requires a value"
      WSL_HOSTS_FILE="$2"
      shift 2
      ;;
    --wsl-route-gateway)
      [[ $# -ge 2 ]] || die "--wsl-route-gateway requires a value"
      WSL_ROUTE_GATEWAY="$2"
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
    --offline-env)
      [[ $# -ge 2 ]] || die "--offline-env requires a value"
      OFFLINE_ENV="$2"
      shift 2
      ;;
    --offline-namespace)
      [[ $# -ge 2 ]] || die "--offline-namespace requires a value"
      OFFLINE_NAMESPACE="$2"
      shift 2
      ;;
    --offline-tag)
      [[ $# -ge 2 ]] || die "--offline-tag requires a value"
      OFFLINE_TAG="$2"
      shift 2
      ;;
    --preload-skip-build)
      PRELOAD_SKIP_BUILD=1
      shift
      ;;
    --preload-apply)
      PRELOAD_APPLY=1
      shift
      ;;
    --preload-with-runner)
      PRELOAD_WITH_RUNNER=1
      shift
      ;;
    --vm-commands)
      RUN_STAGE_VM_COMMANDS=1
      shift
      ;;
    --apply-wsl-route)
      RUN_STAGE_WSL_ROUTE=1
      shift
      ;;
    --preload-offline-bundle)
      RUN_STAGE_PRELOAD=1
      shift
      ;;
    --apply-wsl-hosts)
      RUN_STAGE_WSL_HOSTS=1
      shift
      ;;
    --apply-windows-hosts)
      RUN_STAGE_WINDOWS_HOSTS=1
      shift
      ;;
    --run-start)
      RUN_STAGE_START=1
      shift
      ;;
    --all)
      RUN_STAGE_VM_COMMANDS=1
      RUN_STAGE_WSL_ROUTE=1
      RUN_STAGE_PRELOAD=1
      RUN_STAGE_WSL_HOSTS=1
      RUN_STAGE_WINDOWS_HOSTS=1
      RUN_STAGE_START=1
      shift
      ;;
    --print-only)
      PRINT_ONLY=1
      shift
      ;;
    --)
      shift
      EXTRA_ARGS+=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

require_ipv4 "control-plane IP" "${CONTROL_PLANE_IP}"
require_ipv4 "worker1 IP" "${WORKER1_IP}"
require_ipv4 "worker2 IP" "${WORKER2_IP}"
require_ipv4 "gateway" "${GATEWAY}"
require_ipv4 "ingress LB IP" "${INGRESS_LB_IP}"
[[ "${PRELOAD_WITH_RUNNER}" != "1" || "${PRELOAD_APPLY}" == "1" ]] || die "--preload-with-runner requires --preload-apply"

if [[ -z "${WSL_ROUTE_GATEWAY}" ]]; then
  WSL_ROUTE_GATEWAY="$(discover_wsl_default_gateway)"
fi
[[ -n "${WSL_ROUTE_GATEWAY}" ]] || die "Unable to detect WSL default gateway. Pass --wsl-route-gateway."
require_ipv4 "WSL route gateway" "${WSL_ROUTE_GATEWAY}"

HOSTS_DOMAIN_LINE="$(build_domain_line)"

if [[ "${RUN_STAGE_VM_COMMANDS}" -eq 0 && "${RUN_STAGE_WSL_ROUTE}" -eq 0 && "${RUN_STAGE_PRELOAD}" -eq 0 && "${RUN_STAGE_WSL_HOSTS}" -eq 0 && "${RUN_STAGE_WINDOWS_HOSTS}" -eq 0 && "${RUN_STAGE_START}" -eq 0 ]]; then
  RUN_STAGE_VM_COMMANDS=1
fi

log "Planned node IPs"
log "  ${CONTROL_PLANE_HOSTNAME} -> ${CONTROL_PLANE_IP}"
log "  ${WORKER1_HOSTNAME} -> ${WORKER1_IP}"
log "  ${WORKER2_HOSTNAME} -> ${WORKER2_IP}"
log "WSL route gateway -> ${WSL_ROUTE_GATEWAY}"
log "Offline bundle dir -> ${BUNDLE_DIR}"
log "Ingress domains -> ${HOSTS_DOMAIN_LINE}"

if [[ "${RUN_STAGE_VM_COMMANDS}" -eq 1 ]]; then
  print_vm_commands
fi

if [[ "${RUN_STAGE_WSL_ROUTE}" -eq 1 ]]; then
  apply_wsl_route "${WSL_ROUTE_GATEWAY}"
fi

if [[ "${RUN_STAGE_PRELOAD}" -eq 1 ]]; then
  run_preload
fi

if [[ "${RUN_STAGE_WSL_HOSTS}" -eq 1 ]]; then
  upsert_wsl_hosts "${WSL_HOSTS_FILE}" "${HOSTS_DOMAIN_LINE}"
fi

if [[ "${RUN_STAGE_WINDOWS_HOSTS}" -eq 1 ]]; then
  apply_windows_hosts "${HOSTS_DOMAIN_LINE}"
fi

if [[ "${RUN_STAGE_START}" -eq 1 ]]; then
  run_start
fi
