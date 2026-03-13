#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/dist/gitlab-repos}"
FORCE=0

usage() {
  cat <<'EOF'
Usage: bash scripts/export_gitlab_repos.sh [options]

Options:
  --out-dir <path>  Directory where the GitLab repo scaffolds will be written.
  --force           Remove an existing output directory before exporting.
  -h, --help        Show this help.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      [[ $# -ge 2 ]] || die "--out-dir requires a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --force)
      FORCE=1
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

clean_output_dir() {
  if [[ -d "${OUT_DIR}" ]]; then
    if [[ "${FORCE}" == "1" ]]; then
      rm -rf "${OUT_DIR}"
    else
      die "Output directory already exists: ${OUT_DIR} (use --force to replace it)"
    fi
  fi

  mkdir -p "${OUT_DIR}"
}

copy_app_contents() {
  local app_name="$1"
  local repo_dir="$2"

  mkdir -p "${repo_dir}"
  cp -R "${ROOT_DIR}/apps/${app_name}/." "${repo_dir}/"
  rm -rf "${repo_dir}/__pycache__" "${repo_dir}/node_modules" "${repo_dir}/dist"
}

write_repo_gitignore() {
  local repo_dir="$1"

  cat > "${repo_dir}/.gitignore" <<'EOF'
__pycache__/
.pytest_cache/
.mypy_cache/
.venv/
venv/
dist/
node_modules/
.DS_Store
kubeconfig
EOF
}

write_backend_ci() {
  local repo_dir="$1"

  cat > "${repo_dir}/.gitlab-ci.yml" <<'EOF'
stages:
  - test
  - build
  - deploy

python_sanity:
  stage: test
  image: python:3.12
  script:
    - python -m compileall app

kaniko_build:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:v1.23.2-debug
    entrypoint: [""]
  script:
    - export IMAGE_NAME="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/backend"
    - mkdir -p /kaniko/.docker
    - >
      printf '{"auths":{"%s":{"username":"%s","password":"%s"}}}'
      "$HARBOR_REGISTRY" "$HARBOR_USER" "$HARBOR_PASSWORD" > /kaniko/.docker/config.json
    - /kaniko/executor --context "${CI_PROJECT_DIR}" --dockerfile "${CI_PROJECT_DIR}/Dockerfile" --destination "${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}" --destination "${IMAGE_NAME}:latest"

deploy_backend:
  stage: deploy
  image: bitnami/kubectl:1.32
  needs:
    - kaniko_build
  script:
    - export IMAGE_NAME="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/backend"
    - export DEPLOY_ENV="${DEPLOY_ENV:-dev}"
    - export DEPLOY_NAMESPACE="data-platform-${DEPLOY_ENV}"
    - echo "$KUBECONFIG_B64" | base64 -d > kubeconfig
    - export KUBECONFIG="${CI_PROJECT_DIR}/kubeconfig"
    - kubectl set image deployment/backend backend="${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}" -n "${DEPLOY_NAMESPACE}"
    - kubectl rollout status deployment/backend -n "${DEPLOY_NAMESPACE}" --timeout=180s
EOF
}

write_frontend_ci() {
  local repo_dir="$1"

  cat > "${repo_dir}/.gitlab-ci.yml" <<'EOF'
stages:
  - build
  - deploy

kaniko_build:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:v1.23.2-debug
    entrypoint: [""]
  script:
    - export IMAGE_NAME="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/frontend"
    - export VITE_API_BASE_URL="${VITE_API_BASE_URL:-http://localhost:30081}"
    - mkdir -p /kaniko/.docker
    - >
      printf '{"auths":{"%s":{"username":"%s","password":"%s"}}}'
      "$HARBOR_REGISTRY" "$HARBOR_USER" "$HARBOR_PASSWORD" > /kaniko/.docker/config.json
    - /kaniko/executor --context "${CI_PROJECT_DIR}" --dockerfile "${CI_PROJECT_DIR}/Dockerfile" --build-arg "VITE_API_BASE_URL=${VITE_API_BASE_URL}" --destination "${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}" --destination "${IMAGE_NAME}:latest"

deploy_frontend:
  stage: deploy
  image: bitnami/kubectl:1.32
  needs:
    - kaniko_build
  script:
    - export IMAGE_NAME="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/frontend"
    - export DEPLOY_ENV="${DEPLOY_ENV:-dev}"
    - export DEPLOY_NAMESPACE="data-platform-${DEPLOY_ENV}"
    - echo "$KUBECONFIG_B64" | base64 -d > kubeconfig
    - export KUBECONFIG="${CI_PROJECT_DIR}/kubeconfig"
    - kubectl set image deployment/frontend frontend="${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}" -n "${DEPLOY_NAMESPACE}"
    - kubectl rollout status deployment/frontend -n "${DEPLOY_NAMESPACE}" --timeout=180s
EOF
}

write_airflow_ci() {
  local repo_dir="$1"

  cat > "${repo_dir}/.gitlab-ci.yml" <<'EOF'
stages:
  - test
  - build
  - deploy

python_sanity:
  stage: test
  image: python:3.12
  script:
    - python -m compileall dags

kaniko_build:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:v1.23.2-debug
    entrypoint: [""]
  script:
    - export IMAGE_NAME="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/airflow"
    - mkdir -p /kaniko/.docker
    - >
      printf '{"auths":{"%s":{"username":"%s","password":"%s"}}}'
      "$HARBOR_REGISTRY" "$HARBOR_USER" "$HARBOR_PASSWORD" > /kaniko/.docker/config.json
    - /kaniko/executor --context "${CI_PROJECT_DIR}" --dockerfile "${CI_PROJECT_DIR}/Dockerfile" --destination "${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}" --destination "${IMAGE_NAME}:latest"

deploy_airflow:
  stage: deploy
  image: bitnami/kubectl:1.32
  needs:
    - kaniko_build
  script:
    - export IMAGE_NAME="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/airflow"
    - export DEPLOY_ENV="${DEPLOY_ENV:-dev}"
    - export DEPLOY_NAMESPACE="data-platform-${DEPLOY_ENV}"
    - echo "$KUBECONFIG_B64" | base64 -d > kubeconfig
    - export KUBECONFIG="${CI_PROJECT_DIR}/kubeconfig"
    - kubectl set image deployment/airflow airflow="${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}" -n "${DEPLOY_NAMESPACE}"
    - kubectl rollout status deployment/airflow -n "${DEPLOY_NAMESPACE}" --timeout=180s
EOF
}

write_jupyter_ci() {
  local repo_dir="$1"

  cat > "${repo_dir}/.gitlab-ci.yml" <<'EOF'
stages:
  - build
  - deploy

kaniko_build:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:v1.23.2-debug
    entrypoint: [""]
  script:
    - export IMAGE_NAME="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/jupyter"
    - mkdir -p /kaniko/.docker
    - >
      printf '{"auths":{"%s":{"username":"%s","password":"%s"}}}'
      "$HARBOR_REGISTRY" "$HARBOR_USER" "$HARBOR_PASSWORD" > /kaniko/.docker/config.json
    - /kaniko/executor --context "${CI_PROJECT_DIR}" --dockerfile "${CI_PROJECT_DIR}/Dockerfile" --destination "${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}" --destination "${IMAGE_NAME}:latest"

deploy_jupyter:
  stage: deploy
  image: bitnami/kubectl:1.32
  needs:
    - kaniko_build
  script:
    - export IMAGE_NAME="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/jupyter"
    - export DEPLOY_ENV="${DEPLOY_ENV:-dev}"
    - export DEPLOY_NAMESPACE="data-platform-${DEPLOY_ENV}"
    - echo "$KUBECONFIG_B64" | base64 -d > kubeconfig
    - export KUBECONFIG="${CI_PROJECT_DIR}/kubeconfig"
    - kubectl set image deployment/jupyter jupyter="${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}" -n "${DEPLOY_NAMESPACE}"
    - kubectl rollout status deployment/jupyter -n "${DEPLOY_NAMESPACE}" --timeout=180s
EOF
}

write_repo_readme() {
  local repo_dir="$1"
  local repo_name="$2"
  local image_name="$3"
  local deployment_name="$4"

  cat > "${repo_dir}/README.md" <<EOF
# ${repo_name}

이 디렉터리는 GitLab 의 개별 app repo 로 push 하는 스캐폴드입니다.

## CI/CD 흐름

- GitLab Runner 가 pipeline 을 실행
- Kaniko 로 Harbor 이미지 빌드/푸시
- \`kubectl set image\` 로 Kubernetes deployment \`${deployment_name}\` 갱신

## 필요한 GitLab CI 변수

- \`HARBOR_REGISTRY\`
- \`HARBOR_PROJECT\`
- \`HARBOR_USER\`
- \`HARBOR_PASSWORD\`
- \`KUBECONFIG_B64\`
- \`DEPLOY_ENV\` (\`dev\` 또는 \`prod\`)

## 배포 대상

- Harbor image: \`${image_name}\`
- Kubernetes deployment: \`${deployment_name}\`
EOF
}

write_root_readme() {
  cat > "${OUT_DIR}/README.md" <<'EOF'
# GitLab Repo Export

이 디렉터리는 app 모듈을 GitLab 의 개별 repo 로 분리하기 위한 산출물입니다.

## 생성되는 repo

- `platform-backend`
- `platform-frontend`
- `platform-airflow`
- `platform-jupyter`

현재 작업 중인 루트 repo 는 `platform-infra` 역할을 맡습니다.
EOF
}

export_backend_repo() {
  local repo_dir="${OUT_DIR}/platform-backend"
  copy_app_contents "backend" "${repo_dir}"
  write_repo_gitignore "${repo_dir}"
  write_backend_ci "${repo_dir}"
  write_repo_readme "${repo_dir}" "platform-backend" '${HARBOR_REGISTRY}/${HARBOR_PROJECT}/backend' "backend"
}

export_frontend_repo() {
  local repo_dir="${OUT_DIR}/platform-frontend"
  copy_app_contents "frontend" "${repo_dir}"
  write_repo_gitignore "${repo_dir}"
  write_frontend_ci "${repo_dir}"
  write_repo_readme "${repo_dir}" "platform-frontend" '${HARBOR_REGISTRY}/${HARBOR_PROJECT}/frontend' "frontend"
}

export_airflow_repo() {
  local repo_dir="${OUT_DIR}/platform-airflow"
  copy_app_contents "airflow" "${repo_dir}"
  write_repo_gitignore "${repo_dir}"
  write_airflow_ci "${repo_dir}"
  write_repo_readme "${repo_dir}" "platform-airflow" '${HARBOR_REGISTRY}/${HARBOR_PROJECT}/airflow' "airflow"
}

export_jupyter_repo() {
  local repo_dir="${OUT_DIR}/platform-jupyter"
  copy_app_contents "jupyter" "${repo_dir}"
  write_repo_gitignore "${repo_dir}"
  write_jupyter_ci "${repo_dir}"
  write_repo_readme "${repo_dir}" "platform-jupyter" '${HARBOR_REGISTRY}/${HARBOR_PROJECT}/jupyter' "jupyter"
}

clean_output_dir
write_root_readme
export_backend_repo
export_frontend_repo
export_airflow_repo
export_jupyter_repo

printf 'Exported GitLab app repos to %s\n' "${OUT_DIR}"
