# Offline Artifact Repository

이 레포의 현재 구조에서 `Harbor` 는 플랫폼 공통 이미지를 미러링하는 용도가 아니라 `per-user Jupyter snapshot` 전용입니다. 즉, `docker.io/edumgt/*` 로 push 한 app/runtime 이미지는 Harbor 와 1:1 동기화되지 않습니다.

## Airflow 역할

- Airflow 는 현재 핵심 런타임 의존성이 아니라 `platform_health_check` DAG 로 backend, frontend, jupyter 상태를 주기적으로 확인하는 샘플 오케스트레이터입니다.
- Jupyter sandbox, GitLab repo 분리, offline bundle, snapshot/restore 경로는 Airflow 없이도 동작합니다.
- 폐쇄망 최소 구성에서는 Airflow 를 빼고 backend + frontend one-pod profile 을 먼저 올리는 쪽이 더 단순합니다.

## 추천 저장소

이 레포는 `Python 3.12` 패키지와 `npm` 패키지를 모두 다뤄야 하므로 `devpi` 단독보다 `Nexus Repository` 가 더 잘 맞습니다.

- PyPI proxy/group 으로 backend, jupyter, airflow wheel warm-up 가능
- npm proxy/group 으로 frontend build cache warm-up 가능
- raw hosted repository 로 offline bundle 자체를 함께 적재 가능
- Harbor 는 기존대로 Jupyter snapshot 전용으로 유지 가능

공식 문서:

- Sonatype Nexus Repository formats: https://help.sonatype.com/en/repository-formats.html
- PyPI repositories in Nexus: https://help.sonatype.com/en/pypi-repositories.html
- npm repositories in Nexus: https://help.sonatype.com/en/npm-repositories.html
- Nexus Docker image: https://hub.docker.com/r/sonatype/nexus3

## 설치 순서

기본 stack 에는 `infra/k8s/base/nexus.yaml` 이 포함되어 있습니다.

```bash
bash scripts/apply_k8s.sh --env dev
bash scripts/setup_nexus_offline.sh --namespace data-platform-dev --nexus-url http://127.0.0.1:30091
```

생성되는 주요 endpoint:

- `http://127.0.0.1:30091/repository/pypi-all/simple`
- `http://127.0.0.1:30091/repository/npm-all/`
- `http://127.0.0.1:30091/repository/offline-bundle/`

## 폐쇄망 one-pod app profile

backend 와 frontend 를 하나의 pod 로 묶은 최소 profile 은 별도 kustomization 으로 제공합니다.

```bash
bash scripts/apply_offline_suite.sh
```

주요 포트:

- frontend: `31080`
- backend: `31081`
- jupyter: `31088`
- nexus: `31091`

이 profile 은 `Airflow` 를 의도적으로 제외하고, `MongoDB + Redis + Jupyter PVC + Nexus` 만 함께 올립니다.
