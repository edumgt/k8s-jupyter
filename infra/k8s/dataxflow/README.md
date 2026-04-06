# Dataxflow K8s (Dev)

`dataxflow.local` 환경을 위한 ELT Framework pod 구성입니다.

## 구성 요소
- Backend: FastAPI(Python 3.12, uvicorn)
- Frontend: Vue3 + Quasar SPA(Node 22 build runtime image)
- Infra: MongoDB, Redis
- Scheduler: Airflow
- Teradata mock: PostgreSQL (bootstrap/test 용)

소스 경로:
- Backend: `apps/backend`
- Frontend: `apps/dataxflow-frontend`

## 적용
```bash
kubectl apply -k infra/k8s/dataxflow/overlays/dev
```

## URL
- Frontend: `http://dataxflow.local`
- Backend: `http://api.dataxflow.local/docs`
- Airflow: `http://airflow.dataxflow.local`

## hosts 예시
`<INGRESS_LB_IP>`를 ingress external IP로 교체하세요.

```text
<INGRESS_LB_IP> dataxflow.local api.dataxflow.local airflow.dataxflow.local
```

자동 반영(WSL/Windows):

```bash
chmod +x scripts/sync_dataxflow_hosts.sh
scripts/sync_dataxflow_hosts.sh --apply-wsl-hosts
scripts/sync_dataxflow_hosts.sh --apply-windows-hosts
```

## Teradata bootstrap 테스트
Backend 관리자 API 사용:
- dry run: `POST /api/admin/teradata/bootstrap` with `{"dry_run": true}`
- execute: `POST /api/admin/teradata/bootstrap` with `{"dry_run": false}`

기본 dev 구성은 PostgreSQL mock(`teradata-mock-postgres`)을 Teradata 유사 DB로 사용합니다.

## Image PullBackOff 발생 시
Harbor가 `http`(insecure)인 환경에서 일부 노드가 `https`로만 시도하면 Pull 실패가 날 수 있습니다.
이 경우 이미지를 노드에 직접 동기화하면 즉시 복구됩니다.

```bash
bash scripts/sync_docker_image_to_vms.sh \
  --image-ref harbor.local/data-platform/k8s-data-platform-frontend:latest \
  --ssh-user ubuntu --ssh-password ubuntu \
  --control-plane-ip 192.168.56.10 --worker1-ip 192.168.56.11 \
  --worker2-ip 192.168.56.12 --worker3-ip 192.168.56.13

bash scripts/sync_docker_image_to_vms.sh \
  --image-ref harbor.local/data-platform/platform-redis:7-alpine \
  --ssh-user ubuntu --ssh-password ubuntu \
  --control-plane-ip 192.168.56.10 --worker1-ip 192.168.56.11 \
  --worker2-ip 192.168.56.12 --worker3-ip 192.168.56.13
```
