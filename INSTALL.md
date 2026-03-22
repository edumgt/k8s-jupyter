# INSTALL.md
## Kubernetes-Jupyter-Sandbox OVA 이전/설치 가이드

이 문서는 다른 PC로 OVA를 복사한 뒤 VMware에 Import 하고, 3개 VM의 IP/hostname 을 맞추고, WSL/Windows `hosts` 파일까지 정리한 다음 최종적으로 플랫폼 검증까지 마치는 절차를 상세히 설명합니다.

기본 대상 구성은 아래와 같습니다.

- control-plane: `k8s-data-platform`
- worker-1: `k8s-worker-1`
- worker-2: `k8s-worker-2`
- control-plane IP: `192.168.56.10`
- worker-1 IP: `192.168.56.11`
- worker-2 IP: `192.168.56.12`
- gateway: `192.168.56.1`
- MetalLB range: `192.168.56.240-192.168.56.250`
- ingress LB IP: `192.168.56.240`

## 1) 사전 준비

- 대상 PC: Windows + VMware Workstation
- WSL: Ubuntu 권장
- 저장소 위치: `/home/Kubernetes-Jupyter-Sandbox` 또는 `/opt/k8s-data-platform`
- VMware 에서 3개 VM을 구동할 수 있는 CPU/RAM/디스크 여유 확인
- Windows 와 WSL 모두에서 동일한 네트워크 대역을 사용할 수 있는지 확인

권장 확인 항목:

- Windows 에서 VMware Workstation 실행 가능
- WSL 에서 `bash`, `ssh`, `wslpath` 사용 가능
- VM 내부 Ubuntu 계정의 `sudo` 비밀번호 확인 가능

## 2) OVA 파일을 다른 PC로 복사

대상 PC의 예시 위치:

- `C:\VM\k8s-data-platform.ova`

주의:

- 하나의 OVA만 있는 경우, 동일 OVA를 3번 Import 해서 역할별 VM으로 사용합니다.
- 이미 role 별 OVA 3개를 export 해 둔 경우에는 각 OVA를 해당 이름으로 import 하면 됩니다.

## 3) VMware 에 OVA Import

VMware Workstation 에서 OVA를 import 합니다.

단일 OVA 1개를 3번 import 하는 경우 권장 VM 이름:

- `k8s-data-platform`
- `k8s-worker-1`
- `k8s-worker-2`

중요:

- 세 VM은 반드시 서로 다른 이름으로 등록합니다.
- import 직후에는 세 VM이 같은 hostname, 같은 DHCP IP 를 가질 수 있습니다.
- 이 상태에서 바로 `start.sh`를 실행하면 SSH 대상이 꼬일 수 있으므로, 먼저 각 VM의 고정 IP 와 hostname 을 수동으로 분리해야 합니다.

## 4) 각 VM 전원 ON 후 콘솔 접속

세 VM을 모두 켠 뒤 VMware 콘솔로 각각 로그인합니다.

먼저 각 VM에서 현재 상태를 확인합니다.

```bash
hostname
hostname -I
ip route
```

세 VM이 모두 같은 IP 를 사용 중이면 정상적인 초기 상태가 아닙니다. 이 경우 아래 단계대로 각 VM의 IP 와 hostname 을 먼저 분리해야 합니다.

이 단계에서 보조 스크립트로 [init.sh](/home/Kubernetes-Jupyter-Sandbox/init.sh) 를 사용할 수 있습니다.

먼저 WSL 에서 아래 명령으로 각 VM에 복붙할 명령을 출력합니다.

```bash
bash ./init.sh --vm-commands
```

중요:

- `init.sh`는 같은 IP 를 공유 중인 3개 VM의 내부 IP 를 원격으로 자동 변경하지는 않습니다.
- 이 상태에서는 어떤 SSH 연결이 어느 VM으로 가는지 구분할 수 없으므로, VMware 콘솔에서 각 VM에 직접 로그인해야 합니다.
- 대신 `init.sh`는 각 VM에서 실행해야 할 `set_static_ip.sh`, `set_hostname_hosts.sh` 명령을 한 번에 정리해 줍니다.

## 5) 각 VM의 고정 IP 설정

이 저장소에는 VM 내부 고정 IP 설정용 스크립트가 있습니다.

- [scripts/set_static_ip.sh](/home/Kubernetes-Jupyter-Sandbox/scripts/set_static_ip.sh)

