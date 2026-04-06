#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-data-platform-dev}"
HOST_SUFFIX="${HOST_SUFFIX:-jupyter.local}"
INGRESS_NAME="${INGRESS_NAME:-jupyter-user-wildcard}"
LABEL_SELECTOR="${LABEL_SELECTOR:-app.kubernetes.io/component=user-jupyter}"
WSL_HOSTS_FILE="${WSL_HOSTS_FILE:-/etc/hosts}"
WINDOWS_HOSTS_FILE_WIN="${WINDOWS_HOSTS_FILE_WIN:-C:\Windows\System32\drivers\etc\hosts}"
INGRESS_IP="${INGRESS_IP:-}"
APPLY_WSL=0
APPLY_WINDOWS=0
PRINT_ONLY=0
WATCH=0
INTERVAL_SEC=10
LAST_BLOCK_HASH=""

BEGIN_MARKER="# BEGIN JUPYTER_DYNAMIC_ROUTES"
END_MARKER="# END JUPYTER_DYNAMIC_ROUTES"

usage() {
  cat <<'EOF'
Usage: bash scripts/sync_jupyter_dynamic_hosts.sh [options]

Sync dynamic Jupyter pod host entries to local hosts files.

Options:
  --namespace NAME            Kubernetes namespace (default: data-platform-dev)
  --host-suffix DOMAIN        Dynamic host suffix (default: jupyter.local)
  --ingress-name NAME         Ingress name to read LB IP from (default: jupyter-user-wildcard)
  --ingress-ip IP             Override ingress LB IP.
  --label-selector SELECTOR   Pod label selector (default: app.kubernetes.io/component=user-jupyter)
  --apply-wsl-hosts           Write block to WSL hosts file (/etc/hosts).
  --wsl-hosts-file PATH       WSL hosts file path (default: /etc/hosts).
  --apply-windows-hosts       Write block to Windows hosts file via powershell.exe.
  --windows-hosts-file PATH   Windows hosts file path (default: C:\Windows\System32\drivers\etc\hosts).
  --print-only                Print generated block only.
  --watch                     Continuously refresh hosts entries.
  --interval-sec N            Watch interval seconds (default: 10).
  -h, --help                  Show this help.

Examples:
  bash scripts/sync_jupyter_dynamic_hosts.sh --print-only
  bash scripts/sync_jupyter_dynamic_hosts.sh --apply-wsl-hosts --apply-windows-hosts
  bash scripts/sync_jupyter_dynamic_hosts.sh --apply-wsl-hosts --watch --interval-sec 5
EOF
}

log() {
  printf '[sync_jupyter_dynamic_hosts] %s\n' "$*"
}

die() {
  printf '[sync_jupyter_dynamic_hosts] %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

to_windows_path() {
  local path="$1"
  if [[ "$path" =~ ^[A-Za-z]:[\\/].* ]]; then
    printf '%s' "$path"
    return 0
  fi
  command -v wslpath >/dev/null 2>&1 || die "wslpath is required to convert Windows path from WSL."
  wslpath -w "$path"
}

resolve_ingress_ip() {
  if [[ -n "${INGRESS_IP}" ]]; then
    is_ipv4 "${INGRESS_IP}" || die "Invalid --ingress-ip: ${INGRESS_IP}"
    printf '%s' "${INGRESS_IP}"
    return 0
  fi

  local ip
  ip="$(
    kubectl -n "${NAMESPACE}" get ingress "${INGRESS_NAME}" \
      -o jsonpath='{range .status.loadBalancer.ingress[*]}{.ip}{"\n"}{end}' 2>/dev/null \
      | sed '/^[[:space:]]*$/d' \
      | head -n 1
  )"
  if [[ -z "${ip}" ]]; then
    die "Unable to resolve ingress IP from ${NAMESPACE}/${INGRESS_NAME}. Provide --ingress-ip."
  fi
  is_ipv4 "${ip}" || die "Resolved ingress IP is not IPv4: ${ip}"
  printf '%s' "${ip}"
}

collect_pod_names() {
  kubectl -n "${NAMESPACE}" get pods -l "${LABEL_SELECTOR}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | sed '/^[[:space:]]*$/d' \
    | sort -u
}

build_hosts_block() {
  local ingress_ip="$1"
  shift
  local pod_names=("$@")

  printf '%s\n' "${BEGIN_MARKER}"
  printf '%s\n' "# Auto-generated. Do not edit manually."
  printf '%s %s\n' "${ingress_ip}" "${HOST_SUFFIX}"
  local pod
  for pod in "${pod_names[@]}"; do
    printf '%s %s.%s\n' "${ingress_ip}" "${pod}" "${HOST_SUFFIX}"
  done
  printf '%s\n' "${END_MARKER}"
}

strip_old_block() {
  local src_file="$1"
  local dst_file="$2"
  awk -v begin="${BEGIN_MARKER}" -v end="${END_MARKER}" '
    $0 == begin { in_block=1; next }
    in_block && $0 == end { in_block=0; next }
    !in_block { print }
  ' "${src_file}" > "${dst_file}"
}

