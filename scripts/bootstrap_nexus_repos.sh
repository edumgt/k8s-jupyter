#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-data-platform-dev}"
NEXUS_URL="${NEXUS_URL:-http://127.0.0.1:30091}"
TARGET_PASSWORD="${TARGET_PASSWORD:-nexus123!}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash scripts/bootstrap_nexus_repos.sh [options]

Options:
  --namespace <name>       Kubernetes namespace where Nexus is deployed.
  --nexus-url <url>        Reachable Nexus base URL. Defaults to http://127.0.0.1:30091.
  --target-password <pw>   Password to set for the admin account after bootstrap.
  --dry-run                Print API calls without executing them.
  -h, --help               Show this help.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
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

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

repo_exists() {
  local name="$1"
  curl -fsS -u "admin:${TARGET_PASSWORD}" "${NEXUS_URL}/service/rest/v1/repositories" | jq -e --arg name "${name}" '.[] | select(.name == $name)' >/dev/null
}

create_repo() {
  local endpoint="$1"
  local name="$2"
  local payload="$3"

  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '+ POST %s/service/rest/v1/repositories/%s\n' "${NEXUS_URL}" "${endpoint}"
    return 0
  fi

  if repo_exists "${name}"; then
    return 0
  fi

  curl -fsS -u "admin:${TARGET_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -X POST \
    "${NEXUS_URL}/service/rest/v1/repositories/${endpoint}" \
    -d "${payload}" >/dev/null
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      [[ $# -ge 2 ]] || die "--namespace requires a value"
      NAMESPACE="$2"
      shift 2
      ;;
    --nexus-url)
      [[ $# -ge 2 ]] || die "--nexus-url requires a value"
      NEXUS_URL="$2"
      shift 2
      ;;
    --target-password)
      [[ $# -ge 2 ]] || die "--target-password requires a value"
      TARGET_PASSWORD="$2"
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
      die "Unknown option: $1"
      ;;
  esac
done

require_command kubectl
require_command curl
require_command jq

run_cmd kubectl rollout status deployment/nexus -n "${NAMESPACE}" --timeout=900s
pod_name="$(kubectl get pod -n "${NAMESPACE}" -l app=nexus -o jsonpath='{.items[0].metadata.name}')"
[[ -n "${pod_name}" ]] || die "Unable to find Nexus pod in namespace ${NAMESPACE}"

if [[ "${DRY_RUN}" == "1" ]]; then
  initial_password='dry-run-password'
else
  initial_password="$(kubectl exec -n "${NAMESPACE}" "${pod_name}" -- cat /nexus-data/admin.password 2>/dev/null || true)"
  [[ -n "${initial_password}" ]] || initial_password="${TARGET_PASSWORD}"
fi

if [[ "${DRY_RUN}" != "1" ]]; then
  for _ in $(seq 1 120); do
    if curl -fsS "${NEXUS_URL}/service/rest/v1/status" >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done

  if ! curl -fsS -u "admin:${TARGET_PASSWORD}" "${NEXUS_URL}/service/rest/v1/status" >/dev/null 2>&1; then
    curl -fsS -u "admin:${initial_password}" \
      -H 'Content-Type: text/plain' \
      -X PUT \
      "${NEXUS_URL}/service/rest/v1/security/users/admin/change-password" \
      --data "${TARGET_PASSWORD}" >/dev/null
  fi
fi

create_repo "raw/hosted" "offline-bundle" '{
  "name": "offline-bundle",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "ALLOW"
  }
}'

create_repo "npm/proxy" "npm-proxy" '{
  "name": "npm-proxy",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "https://registry.npmjs.org",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true
  }
}'

create_repo "npm/hosted" "npm-hosted" '{
  "name": "npm-hosted",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "ALLOW_ONCE"
  }
}'

create_repo "npm/group" "npm-all" '{
  "name": "npm-all",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "group": {
    "memberNames": ["npm-hosted", "npm-proxy"]
  }
}'

create_repo "pypi/proxy" "pypi-proxy" '{
  "name": "pypi-proxy",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "https://pypi.org",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true
  }
}'

create_repo "pypi/hosted" "pypi-hosted" '{
  "name": "pypi-hosted",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "ALLOW_ONCE"
  }
}'

create_repo "pypi/group" "pypi-all" '{
  "name": "pypi-all",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "group": {
    "memberNames": ["pypi-hosted", "pypi-proxy"]
  }
}'

printf 'Nexus repositories are ready.\n'
printf 'PyPI group: %s/repository/pypi-all/simple\n' "${NEXUS_URL}"
printf 'npm group:  %s/repository/npm-all/\n' "${NEXUS_URL}"