기본적으로 네트워크 인터페이스는 자동 감지됩니다. 자동 감지가 실패하면 `--iface ens160` 같은 형태로 직접 지정합니다.

### 5-1) control-plane

VMware 콘솔에서 `k8s-data-platform` VM에 로그인 후 실행:

```bash
sudo bash /opt/k8s-data-platform/scripts/set_static_ip.sh --ip 192.168.56.10 --prefix 24 --gateway 192.168.56.1 --dns 192.168.56.1,1.1.1.1,8.8.8.8
```

### 5-2) worker-1

VMware 콘솔에서 `k8s-worker-1` VM에 로그인 후 실행:

```bash
sudo bash /opt/k8s-data-platform/scripts/set_static_ip.sh --ip 192.168.56.11 --prefix 24 --gateway 192.168.56.1 --dns 192.168.56.1,1.1.1.1,8.8.8.8
```

### 5-3) worker-2

VMware 콘솔에서 `k8s-worker-2` VM에 로그인 후 실행:

```bash
sudo bash /opt/k8s-data-platform/scripts/set_static_ip.sh --ip 192.168.56.12 --prefix 24 --gateway 192.168.56.1 --dns 192.168.56.1,1.1.1.1,8.8.8.8
```

적용 후 각 VM에서 다시 확인:

```bash
hostname -I
ip route
```

## 6) 각 VM의 hostname 및 `/etc/hosts` 보정

이 저장소에는 hostname 과 guest 내부 `/etc/hosts` fallback 설정용 스크립트가 있습니다.

- [scripts/set_hostname_hosts.sh](/home/Kubernetes-Jupyter-Sandbox/scripts/set_hostname_hosts.sh)

각 VM에서 자기 역할에 맞는 hostname 으로 설정합니다.

### 6-1) control-plane

```bash
sudo bash /opt/k8s-data-platform/scripts/set_hostname_hosts.sh --hostname k8s-data-platform --entry "192.168.56.10 k8s-data-platform" --entry "192.168.56.11 k8s-worker-1" --entry "192.168.56.12 k8s-worker-2"
```

### 6-2) worker-1

```bash
sudo bash /opt/k8s-data-platform/scripts/set_hostname_hosts.sh --hostname k8s-worker-1 --entry "192.168.56.10 k8s-data-platform" --entry "192.168.56.11 k8s-worker-1" --entry "192.168.56.12 k8s-worker-2"
```

### 6-3) worker-2

```bash
sudo bash /opt/k8s-data-platform/scripts/set_hostname_hosts.sh --hostname k8s-worker-2 --entry "192.168.56.10 k8s-data-platform" --entry "192.168.56.11 k8s-worker-1" --entry "192.168.56.12 k8s-worker-2"
```

적용 후 각 VM에서 확인:

```bash
hostname
cat /etc/hosts
```

## 7) VM 내부 최종 점검

각 VM에서 아래를 확인합니다.

- `hostname` 이 역할명과 일치하는지
- `hostname -I` 에서 각기 다른 IP 가 보이는지
- `ping -c 1 192.168.56.10`
- `ping -c 1 192.168.56.11`
- `ping -c 1 192.168.56.12`

예상 결과:

- `k8s-data-platform` -> `192.168.56.10`
- `k8s-worker-1` -> `192.168.56.11`
- `k8s-worker-2` -> `192.168.56.12`

## 8) WSL 에서 메인 배포/검증 실행

실행 전에 먼저 Windows/VMware/WSL 간 라우팅이 맞아야 합니다.

사전 네트워크 구성 순서:

1. VMware Host-only 네트워크를 `192.168.56.0/24`로 생성
2. Windows 호스트 어댑터를 `192.168.56.1`로 연결
3. 그 다음 WSL 에 `192.168.56.0/24 -> <WSL 기본 게이트웨이>` 라우트 추가

### 8-1) VMware Host-only 네트워크 생성

Windows 에서 VMware Workstation 을 관리자 권한으로 열고 `Virtual Network Editor`를 실행합니다.

권장 설정:

- Network type: `Host-only`
- Subnet IP: `192.168.56.0`
- Subnet mask: `255.255.255.0`
- DHCP: 가능하면 비활성화
- `Connect a host virtual adapter to this network`: 활성화

예:

- `VMnet2` -> `Host-only` -> `192.168.56.0/24`

그리고 `k8s-data-platform`, `k8s-worker-1`, `k8s-worker-2` 세 VM의 네트워크 어댑터를 모두 같은 `VMnet`에 연결합니다.

