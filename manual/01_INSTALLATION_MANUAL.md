# 설치 매뉴얼 (고객사 납품용)

## 1. 목적

본 문서는 인터넷이 없는 환경(air-gap)에서 플랫폼을 설치/검증하기 위한 표준 절차를 제공합니다.

## 2. 구성 개요

- OS/가상화: Ubuntu 24 기반 OVA, VMware Workstation
- 클러스터: kubeadm Kubernetes (3-node)
- 배포 방식: Kubernetes manifest + kustomize overlay
- 주요 서비스:
  - Frontend: `http://platform.local`
  - Backend Docs: `http://platform.local/docs`
  - Jupyter: `http://jupyter.platform.local/lab`
  - GitLab: `http://gitlab.platform.local`
  - Airflow: `http://airflow.platform.local`
  - Nexus: `http://nexus.platform.local`

## 3. 사전 준비

### 3.1 필수 산출물

1. `k8s-data-platform.ova`
2. `k8s-worker-1.ova`
3. `k8s-worker-2.ova`
4. 설치 저장소(본 repo) 또는 최소 실행 스크립트 세트

### 3.2 네트워크 기준값(권장)

1. Subnet: `<YOUR_SUBNET>/24`
2. Gateway: `<YOUR_GATEWAY_IP>`
3. Control-plane: `<YOUR_MASTER_IP>`
4. Worker-1: `<YOUR_WORKER1_IP>`
5. Worker-2: `<YOUR_WORKER2_IP>`
6. MetalLB range: `<YOUR_LB_IP>-<YOUR_LB_IP_END>`
7. Ingress LB IP: `<YOUR_LB_IP>`

## 4. 설치 절차

### 4.1 OVA Import

VMware에서 OVA 3개를 import합니다.

### 4.2 VM 네트워크/호스트명 설정

각 VM 콘솔에서 정적 IP와 hostname을 설정합니다.

예시(control-plane):

```bash
sudo bash /opt/k8s-data-platform/scripts/set_static_ip.sh --ip <YOUR_MASTER_IP> --prefix 24 --gateway <YOUR_GATEWAY_IP> --dns <YOUR_GATEWAY_IP>,1.1.1.1,8.8.8.8
sudo bash /opt/k8s-data-platform/scripts/set_hostname_hosts.sh --hostname k8s-data-platform --entry "<YOUR_MASTER_IP> k8s-data-platform" --entry "<YOUR_WORKER1_IP> k8s-worker-1" --entry "<YOUR_WORKER2_IP> k8s-worker-2"
```

### 4.3 원샷 설치 실행

WSL(저장소 루트)에서 실행:

```bash
bash init.sh --all
```

필요 시 정적 네트워크 파라미터를 명시:

```bash
bash ./start.sh \
  --static-network \
  --control-plane-ip <YOUR_MASTER_IP> \
  --worker1-ip <YOUR_WORKER1_IP> \
  --worker2-ip <YOUR_WORKER2_IP> \
  --gateway <YOUR_GATEWAY_IP> \
  --metallb-range <YOUR_LB_IP>-<YOUR_LB_IP_END> \
  --ingress-lb-ip <YOUR_LB_IP>
```

### 4.4 hosts 적용

Windows/WSL hosts에 아래 도메인을 등록합니다.

```text
<YOUR_LB_IP> platform.local
<YOUR_LB_IP> jupyter.platform.local
<YOUR_LB_IP> gitlab.platform.local
<YOUR_LB_IP> airflow.platform.local
<YOUR_LB_IP> nexus.platform.local
<YOUR_LB_IP> headlamp.platform.local
```

## 5. 설치 검증

### 5.1 클러스터 상태

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A -o wide
```

### 5.2 Ingress 검증

```bash
bash scripts/verify.sh --http-mode ingress --lb-ip <YOUR_LB_IP>
```

### 5.3 URL 확인

```bash
curl -I http://platform.local
curl -I http://gitlab.platform.local
curl -I http://airflow.platform.local
curl -I http://nexus.platform.local
```

## 6. 기본 관리자 계정(초기값)

1. Platform Admin: `admin@test.com / CHANGE_ME`
2. GitLab: `root / CHANGE_ME`
3. Airflow: `admin / CHANGE_ME`
4. Nexus: `admin / CHANGE_ME`

주의: 납품 후 운영 전 반드시 비밀번호를 변경하십시오.

## 7. 오프라인(air-gap) 필수 확인

1. `harbor.local/data-platform/*` 이미지가 노드 runtime에 존재해야 함
2. `/opt/k8s-data-platform/offline-bundle` 경로(또는 동등 bundle) 준비
3. 외부 레지스트리 참조 없이 pod 기동 가능해야 함

점검:

```bash
bash scripts/check_offline_readiness.sh
```

## 8. 설치 실패 시 우선 조치

1. `kubectl get pods -A`에서 `ImagePullBackOff` 확인
2. 오프라인 번들 재적재
3. `bash scripts/apply_k8s.sh --env dev --overlay dev-3node` 재적용
4. `bash scripts/verify.sh --http-mode ingress --lb-ip <LB_IP>` 재검증
