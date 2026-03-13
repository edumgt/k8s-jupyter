# k8s-data-platform-ova

WSL Ubuntu에서 `Packer + Ansible`로 Ubuntu 24 기반 OVA를 만들고, 그 안에 `k3s` 단일 노드 Kubernetes 플랫폼을 올린 뒤 아래 스택을 모두 `Kubernetes manifest` 기준으로 운영하도록 구성한 레포입니다.

- Kubernetes / k3s
- Docker/OCI image build pipeline
- Python 3.12
- Node 22.22
- Ubuntu 24
- Teradata SQL(ANSI SQL)
- MongoDB
- Redis
- Apache Airflow
- Quasar Framework(Vue 3)
- GitLab / GitLab Runner
- Harbor
- Jupyter pod

## 구조 요약

```text
.
├── apps/
│   ├── airflow/          # Airflow 이미지와 DAG
│   ├── backend/          # FastAPI + MongoDB/Redis/Teradata API
│   ├── frontend/         # Quasar(Vue 3) 대시보드
│   └── jupyter/          # JupyterLab 이미지와 샘플 노트북
├── ansible/             # Ubuntu 24 OVA 내부 k3s 호스트 부트스트랩
├── infra/
│   ├── harbor/          # Harbor 연계 가이드
│   └── k8s/
│       ├── base/        # 환경 공통 워크로드 베이스
│       ├── overlays/    # dev / prod 환경별 오버레이
│       └── runner/      # GitLab Runner base + dev/prod 오버레이
├── packer/              # Ubuntu 24 OVA 템플릿
└── scripts/             # OVA 빌드 / k8s 배포 / 검증 스크립트
```

## 아키텍처

```text
WSL Ubuntu
  -> Packer
  -> Ubuntu 24 OVA
  -> Ansible provisioning
  -> k3s single-node host
  -> Kubernetes workloads
     - backend (FastAPI)
     - frontend (Quasar)
     - mongodb
     - redis
     - airflow
     - jupyter
     - per-user jupyter-session pods
     - gitlab
  -> GitLab Runner (k8s executor)
  -> Harbor push
```

## 빠른 시작

### 1. 변수 파일 준비

```bash
cp packer/variables.pkr.hcl.example packer/variables.pkr.hcl
```

`packer/variables.pkr.hcl`에서 다음 값을 환경에 맞게 수정합니다.

- `iso_url`
- `iso_checksum`
- `vmware_workstation_path`
- `ovftool_path_windows`
- `ssh_username`
- `ssh_password`

### 2. OVA 빌드

```bash
bash scripts/run_wsl.sh --skip-export
```

OVA까지 한 번에 생성하려면:

```bash
bash scripts/run_wsl.sh
```

### 3. Kubernetes 플랫폼 적용

```bash
bash scripts/apply_k8s.sh --env dev
```

초기화 후 재배포:

```bash
bash scripts/reset_k8s.sh --env dev
bash scripts/apply_k8s.sh --env dev
```

상태 확인:

```bash
bash scripts/status_k8s.sh --env dev
```

### 4. GitLab Runner 적용

Runner는 `k8s executor` 오버레이로 분리했습니다.

1. dev 또는 prod 환경용 runner overlay를 선택합니다.
2. 다음 명령으로 runner 리소스를 적용합니다.

```bash
bash scripts/apply_k8s.sh --env dev --with-runner
kubectl scale deployment/gitlab-runner -n data-platform-dev --replicas=1
```

### 5. GitLab Repo 구조

운영 기준 GitLab 프로젝트 구성은 아래처럼 나눕니다.

- `platform-infra`: 현재 repo, OVA / k8s overlay / runner / 운영 문서 담당
- `platform-backend`: backend app 전용 repo
- `platform-frontend`: frontend app 전용 repo
- `platform-airflow`: airflow app 전용 repo
- `platform-jupyter`: jupyter app 전용 repo

