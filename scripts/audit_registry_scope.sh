#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

dockerhub_refs="$(rg -o 'docker\.io/edumgt/[^\" ]+' \
  "${ROOT_DIR}/infra/k8s" \
  "${ROOT_DIR}/apps" \
  "${ROOT_DIR}/scripts/build_k8s_images.sh" \
  -g '!**/node_modules/**' | sort -u)"

harbor_image_refs="$(rg -o 'harbor\.local/[^\" ]+' \
  "${ROOT_DIR}/infra" \
  "${ROOT_DIR}/apps" \
  "${ROOT_DIR}/docs" \
  -g '!**/node_modules/**' | sort -u || true)"

printf 'Docker Hub image refs used by workloads/build scripts:\n%s\n\n' "${dockerhub_refs}"
printf 'Harbor refs found in code/docs:\n%s\n\n' "${harbor_image_refs:-<none>}"

if rg -n 'image:\s*harbor\.local' "${ROOT_DIR}/infra/k8s" "${ROOT_DIR}/apps" -g '!**/node_modules/**' >/dev/null; then
  printf 'Result: some workloads pull directly from Harbor.\n'
else
  printf 'Result: Docker Hub pushes are not mirrored 1:1 into Harbor in this repo.\n'
  printf 'Harbor is configured for per-user Jupyter snapshot images only.\n'
fi
