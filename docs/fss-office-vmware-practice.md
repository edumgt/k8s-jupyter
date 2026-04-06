# FSS 사무실/반입 유사 환경 VMware 연습 가이드

목표:

- 사무실의 NAT + 별도 NFS NIC + Harbor(insecure) + bastion 경유 운영 방식을
  내 PC VMware/사내 랩에서 최대한 동일하게 연습
- 반입 후 변경 포인트(DNS, Harbor secure, NFS endpoint)까지 문서화

## 1) 작업 디렉터리 (bastion 기준)

요구사항에 맞게 매니페스트/스크립트 작업 경로를 고정합니다.

```bash
mkdir -p /home/disadm/fss-support/k8s-dev
cd /home/disadm/fss-support/k8s-dev
# git clone <your-git-url> .
```

## 2) K8s 버전 맞추기 (선택)

이 레포 기본은 `v1.34` 계열이며, 아래 env로 minor를 오버라이드할 수 있습니다.

```bash
export KUBERNETES_APT_MINOR_VERSION=v1.35
```

주의:

- 위 값은 **minor 라인** 선택입니다. (예: `v1.35`)
- 정확히 `1.35.3` patch 고정이 필요하면 apt 패키지 버전 핀 추가가 별도 필요합니다.

## 3) 클러스터 bootstrap (master-1 + worker-1 + worker-2 + worker-ml-1)

템플릿 복사:

```bash
mkdir -p /home/disadm/fss-support/k8s-dev/runtime
cp scripts/templates/fss-office-dev.env.example /home/disadm/fss-support/k8s-dev/runtime/fss-office-dev.env
vi /home/disadm/fss-support/k8s-dev/runtime/fss-office-dev.env
```

실행:

```bash
bash scripts/bootstrap_3node_k8s_ova.sh --config /home/disadm/fss-support/k8s-dev/runtime/fss-office-dev.env
```

검증:

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A -o wide
```

## 4) worker-ml 라벨/스케줄 정책

GPU가 아직 없으면 라벨/affinity만 먼저 검증합니다.

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl label node worker-ml-1 node-role.kubernetes.io/worker-ml=worker-ml --overwrite
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl label node worker-ml-1 dis.role=ml --overwrite
```

필요 시 일반 워크로드 차단(옵션):

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl taint node worker-ml-1 dis/ml-only=true:NoSchedule --overwrite
```

## 5) FSS namespace / dynamic route / infra 적용

```bash
bash scripts/setup_fss_platform.sh \
  --env dev \
  --metallb-range 10.111.111.77-10.111.111.77 \
  --ingress-lb-ip 10.111.111.77 \
  --harbor-server 10.111.111.72:80 \
  --harbor-username 'robot$dis' \
  --harbor-password '<password>'

# 수동 적용 시
# kubectl apply -k infra/k8s/fss/overlays/dev

kubectl get ns | egrep 'app|dis|infra|sample|unitest'
kubectl -n dis get deploy,svc,ingress
kubectl -n infra get sts,svc,pvc,secret
```

구성 검증:

```bash
bash scripts/verify_fss_vmware_setup.sh
kubectl get ns | egrep 'app|dis|infra|sample|unitest'
kubectl -n dis get deploy,svc,ingress
kubectl -n infra get sts,svc,pvc,secret
```

## 6) NFS 연습 포인트

현재는 사무실 NFS 시뮬레이터 기준으로 마운트하고, 반입 후 endpoint 교체만 수행합니다.

노드에서 확인:

```bash
showmount -e 192.168.10.2
mount | grep 192.168.10.2
```

성능/용량 검증 샘플(busybox):

```bash
kubectl -n sample run io-test --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl -n sample exec -it io-test -- sh
# inside:
# df -h
# dd if=/dev/zero of=/tmp/test.bin bs=1M count=1024
```

## 7) 노드 추가/삭제 운영 가이드

추가(예: worker 신규 1대):

```bash
# control-plane
JOIN_CMD="$(sudo kubeadm token create --ttl 2h --print-join-command)"
echo "${JOIN_CMD}"

# 신규 worker
sudo kubeadm reset -f || true
sudo ${JOIN_CMD}
```

라벨 부여:

```bash
kubectl label node <new-node-name> node-role.kubernetes.io/worker=worker --overwrite
```

삭제:

```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <node-name>
# 대상 노드에서
sudo kubeadm reset -f
```

## 8) 반입 후 변경 체크리스트

1. DNS 서버 주소 교체 (`DNS_SERVERS`, node resolver)
2. Harbor insecure -> secure 전환 (containerd registry config + certs)
3. NFS endpoint/IP 교체 및 mount/fstab 반영
4. MetalLB 주소대역 재설정 (금감원 대역)
5. hosts 임시 매핑 제거 후 정식 DNS 검증