app repo 스캐폴드를 생성하려면:

```bash
bash scripts/export_gitlab_repos.sh --force
```

자세한 설명은 [docs/gitlab-repo-layout.md](/home/Kubernetes-OVA-SRE-Archi/docs/gitlab-repo-layout.md#L1) 에 정리했습니다.

### 6. 환경 구조

- `infra/k8s/base`: 공통 manifest 레이어
- `infra/k8s/overlays/dev`: 개발 환경 overlay, namespace `data-platform-dev`
- `infra/k8s/overlays/prod`: 운영 환경 overlay, namespace `data-platform-prod`
- `infra/k8s/runner/base`: runner 공통 레이어
- `infra/k8s/runner/overlays/dev|prod`: 환경별 runner overlay

현재 구조는 `한 VM/한 클러스터에서 한 환경을 선택 배포`하는 기준입니다. 프론트엔드 API URL이 현재 빌드 타임에 고정되어 있으므로, dev와 prod를 같은 단일 VM에 동시에 노출하는 구조까지는 아직 확장하지 않았습니다.

### 7. 주요 NodePort

- Frontend: `30080`
- Backend API: `30081`
- JupyterLab: `30088`
- GitLab Web: `30089`
- Airflow: `30090`
- GitLab SSH: `30224`

## 데모 로그인 정보

스크린샷과 로컬 확인에 사용한 기본 계정/토큰입니다. 실제 환경에서는 overlay 별 secret patch 값을 반드시 변경해야 합니다.

- dev Airflow: `admin` / `admin12345!`
- dev JupyterLab token: `platform123`
- control-plane dashboard: `platform-admin` / `controlplane123!`
- dev GitLab root: `v7Q#2mL!9xC@4pR%8tZ`

## 사용자별 JupyterLab 흐름

1. Frontend `Personal JupyterLab` 카드에서 사용자명을 입력합니다.
2. Frontend가 backend `/api/jupyter/sessions`를 호출합니다.
3. Backend가 현재 namespace에 사용자 전용 Jupyter pod와 NodePort service를 생성합니다.
4. 세션이 `ready`가 되면 Frontend가 같은 호스트의 동적 NodePort URL로 JupyterLab을 엽니다.

이 per-user 세션은 `apps/jupyter` 이미지를 그대로 사용하므로 Python 3.12, JupyterLab, 샘플 notebook이 함께 제공됩니다. 세션 저장공간은 pod 생명주기에 묶인 실습용 ephemeral workspace 입니다.

## UI 캡처

아래 이미지는 k8s 위에 올라간 실제 서비스 화면을 Playwright 컨테이너로 캡처한 결과를 포함하는 자리입니다.

### Frontend Dashboard

![Frontend dashboard](docs/screenshots/frontend-dashboard.png)

### Backend OpenAPI

![Backend OpenAPI](docs/screenshots/backend-openapi.png)

### Control Plane Login

![Control plane login](docs/screenshots/k8s-control-plane-login.png)

### Control Plane Nodes

![Control plane nodes](docs/screenshots/k8s-control-plane-nodes.png)

### Control Plane Pods

![Control plane pods](docs/screenshots/k8s-control-plane-pods.png)

### Airflow

![Airflow home](docs/screenshots/airflow-home.png)

### JupyterLab

![JupyterLab](docs/screenshots/jupyter-lab.png)

### GitLab

![GitLab dashboard](docs/screenshots/gitlab-dashboard.png)

## 기술 스택 설명

기술 스택별 역할과 선택 이유는 [docs/stack-roles.md](/home/Kubernetes-OVA-SRE-Archi/docs/stack-roles.md#L1)에서 자세히 설명합니다.

## 주요 구성 설명

### Backend

- `FastAPI`
- MongoDB / Redis 헬스 체크
- Teradata ANSI SQL 실행용 `/api/teradata/query`
- 샘플 ANSI SQL 카탈로그 제공
- `/api/jupyter/sessions` 로 사용자별 Jupyter pod / service 생성 및 제거
- `/api/control-plane/login`, `/api/control-plane/dashboard` 로 cluster node / pod inventory 제공
- Jupyter / Airflow / GitLab / Harbor 링크 제공

### Frontend

- `Quasar + Vue 3 + Vite`
- 플랫폼 상태 카드, 서비스 링크, 샘플 SQL 뷰
- control-plane login, node inventory, pod inventory 화면 제공
- `Node 22.22` 빌드 스테이지

### Jupyter

- `Python 3.12`
- JupyterLab
- MongoDB / Redis / Teradata Python 드라이버 포함
- PVC 기반 shared notebook workspace
- Frontend 요청으로 생성되는 per-user JupyterLab pod 지원

### Airflow

- `apache/airflow` 기반 커스텀 이미지
- 플랫폼 헬스 체크 DAG 포함

### GitLab / Runner

- GitLab CE는 Kubernetes Deployment + PVC로 배포
- GitLab Runner는 Kubernetes executor 기준 오버레이
- 이미지 빌드는 Docker daemon 대신 `Kaniko` 사용

### Harbor

Harbor는 별도 인프라 또는 사내 공용 레지스트리로 운용하는 것을 기본 가정으로 두고, 이 레포에서는 그 Harbor에 이미지를 push 하도록 구성합니다. 자세한 내용은 [infra/harbor/README.md](/home/Kubernetes-OVA-SRE-Archi/infra/harbor/README.md#L1)를 참고하면 됩니다.

## 파일 포인트

- OVA 템플릿: [packer/k8s-data-platform.pkr.hcl](/home/Kubernetes-OVA-SRE-Archi/packer/k8s-data-platform.pkr.hcl#L1)
- Ansible 플레이북: [ansible/playbook.yml](/home/Kubernetes-OVA-SRE-Archi/ansible/playbook.yml#L1)
- 공통 k8s 베이스: [infra/k8s/base/kustomization.yaml](/home/Kubernetes-OVA-SRE-Archi/infra/k8s/base/kustomization.yaml#L1)
- dev 오버레이: [infra/k8s/overlays/dev/kustomization.yaml](/home/Kubernetes-OVA-SRE-Archi/infra/k8s/overlays/dev/kustomization.yaml#L1)
- prod 오버레이: [infra/k8s/overlays/prod/kustomization.yaml](/home/Kubernetes-OVA-SRE-Archi/infra/k8s/overlays/prod/kustomization.yaml#L1)
- Runner base: [infra/k8s/runner/base/kustomization.yaml](/home/Kubernetes-OVA-SRE-Archi/infra/k8s/runner/base/kustomization.yaml#L1)
- Runner dev overlay: [infra/k8s/runner/overlays/dev/kustomization.yaml](/home/Kubernetes-OVA-SRE-Archi/infra/k8s/runner/overlays/dev/kustomization.yaml#L1)
- Runner prod overlay: [infra/k8s/runner/overlays/prod/kustomization.yaml](/home/Kubernetes-OVA-SRE-Archi/infra/k8s/runner/overlays/prod/kustomization.yaml#L1)
- GitLab repo 구성 문서: [docs/gitlab-repo-layout.md](/home/Kubernetes-OVA-SRE-Archi/docs/gitlab-repo-layout.md#L1)
- GitLab CI: [.gitlab-ci.yml](/home/Kubernetes-OVA-SRE-Archi/.gitlab-ci.yml#L1)

## 참고

- 이 레포의 runtime/deploy/ops 기준은 `Kubernetes` 입니다.
- 실행 기준 환경은 `dev` 와 `prod` overlay 이며, 스크립트 기본값은 `dev` 입니다.
- 이전 `docker compose` 기반 실행 경로와 단일 호스트 서비스 설정은 제거했습니다.
- Teradata 연결 정보가 없으면 backend는 mock 모드로 응답합니다.