upsert_unix_hosts_block() {
  local hosts_file="$1"
  local block_file="$2"
  [[ -f "${hosts_file}" ]] || die "WSL hosts file not found: ${hosts_file}"

  local tmp_file
  tmp_file="$(mktemp)"

  strip_old_block "${hosts_file}" "${tmp_file}"
  cat "${block_file}" >> "${tmp_file}"

  if [[ "${EUID}" -eq 0 ]]; then
    cat "${tmp_file}" > "${hosts_file}"
  else
    sudo cp "${tmp_file}" "${hosts_file}"
  fi
  rm -f "${tmp_file}"
  log "Updated WSL hosts file: ${hosts_file}"
}

upsert_windows_hosts_block() {
  local block_file="$1"
  require_command powershell.exe

  local block_path_win
  block_path_win="$(to_windows_path "${block_file}")"

  if ! powershell.exe -NoProfile -Command "
    \$hostsPath = '${WINDOWS_HOSTS_FILE_WIN}';
    \$blockPath = '${block_path_win}';
    \$begin = '${BEGIN_MARKER}';
    \$end = '${END_MARKER}';
    \$newBlock = Get-Content -LiteralPath \$blockPath;
    \$content = @();
    if (Test-Path -LiteralPath \$hostsPath) {
      \$inside = \$false;
      foreach (\$line in (Get-Content -LiteralPath \$hostsPath)) {
        if (\$line -eq \$begin) { \$inside = \$true; continue }
        if (\$inside -and \$line -eq \$end) { \$inside = \$false; continue }
        if (-not \$inside) { \$content += \$line }
      }
    }
    \$content += \$newBlock;
    Set-Content -LiteralPath \$hostsPath -Value \$content -Encoding ASCII;
  " >/dev/null; then
    log "Failed to update Windows hosts file automatically (administrator privileges may be required)."
    return 0
  fi

  log "Updated Windows hosts file: ${WINDOWS_HOSTS_FILE_WIN}"
}

sync_once() {
  local ingress_ip
  ingress_ip="$(resolve_ingress_ip)"

  mapfile -t pod_names < <(collect_pod_names)
  local block_file
  local block_hash
  block_file="$(mktemp)"
  build_hosts_block "${ingress_ip}" "${pod_names[@]}" > "${block_file}"
  block_hash="$(sha256sum "${block_file}" | awk '{print $1}')"

  if [[ "${PRINT_ONLY}" -eq 0 && -n "${LAST_BLOCK_HASH}" && "${LAST_BLOCK_HASH}" == "${block_hash}" ]]; then
    rm -f "${block_file}"
    return 0
  fi
  LAST_BLOCK_HASH="${block_hash}"

  if [[ "${PRINT_ONLY}" -eq 1 ]]; then
    cat "${block_file}"
    return 0
  fi

  if [[ "${APPLY_WSL}" -eq 1 ]]; then
    upsert_unix_hosts_block "${WSL_HOSTS_FILE}" "${block_file}"
  fi
  if [[ "${APPLY_WINDOWS}" -eq 1 ]]; then
    upsert_windows_hosts_block "${block_file}"
  fi
  rm -f "${block_file}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      [[ $# -ge 2 ]] || die "--namespace requires a value"
      NAMESPACE="$2"
      shift 2
      ;;
    --host-suffix)
      [[ $# -ge 2 ]] || die "--host-suffix requires a value"
      HOST_SUFFIX="$2"
      shift 2
      ;;
    --ingress-name)
      [[ $# -ge 2 ]] || die "--ingress-name requires a value"
      INGRESS_NAME="$2"
      shift 2
      ;;
    --ingress-ip)
      [[ $# -ge 2 ]] || die "--ingress-ip requires a value"
      INGRESS_IP="$2"
      shift 2
      ;;
    --label-selector)
      [[ $# -ge 2 ]] || die "--label-selector requires a value"
      LABEL_SELECTOR="$2"
      shift 2
      ;;
    --apply-wsl-hosts)
      APPLY_WSL=1
      shift
      ;;
    --wsl-hosts-file)
      [[ $# -ge 2 ]] || die "--wsl-hosts-file requires a value"
      WSL_HOSTS_FILE="$2"
      shift 2
      ;;
    --apply-windows-hosts)
      APPLY_WINDOWS=1
      shift
      ;;
    --windows-hosts-file)
      [[ $# -ge 2 ]] || die "--windows-hosts-file requires a value"
      WINDOWS_HOSTS_FILE_WIN="$2"
      shift 2
      ;;
    --print-only)
      PRINT_ONLY=1
      shift
      ;;
    --watch)
      WATCH=1
      shift
      ;;
    --interval-sec)
      [[ $# -ge 2 ]] || die "--interval-sec requires a value"
      INTERVAL_SEC="$2"
      shift 2
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

require_command kubectl

if [[ "${PRINT_ONLY}" -eq 0 && "${APPLY_WSL}" -eq 0 && "${APPLY_WINDOWS}" -eq 0 ]]; then
  PRINT_ONLY=1
  log "No apply option provided. Falling back to --print-only."
fi

if [[ "${WATCH}" -eq 1 ]]; then
  while true; do
    sync_once
    sleep "${INTERVAL_SEC}"
  done
else
  sync_once
fi