### 8-2) Windows 호스트 어댑터 IP 확인

Windows 네트워크 어댑터 목록에서 `VMware Network Adapter VMnetX`를 확인합니다.

이 어댑터의 IPv4 가 아래처럼 잡혀 있어야 합니다.

- IP: `192.168.56.1`
- Subnet mask: `255.255.255.0`

필요하면 Windows 에서 수동 설정합니다.

Windows 확인 예:

```powershell
ipconfig
ping 192.168.56.10
ping 192.168.56.11
ping 192.168.56.12
```

여기서 Windows 자체가 세 VM에 도달하지 못하면, WSL 라우트 추가 전에 VMware 네트워크부터 다시 확인해야 합니다.

### 8-3) WSL 라우트 추가

WSL 에서 현재 기본 게이트웨이를 확인합니다.

```bash
ip route
```

예를 들어 기본 게이트웨이가 `172.24.112.1`이면 아래처럼 라우트를 추가합니다.

```bash
sudo ip route replace 192.168.56.0/24 via 172.24.112.1 dev eth0
```

`init.sh`로 같은 작업을 하려면:

```bash
bash ./init.sh --apply-wsl-route
```

게이트웨이를 직접 지정하려면:

```bash
bash ./init.sh --apply-wsl-route --wsl-route-gateway 172.24.112.1
```

라우트 적용 확인:

```bash
ip route
ping -c 1 192.168.56.10
nc -vz 192.168.56.10 22
```

이제 WSL 에서 저장소 루트로 이동한 뒤 아래 명령을 실행합니다.

```bash
bash ./start.sh \
  --vars-file packer/variables.vmware.auto.pkrvars.hcl \
  --static-network \
  --control-plane-ip 192.168.56.10 \
  --worker1-ip 192.168.56.11 \
  --worker2-ip 192.168.56.12 \
  --gateway 192.168.56.1 \
  --metallb-range 192.168.56.240-192.168.56.250 \
  --ingress-lb-ip 192.168.56.240 \
  --always-provision
```

설명:

- `--static-network`: 고정 IP 기준으로 클러스터를 처리합니다.
- `--always-provision`: 기존 VMX 가 이미 있어도 provision/bootstrap 단계를 강제로 다시 태웁니다.
- `--ingress-lb-ip 192.168.56.240`: 최종 접속용 URL 이 이 IP 로 연결되도록 맞춥니다.

이미 VM 이 있고 IP/hostname 을 수동 보정한 이후라면, 처음 한 번은 `--always-provision`을 함께 주는 편이 안전합니다.

같은 작업을 `init.sh`로 실행하려면:

```bash
bash ./init.sh --run-start -- --skip-export
```

추가 옵션이 필요하면 `--` 뒤에 그대로 넘기면 됩니다.

## 9) WSL 의 `/etc/hosts` 설정

WSL 에서 브라우저 또는 `curl` 로 `platform.local` 계열 URL 을 바로 접근하려면 WSL 의 `/etc/hosts` 에 ingress LB IP 를 등록합니다.

WSL 에서:

```bash
sudo sh -c 'cat >> /etc/hosts <<EOF
192.168.56.240 platform.local jupyter.platform.local gitlab.platform.local airflow.platform.local nexus.platform.local
EOF'
```

확인:

```bash
grep 'platform.local' /etc/hosts
```

주의:

- 여기에는 node IP 가 아니라 ingress LB IP `192.168.56.240` 를 넣습니다.
- `k8s-data-platform`, `k8s-worker-1`, `k8s-worker-2` 같은 노드 이름은 VM 내부 `/etc/hosts` 용도입니다.

같은 작업을 `init.sh`로 실행하려면:

```bash
bash ./init.sh --apply-wsl-hosts
```

## 10) Windows `hosts` 파일 설정

Windows 브라우저에서 같은 도메인으로 접근하려면 Windows `hosts` 파일도 수정해야 합니다.

대상 파일:

- `C:\Windows\System32\drivers\etc\hosts`

관리자 권한으로 메모장 또는 편집기를 열고 아래 줄을 추가합니다.

```text
192.168.56.240 platform.local jupyter.platform.local gitlab.platform.local airflow.platform.local nexus.platform.local
```

저장 후 Windows 에서 확인:

```powershell
ping platform.local
```

주의:

- Windows `hosts` 파일 수정은 관리자 권한이 필요합니다.
- 회사 보안 정책에 따라 파일 편집이 제한될 수 있습니다.

