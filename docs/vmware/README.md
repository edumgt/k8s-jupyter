# VMware 실행 가이드 (Repo 다운로드부터 구동까지)

이 문서는 **VMware 방식**으로 이 저장소를 실행하는 과정을 정리합니다.

## 1) 사전 준비

- OS: Windows 10/11 (권장)
- VMware Workstation Pro/Player 설치
- Git 설치
- 선택: WSL2 (OVA를 직접 빌드할 경우 편리)

기본 계정(OVA 내부):
- username: `ubuntu`
- password: `ubuntu`

## 2) 저장소 다운로드

```bash
git clone https://github.com/<your-org>/Kubernetes-Jupyter-Sandbox.git
cd Kubernetes-Jupyter-Sandbox
```

## 3) OVA 준비

다음 2가지 경로 중 하나를 선택합니다.

### A. 이미 OVA 파일이 있는 경우

- `k8s-data-platform.ova` 파일을 준비하고 다음 단계로 이동합니다.

### B. 이 repo에서 OVA를 직접 빌드하는 경우

```bash
cp packer/variables.pkr.hcl.example packer/variables.pkr.hcl
```

`packer/variables.pkr.hcl`에 ISO 경로/체크섬 등을 맞춘 뒤:

```bash
bash scripts/run_wsl.sh
```

산출물:
- `dist/k8s-data-platform.ova`

참고:
- 현재 Packer 템플릿은 `virtualbox-iso` 빌더를 사용합니다.
- 즉, **빌드 단계에는 VirtualBox가 필요**할 수 있고, 실행(검증)은 VMware에서 진행할 수 있습니다.

## 4) VMware로 OVA Import

1. VMware Workstation 실행
2. `File > Open` 또는 `Import`로 `k8s-data-platform.ova` 선택
3. 아래와 같은 경고가 나오면 `Retry`를 눌러 import를 다시 진행
   - `The import failed because ... did not pass OVF specification conformance or virtual hardware compliance checks.`
   - 이 OVA는 VirtualBox 계열 export 결과물이라 VMware가 OVF/가상 하드웨어 호환성 검사를 엄격하게 볼 때 이 경고가 나올 수 있음
   - 일반적으로 `Retry`를 누르면 검사를 완화하고 계속 import 가능
4. VM 이름/저장 경로 지정
5. CPU/Memory 조정 (권장: CPU 4+, Memory 16GB+)
6. Network Adapter를 `Bridged` 권장
7. VM 부팅

## 5) VM 내부 상태 확인

VM 콘솔 로그인 후:

```bash
hostname -I
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n data-platform-dev -o wide
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get svc -n data-platform-dev
```

## 6) 호스트 브라우저 접속

`<OVA_IP>`는 `hostname -I`로 확인한 VM IP입니다.

- Frontend: `http://<OVA_IP>:30080`
- Backend: `http://<OVA_IP>:30081`
- Jupyter: `http://<OVA_IP>:30088`
- GitLab: `http://<OVA_IP>:30089`
- Airflow: `http://<OVA_IP>:30090`
- Nexus: `http://<OVA_IP>:30091`
- code-server: `http://<OVA_IP>:30100`

로그인 계정:
- user: `test1@test.com / 123456`
- user: `test2@test.com / 123456`
- admin: `admin@test.com / 123456`

## 7) 자주 발생하는 이슈

### VMware import 중 OVF compliance 오류가 뜨는 경우

- 예시 메시지:
  - `The import failed because ... did not pass OVF specification conformance or virtual hardware compliance checks.`
- 우선 `Retry`를 눌러 VMware의 완화된 import 모드로 다시 시도합니다.
- 이 경고는 OVA 자체가 완전히 깨졌다는 뜻보다는, VMware가 OVF/가상 하드웨어 메타데이터를 엄격하게 검사하면서 발생하는 경우가 많습니다.
- `Retry` 후 import가 완료되면 그대로 사용해도 됩니다.
- 그래도 실패하면 다음 순서로 확인합니다.
  - OVA 파일 경로를 영문/짧은 경로로 옮긴 뒤 다시 import
  - OVA를 다시 export 또는 다시 build
  - VMware import 완료 후 부팅이 안 되면 firmware 설정을 기본값 유지한 상태로 다시 import

### VMware import는 됐지만 부팅/동작이 이상한 경우

