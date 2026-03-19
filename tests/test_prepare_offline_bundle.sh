#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

record_pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf 'ok - %s\n' "$1"
}

record_fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf 'not ok - %s\n' "$1" >&2
}

assert_file_exists() {
  [[ -f "$1" ]] || {
    printf 'expected file to exist: %s\n' "$1" >&2
    return 1
  }
}

assert_dir_has_files() {
  local path="$1"

  find "${path}" -maxdepth 1 -type f | grep -q . || {
    printf 'expected directory to contain files: %s\n' "${path}" >&2
    return 1
  }
}

make_fixture_repo() {
  local target="$1"

  mkdir -p "${target}/scripts" "${target}/scripts/lib" "${target}/apps" "${target}/infra" "${target}/docs"
  cp "${REPO_ROOT}/scripts/prepare_offline_bundle.sh" "${target}/scripts/prepare_offline_bundle.sh"
  cp "${REPO_ROOT}/scripts/import_offline_bundle.sh" "${target}/scripts/import_offline_bundle.sh"
  cp "${REPO_ROOT}/scripts/lib/kubernetes_runtime.sh" "${target}/scripts/lib/kubernetes_runtime.sh"
  cp "${REPO_ROOT}/scripts/apply_k8s.sh" "${target}/scripts/apply_k8s.sh"
  cp "${REPO_ROOT}/scripts/reset_k8s.sh" "${target}/scripts/reset_k8s.sh"
  cp "${REPO_ROOT}/scripts/status_k8s.sh" "${target}/scripts/status_k8s.sh"
  cp "${REPO_ROOT}/scripts/healthcheck.sh" "${target}/scripts/healthcheck.sh"
  cp "${REPO_ROOT}/scripts/verify.sh" "${target}/scripts/verify.sh"
  cp "${REPO_ROOT}/scripts/verify_nexus_dependencies.sh" "${target}/scripts/verify_nexus_dependencies.sh"
  cp "${REPO_ROOT}/scripts/apply_offline_suite.sh" "${target}/scripts/apply_offline_suite.sh"
  cp "${REPO_ROOT}/scripts/audit_registry_scope.sh" "${target}/scripts/audit_registry_scope.sh"
  cp "${REPO_ROOT}/scripts/bootstrap_nexus_repos.sh" "${target}/scripts/bootstrap_nexus_repos.sh"
  cp "${REPO_ROOT}/scripts/prime_nexus_caches.sh" "${target}/scripts/prime_nexus_caches.sh"
  cp "${REPO_ROOT}/scripts/setup_nexus_offline.sh" "${target}/scripts/setup_nexus_offline.sh"
  cp "${REPO_ROOT}/scripts/frontend_dev_setup.sh" "${target}/scripts/frontend_dev_setup.sh"
  cp "${REPO_ROOT}/scripts/run_frontend_dev.sh" "${target}/scripts/run_frontend_dev.sh"
  cp "${REPO_ROOT}/scripts/run_frontend_build.sh" "${target}/scripts/run_frontend_build.sh"
  cp "${REPO_ROOT}/scripts/generate_join_command.sh" "${target}/scripts/generate_join_command.sh"
  cp "${REPO_ROOT}/scripts/join_worker_node.sh" "${target}/scripts/join_worker_node.sh"
  cp "${REPO_ROOT}/scripts/configure_multinode_cluster.sh" "${target}/scripts/configure_multinode_cluster.sh"
  chmod +x "${target}/scripts/"*.sh

  mkdir -p "${target}/apps/backend" "${target}/apps/jupyter" "${target}/apps/airflow" "${target}/apps/frontend"
  printf 'fastapi\n' > "${target}/apps/backend/requirements.txt"
  printf 'jupyterlab\n' > "${target}/apps/jupyter/requirements.txt"
  printf 'apache-airflow\n' > "${target}/apps/airflow/requirements.txt"
  printf '{\"name\":\"frontend\",\"private\":true}\n' > "${target}/apps/frontend/package.json"

  cp -R "${REPO_ROOT}/infra/k8s" "${target}/infra/"
  cp "${REPO_ROOT}/docs/runbook.md" "${target}/docs/runbook.md"
  cp "${REPO_ROOT}/docs/sre-checklist.md" "${target}/docs/sre-checklist.md"
  cp "${REPO_ROOT}/docs/stack-roles.md" "${target}/docs/stack-roles.md"
  cp "${REPO_ROOT}/docs/gitlab-repo-layout.md" "${target}/docs/gitlab-repo-layout.md"
  cp "${REPO_ROOT}/docs/offline-repository.md" "${target}/docs/offline-repository.md"
  cp "${REPO_ROOT}/README.md" "${target}/README.md"
}

test_prepare_offline_bundle_reuses_archives_and_copies_k8s_assets() (
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT

  make_fixture_repo "${tmp_dir}"
  mkdir -p "${tmp_dir}/.tmp-k8s-images" "${tmp_dir}/bin"
  printf 'fake-image-archive\n' > "${tmp_dir}/.tmp-k8s-images/platform-backend.tar"

  cat > "${tmp_dir}/bin/python3" <<'EOF'
#!/usr/bin/env bash
dest=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      dest="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "${dest}"
printf 'wheel-placeholder\n' > "${dest}/offline-placeholder.whl"
EOF

  cat > "${tmp_dir}/bin/npm" <<'EOF'
#!/usr/bin/env bash
cache_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cache)
      cache_dir="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "${cache_dir}"
printf '{\"lockfileVersion\":3}\n' > package-lock.json
EOF

  chmod +x "${tmp_dir}/bin/python3" "${tmp_dir}/bin/npm"
  PATH="${tmp_dir}/bin:${PATH}" bash "${tmp_dir}/scripts/prepare_offline_bundle.sh" \
    --out-dir "${tmp_dir}/dist/offline-bundle" \
    --skip-images

  assert_file_exists "${tmp_dir}/dist/offline-bundle/images/platform-backend.tar"
  assert_dir_has_files "${tmp_dir}/dist/offline-bundle/wheels/backend"
  assert_file_exists "${tmp_dir}/dist/offline-bundle/frontend-package-lock.json"
  assert_file_exists "${tmp_dir}/dist/offline-bundle/k8s/infra/k8s/base/kustomization.yaml"
  assert_file_exists "${tmp_dir}/dist/offline-bundle/k8s/scripts/import_offline_bundle.sh"
  assert_file_exists "${tmp_dir}/dist/offline-bundle/k8s/scripts/lib/kubernetes_runtime.sh"
  assert_file_exists "${tmp_dir}/dist/offline-bundle/k8s/scripts/setup_nexus_offline.sh"
  assert_file_exists "${tmp_dir}/dist/offline-bundle/k8s/scripts/verify_nexus_dependencies.sh"
  assert_file_exists "${tmp_dir}/dist/offline-bundle/k8s/docs/runbook.md"
  assert_file_exists "${tmp_dir}/dist/offline-bundle/k8s/docs/offline-repository.md"
  assert_file_exists "${tmp_dir}/dist/offline-bundle/k8s/README.offline.md"
)

run_test() {
  local name="$1"

  if "${name}"; then
    record_pass "${name}"
  else
    record_fail "${name}"
  fi
}

run_test test_prepare_offline_bundle_reuses_archives_and_copies_k8s_assets

if [[ "${TESTS_FAILED}" -ne 0 ]]; then
  printf '%s tests failed\n' "${TESTS_FAILED}" >&2
  exit 1
fi

printf '%s tests passed\n' "${TESTS_PASSED}"
