# FSS Jupyter K8s Blueprint

이 디렉터리는 아래 요구사항을 반영한 K8s 매니페스트 초안입니다.

- namespace 분리: `app`, `dis`, `infra`, `sample`, `unitest`
- ADW 앱:
  - `app/fss-adw-server` (Node 22, Express 5, Socket.io, Mongoose, Redis session)
  - `app/fss-adw-frontend` (Vue3 + Quasar SPA)
- 사용자 Jupyter 동적 라우팅:
  - headless service
  - wildcard ingress
  - named pod 라우팅용 router deployment
- 인프라 서비스:
  - MongoDB (root / CHANGE_ME)
  - Redis (ACL root / CHANGE_ME)

## Apply

```bash
# dev
kubectl apply -k infra/k8s/fss/overlays/dev

# prod
kubectl apply -k infra/k8s/fss/overlays/prod
```

또는 자동 설치 스크립트 사용:

```bash
bash scripts/setup_fss_platform.sh \
  --env dev \
  --metallb-range 192.168.56.77-192.168.56.77 \
  --ingress-lb-ip 192.168.56.77 \
  --harbor-server 192.168.56.72:80 \
  --harbor-username 'robot$dis' \
  --harbor-password '<password>'
```

검증 스크립트:

```bash
bash scripts/verify_fss_vmware_setup.sh
```

`overlays/dev`는 `infra` namespace의 Mongo/Redis PVC 바인딩을 위해 로컬 PV(`local-pv.yaml`)를 포함합니다.

## Dynamic Route Design

고정 ingress/service 하나로 다음 형식을 처리합니다.

- `https://test-user-1234.service.jupyter.platform.local`
- `https://test-user-5678.service.jupyter.platform.local`

동작 방식:

1. wildcard ingress가 `dis/jupyter-pod-router` 로 전달
2. router가 host prefix (`test-user-1234`)를 Pod name으로 해석
3. `http://<pod>.jupyter-named-pod.dis.svc.cluster.local:8888` 로 프록시

### Required Pod Contract

백엔드가 사용자 Pod 생성 시 아래를 보장해야 합니다.

1. Pod 이름: 외부 host prefix와 일치
2. Pod spec:
   - `hostname: <pod-name>`
   - `subdomain: jupyter-named-pod`
3. Label:
   - `app.kubernetes.io/component=user-jupyter`
4. 사용자 PVC mount 및 quota 적용

## Node Migration Notes

Python 기반 Jupyter 관리 로직을 Node 기반으로 전환하기 위해 아래 리소스를 추가했습니다.

- `infra/k8s/fss/base/adw-app.yaml`
  - `fss-adw-server` Deployment/Service/Ingress
  - `fss-adw-frontend` Deployment/Service
  - `fss-adw-server` ServiceAccount + ClusterRole + ClusterRoleBinding
  - 앱 ConfigMap/Secret

백엔드 소스:
- `apps/adw-server-node`

프론트엔드 소스:
- `apps/jupyter-frontend`

## Important Production Notes

`overlays/prod` 의 Mongo/Redis replica 3 패치는 "복제 수"만 올립니다.

- Mongo: 실제 운영 HA는 replica set init 및 health 정책이 추가로 필요
- Redis: 실제 운영 HA는 Sentinel 또는 Redis Cluster 구성이 추가로 필요

24x7 mission critical이 아니라면 단일 인스턴스 유지 정책도 가능합니다.

## Harbor Projects

요구사항에 맞춰 프로젝트를 다음처럼 가정합니다.

- `app`: fss-adw-server, fss-adw-batch 등
- `dis`: 사용자 Jupyter 이미지
- `library`: 공통 인프라 이미지

현재 fss base는 아래 이미지를 사용합니다.

- `harbor.local/library/mongo:8.2.5`
- `harbor.local/library/redis:8.6.1`
- `harbor.local/library/jupyter-pod-router:latest`

## Storage Recommendation

요구사항에서 "Rook-Ceph over NFS"를 고려했지만, 실무적으로는 아래 우선순위를 권장합니다.

1. **권장**: Rook-Ceph + CephFS 동적 PVC (PVC size quota를 스토리지 계층에서 강제)
2. NFS 강제 환경: NFS provisioner + 별도 디렉터리 quota 운영 자동화

`Rook-Ceph NFS`는 "Ceph를 NFS로 export"하는 모델이며, 기존 외부 NFS 위에 Ceph를 얹는 구조와는 다릅니다.

## Verification Examples

```bash
# namespace 확인
kubectl get ns | egrep 'app|dis|infra|sample|unitest'

# wildcard ingress / router
kubectl -n dis get ingress,svc,deploy

# infra
kubectl -n infra get sts,svc,pvc,secret

# 스토리지 검증용 busybox (sample namespace)
kubectl -n sample run io-test --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl -n sample exec -it io-test -- sh
# inside pod:
# df -h
# dd if=/dev/zero of=/tmp/test.bin bs=1M count=1024
```