- CPU 4개 이상, Memory 16GB 이상으로 올린 뒤 다시 부팅합니다.
- Network Adapter는 우선 `Bridged`로 두고 VM 내부에서 `hostname -I`로 IP를 확인합니다.
- `kubectl` 확인 시 반드시 관리자 kubeconfig를 사용합니다.

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
```

### 부팅 중 `Failed to fork off sandboxing environment` / `Freezing execution` 이 뜨는 경우

- 예시 메시지:
  - `Failed to fork off sandboxing environment for executing generators: Protocol error`
  - `[!!!!!!] Failed to start up manager.`
  - `systemd[1]: Freezing execution.`
- 이 경우는 단순한 VMware import 경고가 아니라, Ubuntu 24.04 부팅 초기에 `systemd`가 멈춘 상태입니다.
- 화면에 `recovering journal` 이 보였다면 비정상 종료 직후 한 번 발생했을 가능성도 있으니, 우선 VM을 완전히 종료한 뒤 다시 켜 봅니다.
- 재부팅 후에도 같은 화면에서 멈추면 가장 확실한 복구 방법은 라이브 ISO 또는 복구 환경으로 부팅해서 `initramfs`를 다시 생성하는 것입니다.

예시 절차:

```bash
sudo mount /dev/sda2 /mnt
sudo mount --bind /dev /mnt/dev
sudo mount --bind /dev/pts /mnt/dev/pts
sudo mount --bind /proc /mnt/proc
sudo mount --bind /sys /mnt/sys
sudo mount --bind /run /mnt/run
sudo chroot /mnt
update-initramfs -c -k all
exit
sudo reboot
```

주의:
- 루트 파티션이 `/dev/sda2`가 아닐 수 있으므로 실제 파티션명을 먼저 확인해야 합니다.
- 가능하면 Ubuntu Server 24.04 계열 ISO의 `Try Ubuntu` 또는 recovery shell에서 작업하는 편이 안전합니다.
- 복구 후 정상 부팅되면 아래 명령으로 상태를 다시 확인합니다.

```bash
hostname -I
sudo systemctl is-active docker containerd kubelet
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n data-platform-dev -o wide
```

### `ip -br a`에서 `ens32`가 `DOWN`으로 나오는 경우

- 이 상태에서는 VM이 네트워크를 못 잡아서 `hostname -I`가 비거나, 호스트에서 NodePort 접근이 모두 실패합니다.
- 먼저 VMware VM 설정에서 아래 항목을 확인합니다.
  - `Network Adapter > Connected` 체크
  - `Network Adapter > Connect at power on` 체크
  - 우선 `Bridged` 사용 (필요하면 `Configure Adapters`에서 실제 사용 중인 호스트 NIC를 명시)
- 회사/학교망 정책으로 Bridged가 막히는 환경이면 일단 `NAT`로 전환해 통신 여부를 먼저 확인합니다.

VM 내부에서:

```bash
ip -br a
sudo ip link set ens32 up
sudo systemctl restart systemd-networkd
sudo networkctl reconfigure ens32
ip -4 addr show ens32
ip route
```

- `ens32`에 IPv4가 생기면 정상입니다.
- Ubuntu 24.04 이미지에 따라 `dhclient`가 기본 미설치일 수 있습니다. (`sudo: dhclient: command not found` 정상 가능)
- 그 다음 control-plane에서 `kubectl`이 정상인지 확인합니다.

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n data-platform-dev -o wide
```

- 위 절차 후에도 계속 IP가 안 생기면 netplan에 DHCP를 명시하고 재적용합니다.

```bash
sudo tee /etc/netplan/01-vmware-dhcp.yaml >/dev/null <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    ens32:
      dhcp4: true
EOF
sudo netplan generate
sudo netplan apply
sudo systemctl restart systemd-networkd
ip -4 addr show ens32
```

- 그래도 DHCP 임대가 안 잡히면(특히 Bridged/사내망 환경) VMware 네트워크를 `NAT`로 바꿔 우선 연결 여부를 확인합니다.
- `dhclient`를 꼭 써야 하면 아래 패키지를 설치합니다.

```bash
sudo apt-get update
sudo apt-get install -y isc-dhcp-client
sudo dhclient -v ens32
```

### kubectl이 `localhost:8080`으로 붙는 경우

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes
```

### 화면은 열리는데 API 호출이 실패하는 경우

- 브라우저 URL과 API 포트 접근 방식을 통일합니다.
- VMware에서는 일반적으로 `http://<OVA_IP>:30080` 접근을 권장합니다.

## 8) 멀티노드 관련 참고

- `scripts/bootstrap_virtualbox_multinode.ps1`는 이름 그대로 VirtualBox 자동화 스크립트입니다.
- VMware 멀티노드는 이 repo 기준으로 자동 스크립트가 제공되지 않으므로 수동 구성(복제/네트워크/join)이 필요합니다.
