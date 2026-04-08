# RFP 기술구현 체크리스트

기준 문서: `20260326-rfp-Rev.1.docx`  
점검일: `2026-04-08`  
상태 기준: `구현됨` / `부분구현` / `미구현`

## 구현 점검표

| No | 요구사항 | 상태 | 근거 | 비고/후속 |
|---|---|---|---|---|
| 1 | K8S 멀티노드 설치/부트스트랩 자동화 | 부분구현 | `scripts/bootstrap_3node_k8s_ova.sh` | 부트스트랩/조인 자동화는 있음. 환경별 운영 완성도는 현장 검증 필요 |
| 2 | K8S `1.35.3` 설치 기준 | 부분구현 | `README.md`(업그레이드 절차), `ansible/roles/kubernetes/defaults/main.yml` | 가이드는 있으나 기본 프로비저닝 값은 `v1.34` |
| 3 | Dynamic route (headless service + named pod + wildcard ingress) | 구현됨 | `infra/k8s/fss/base/dynamic-routing.yaml`, `apps/jupyter-pod-router/server.js` | 요구 시나리오와 구조 일치 |
| 4 | Load Balancer(MetalLB) 설치 | 구현됨 | `scripts/setup_ingress_metallb.sh`, `scripts/setup_k8s_modern_stack.sh` | IP pool/L2Advertisement 자동 적용 |
| 5 | metrics-server 설치 | 구현됨 | `scripts/setup_ingress_metallb.sh`, `scripts/verify_fss_vmware_setup.sh` | APIService 가용성 점검 포함 |
| 6 | Namespace 분리 (`app/dis/infra/sample/unitest`) | 구현됨 | `infra/k8s/fss/base/namespaces.yaml` | 요구 네임스페이스 5개 정의 완료 |
| 7 | Mongo 인프라 (계정/비밀정보 분리, PVC 유지) | 구현됨 | `infra/k8s/fss/base/mongodb.yaml` | Secret + StatefulSet + PVC 템플릿 구성 |
| 8 | Redis 인프라 (ACL root, PVC 유지) | 구현됨 | `infra/k8s/fss/base/redis.yaml` | 요구 ACL(`user root on`) 반영 |
| 9 | 운영 환경 Mongo/Redis 3인스턴스 | 부분구현 | `infra/k8s/fss/overlays/prod/infra-scale-patch.yaml`, `infra/k8s/fss/README.md` | replica 수는 반영, 실운영 HA 구성은 추가 필요 |
| 10 | worker-ml 노드 라벨/어피니티 정책 | 부분구현 | `scripts/templates/fss-office-dev.env.example`, `docs/fss-office-vmware-practice.md` | 운영 가이드는 있으나 FSS 기본 매니페스트 강제 정책은 제한적 |
| 11 | Rook-Ceph over NFS | 미구현 | `docs/fss-jupyter-k8s-implementation.md`, `infra/k8s/fss/README.md` | 검토/권고 문서만 존재, 배포 매니페스트 없음 |
| 12 | ADW Backend (Node22, Express5, Socket.io, Mongoose, Redis session) | 구현됨 | `apps/adw-server-node/package.json`, `apps/adw-server-node/src/server.js` | 요구 스택 충족 |
| 13 | 사용자 신청/승인 후 PVC 생성 및 개인 Pod 실행 | 구현됨 | `apps/adw-server-node/src/services/governanceService.js`, `apps/adw-server-node/src/services/k8sService.js` | 리소스 승인 -> PVC 생성 -> Pod 생성 흐름 구현 |
| 14 | 개인 Pod 연결 시 본인 확인 후 동적 URL 리다이렉트 | 구현됨 | `apps/adw-server-node/src/server.js`, `apps/adw-server-node/src/services/sessionService.js` | username 접근 제어 + dynamic host 반환 |
| 15 | Snapshot publish 실동작 (ADW Node 백엔드) | 부분구현 | `apps/adw-server-node/src/services/sessionService.js`, `apps/adw-server-node/README.md` | 엔드포인트는 있으나 publish 로직은 미구현 명시 |
| 16 | ELT Backend (Python 3.12, FastAPI, Uvicorn) | 구현됨 | `apps/backend/requirements.txt`, `apps/backend/Dockerfile`, `apps/backend/app/main.py` | 핵심 백엔드 스택 충족 |
| 17 | ELT Backend SQLAlchemy 사용 | 구현됨 | `apps/backend/requirements.txt`, `apps/backend/app/services/teradata.py` | PostgreSQL mock 질의 경로를 SQLAlchemy 기반으로 전환 |
| 18 | ELT Frontend (Node22, Vue3, Quasar SPA) | 구현됨 | `apps/dataxflow-frontend/package.json` | 요구 스택 충족 |
| 19 | ELT Frontend Axios/Chartjs | 구현됨 | `apps/dataxflow-frontend/package.json`, `apps/dataxflow-frontend/src/App.vue` | 업무 포털 화면에서 axios 기반 API 호출 및 배치주기/실행시간 Chart.js 시각화 적용 |
| 20 | ELT 배치업무(잡 생성/프로시저/스케줄링 연동) | 구현됨 | `apps/backend/app/services/dataxflow_jobs.py`, `apps/backend/app/main.py`, `apps/dataxflow-frontend/src/App.vue` | 로그인 후 배치잡 등록/수정, 테스트 실행, 프로시저 컴파일, Airflow 등록, 실행 이력/통계 UI 및 API 연동 완료 |
| 21 | 설치/운영 가이드 문서화 | 구현됨 | `docs/fss-office-vmware-practice.md`, `docs/fss-office-server-map.md`, `infra/k8s/fss/README.md` | 반입 전/후 체크포인트 문서화 |
| 22 | 산출물(manifest/yaml) 정리 및 전달 준비 | 부분구현 | `infra/k8s/fss/*`, `scripts/setup_fss_platform.sh`, `scripts/prime_nexus_from_env.sh`, `scripts/verify_nexus_dependencies.sh` | 매니페스트/스크립트 정리 + Nexus(PyPI/npm) 의존성 프라이밍/검증은 완료. 외부 Git push 자동화는 별도 운영 절차 필요 |

## 우선 조치 항목

- [ ] P1: `Rook-Ceph over NFS` 또는 대체 스토리지 전략 확정 후 실제 배포 매니페스트 추가
- [ ] P1: Ansible 기본값을 `1.35.3` 요구와 일치하도록 버전 핀 전략 확정
- [x] P1: ELT 스택 요구서 기준으로 `SQLAlchemy`, `Axios`, `Chartjs` 적용 여부 확정(적용 완료, Nexus seed 목록 반영)
- [x] P1: Nexus(PyPI/npm) 의존성 캐시 프라이밍/검증 실행 (`prime_nexus_from_env.sh`, `verify_nexus_dependencies.sh`)
- [x] P2: ELT 배치잡 관리(잡 등록/변경/스케줄/실행 이력) 기능 갭 상세화 및 API/UI 보강
- [ ] P2: ADW Node 백엔드의 snapshot publish 실구현 완료
- [ ] P3: worker-ml 스케줄링 정책(affinity/taint/toleration/nodeSelector) 표준 매니페스트화
- [ ] P3: 반입 후 전환(DNS, Harbor secure, NFS endpoint) 검증 결과를 운영 체크리스트에 추가