같은 작업을 `init.sh`로 실행하려면:

```bash
bash ./init.sh --apply-windows-hosts
```

WSL 에서 `powershell.exe`를 통해 Windows `hosts` 파일을 갱신합니다. 관리자 권한이 필요한 환경에서는 Windows 측 권한 승인이 필요할 수 있습니다.

## 11) 접속 확인

WSL 또는 Windows 브라우저에서 아래 URL 을 확인합니다.

- `http://platform.local`
- `http://platform.local/docs`
- `http://jupyter.platform.local/lab`
- `http://gitlab.platform.local`
- `http://airflow.platform.local`
- `http://nexus.platform.local`

WSL 에서 간단 확인:

```bash
curl -I http://platform.local
curl -I http://gitlab.platform.local
curl -I http://nexus.platform.local
```

## 12) 표준 디렉터리 구성(`/opt/company/*`)

플랫폼 내부 디렉터리 구조가 필요하면 아래 스크립트를 실행합니다.

```bash
bash scripts/provision_company_layout.sh
```

생성 경로:

- `/opt/company/bin`
- `/opt/company/config`
- `/opt/company/images`
- `/opt/company/packages`
- `/opt/company/scripts`
- `/opt/company/docs`

## 13) 운영 기본 명령

상태 확인:

```bash
bash scripts/status_k8s.sh --env dev
```

서비스 종료:

```bash
bash scripts/svc-down.sh --env dev
```

전체 네임스페이스 정리:

```bash
bash scripts/svc-down.sh --env dev --delete-namespace
```

백업:

```bash
bash scripts/backup_platform.sh --env dev
```

복구:

```bash
bash scripts/restore_platform.sh --env dev --backup-dir <backup-dir>
```

## 14) 폐쇄망 대비 오프라인 이미지 사전 적재

폐쇄망 또는 DNS 제약 환경에서는 `docker.io/edumgt/*` 이미지를 실시간 pull 하지 못해 GitLab, Jupyter, Airflow, ingress 등의 Pod 가 `ErrImagePull` 또는 `ImagePullBackOff` 상태가 될 수 있습니다.

이 저장소에는 오프라인 번들 생성 및 VM preload 흐름이 포함되어 있습니다.

관련 스크립트:

- [scripts/prepare_offline_bundle.sh](/home/Kubernetes-Jupyter-Sandbox/scripts/prepare_offline_bundle.sh)
- [scripts/import_offline_bundle.sh](/home/Kubernetes-Jupyter-Sandbox/scripts/import_offline_bundle.sh)
- [scripts/preload_offline_bundle_to_vm.sh](/home/Kubernetes-Jupyter-Sandbox/scripts/preload_offline_bundle_to_vm.sh)
- [scripts/check_offline_readiness.sh](/home/Kubernetes-Jupyter-Sandbox/scripts/check_offline_readiness.sh)

권장 순서:

1. 인터넷이 되는 WSL 또는 빌드 호스트에서 오프라인 번들 생성
2. control-plane VM으로 번들 복사
3. VM 내부 Docker/containerd 에 이미지 tar import
4. 필요 시 오프라인 번들 기준으로 manifest 적용

### 14-1) 오프라인 번들 생성

```bash
bash scripts/prepare_offline_bundle.sh --out-dir dist/offline-bundle
```

이 단계에서 아래가 생성됩니다.

- `dist/offline-bundle/images/*.tar`
- `dist/offline-bundle/k8s/...`
- Python wheel / npm cache

### 14-2) control-plane VM으로 오프라인 번들 preload

control-plane VM 이 `192.168.56.10`일 때:

```bash
bash scripts/preload_offline_bundle_to_vm.sh \
  --control-plane-ip 192.168.56.10 \
  --env dev
```

기존 번들을 재사용하려면:

```bash
bash scripts/preload_offline_bundle_to_vm.sh \
  --control-plane-ip 192.168.56.10 \
  --env dev \
  --skip-build
```

이미지 import 후 바로 번들 기준 manifest 적용까지 하려면:

```bash
bash scripts/preload_offline_bundle_to_vm.sh \
  --control-plane-ip 192.168.56.10 \
  --env dev \
  --skip-build \
  --apply
```

설명:

