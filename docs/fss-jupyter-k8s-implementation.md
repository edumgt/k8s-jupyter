# FSS Jupyter K8s 구현 메모

이 문서는 다음 요구사항 구현 시 핵심 의사결정을 정리합니다.

## 1. K8S Dynamic Route

요구:

- 사용자별 named pod 생성 (`test-user-1234`, `test-user-5678`)
- 외부 URL host로 특정 pod에 라우팅
- pod마다 서비스/인그레스 쌍을 추가 생성하지 않음

### 구현 방식

1. `dis` namespace에 headless service (`clusterIP: None`) 생성
2. wildcard ingress (`*.service.jupyter.platform.local`)는 고정 1개만 사용
3. ingress backend는 `jupyter-pod-router` 서비스
4. router가 host prefix를 pod 이름으로 해석하여 headless DNS로 프록시

## 2. Rook-Ceph over NFS 검토

요구사항에 있는 링크의 CephNFS는 "CephFS를 NFS로 export"하는 방식입니다.

- 즉, 기존 외부 NFS를 backing storage로 사용하는 개념과 다릅니다.
- 사용자별 PVC 용량 제한이 중요하면 **Rook-Ceph + CephFS 동적 PVC**가 더 직관적입니다.

### 제안

1. 1차: CephFS 동적 PVC로 사용자 quota 검증
2. NFS가 강제라면: NFS provisioner + 파일시스템 quota 자동화 스크립트 설계

## 3. MetalLB

Bare metal/VM 환경에서 단일 Cluster 외부 IP 제공 목적에는 MetalLB가 표준 선택지입니다.

대안:

- kube-vip (L2/ARP 기반 단순 VIP)

## 4. Infra (Mongo/Redis)

요구를 반영하여 다음을 manifest에 반영했습니다.

- namespace: `infra`
- Mongo 8.2.5 (root / CHANGE_ME)
- Redis 8.6.1 + ACL config (`user root on >CHANGE_ME`)
- secret 분리
- PVC 유지형 StatefulSet

운영 복제 구성은 정책 결정 필요:

- Mongo 3 replica set 초기화
- Redis Sentinel 또는 Redis Cluster

## 5. 소스베이스 변경 포인트 (서버)

기존 docker 기반 서버를 k8s로 전환할 때 최소 변경 포인트:

1. 사용자 pod 생성 시 `hostname/subdomain` 지정
2. per-user NodePort service 제거
3. connect URL을 wildcard host 기반으로 생성
4. 사용자 PVC를 storage class 기반 동적 생성 + 요청 용량 반영
5. 승인 워크플로우와 pod 생성 로직 분리

