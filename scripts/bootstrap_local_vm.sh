#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/tmp/k8s-data-platform-src}"

usage() {
  cat <<'EOF'
Usage: bash scripts/bootstrap_local_vm.sh [options]

Options:
  --repo-root <path>  Repository payload root inside the VM.
  -h, --help          Show this help.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      [[ $# -ge 2 ]] || die "--repo-root requires a value"
      REPO_ROOT="$2"
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

[[ -d "${REPO_ROOT}/ansible" ]] || die "ansible directory not found under ${REPO_ROOT}"
[[ -f "${REPO_ROOT}/ansible/playbook.yml" ]] || die "playbook not found: ${REPO_ROOT}/ansible/playbook.yml"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ansible
ansible-playbook -i 'localhost,' -c local "${REPO_ROOT}/ansible/playbook.yml"