- 로컬에서 오프라인 번들을 만들거나 재사용합니다.
- control-plane VM 의 `/opt/k8s-data-platform/offline-bundle` 아래로 복사합니다.
- VM 내부에서 `docker load` 와 `ctr -n k8s.io images import`를 수행합니다.
- 이후 폐쇄망에서도 GitLab/Nexus/Jupyter 등 핵심 이미지를 외부 pull 없이 사용할 수 있습니다.
- Flannel / ingress-nginx / MetalLB 매니페스트도 번들에 함께 포함되어 외부 URL 다운로드 없이 사용할 수 있습니다.

### 14-3) preload 이후 확인

control-plane 에서:

```bash
sudo ctr -n k8s.io images ls | grep 'platform-gitlab-ce\|platform-nexus3\|k8s-data-platform-jupyter'
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A -o wide
```

GitLab pod 가 `ErrImagePull` 대신 `ContainerCreating`, `Running` 으로 넘어가면 preload 가 반영된 것입니다.

오프라인 준비 상태를 한 번에 점검하려면:

```bash
bash /opt/k8s-data-platform/scripts/check_offline_readiness.sh
```

또는 저장소 경로에서:

```bash
bash scripts/check_offline_readiness.sh
```

## 15) 자주 발생하는 문제

### 15-1) 세 VM이 모두 같은 IP 를 쓰는 경우

증상:

- `start.sh` 에서 SSH 타임아웃
- control-plane, worker-1, worker-2 가 모두 같은 DHCP IP

해결:

- VMware 콘솔에서 각 VM에 직접 로그인
- 먼저 [scripts/set_static_ip.sh](/home/Kubernetes-Jupyter-Sandbox/scripts/set_static_ip.sh) 로 IP 분리
- 다음 [scripts/set_hostname_hosts.sh](/home/Kubernetes-Jupyter-Sandbox/scripts/set_hostname_hosts.sh) 로 hostname 보정
- 그 후 WSL 에서 `start.sh ... --always-provision` 재실행

### 15-2) `--static-network`를 줬는데도 SSH 가 `192.168.56.10`으로 안 붙는 경우

원인:

- 기존 VMX 재사용 모드에서는 VM 내부 IP 가 아직 실제로 바뀌지 않았을 수 있습니다.

해결:

- 먼저 VM 콘솔에서 IP 를 수동 보정
- 이후 `--always-provision` 포함해서 `start.sh` 실행

### 15-3) `platform.local` 접속이 안 되는 경우

확인 순서:

1. `kubectl get svc -A` 로 ingress 관련 서비스 확인
2. `start.sh` 실행 시 `--ingress-lb-ip 192.168.56.240` 을 줬는지 확인
3. WSL `/etc/hosts` 에 `192.168.56.240 platform.local ...` 이 들어갔는지 확인
4. Windows `hosts` 파일에도 같은 줄이 들어갔는지 확인

### 15-4) GitLab/Nexus/Jupyter 가 `ErrImagePull` 인 경우

원인:

- 폐쇄망 또는 DNS 제한으로 `docker.io/edumgt/*` 이미지를 당겨오지 못함

해결:

- [scripts/preload_offline_bundle_to_vm.sh](/home/Kubernetes-Jupyter-Sandbox/scripts/preload_offline_bundle_to_vm.sh) 로 control-plane VM 에 이미지 preload
- 필요 시 worker 노드에도 동일 방식으로 preload

## 16) 권장 작업 순서 요약

1. OVA 를 다른 PC로 복사
2. VMware 에 3개 VM으로 import
3. 각 VM 콘솔에서 IP 를 `192.168.56.10/11/12` 로 분리
4. 각 VM hostname 을 `k8s-data-platform`, `k8s-worker-1`, `k8s-worker-2` 로 보정
5. Windows/VMware/WSL 네트워크 경로를 `192.168.56.0/24` 기준으로 정리
6. 필요 시 `bash scripts/preload_offline_bundle_to_vm.sh --control-plane-ip 192.168.56.10 --env dev` 실행
7. WSL 에서 `bash ./start.sh ... --always-provision` 실행
8. WSL `/etc/hosts` 에 `192.168.56.240 platform.local ...` 등록
9. Windows `hosts` 파일에도 같은 내용 등록
10. 브라우저에서 `platform.local`, `gitlab.platform.local`, `nexus.platform.local` 확인

`init.sh` 기준 빠른 실행 예시:

1. `bash ./init.sh --vm-commands`
2. 출력된 명령을 각 VM 콘솔에서 각각 실행
3. `bash ./init.sh --apply-wsl-hosts --apply-windows-hosts`
4. `bash ./init.sh --run-start -- --skip-export`
