# FSS 서버 맵 (사무실 연습 기준)

이 문서는 공유된 서버 표를 그대로 재정리한 운영 메모입니다.
민감정보(패스워드)는 저장하지 않고, 사용자명/엔드포인트 중심으로 기록합니다.

> **주의**: 아래 IP는 실습 환경 기준 플레이스홀더입니다.
> 실제 운영 IP는 런타임 env 파일 또는 별도 vault에서 관리하세요.

## 1) 인프라/도구 서버

- ESXi: `<YOUR_ESXI_IP>` (`https://<YOUR_ESXI_IP>`)
- NFS 시뮬레이터: `<YOUR_NFS_IP>` (`http://<YOUR_NFS_WEB_IP>:8080`)
- Harbor(사무실): `<YOUR_HARBOR_IP>` / 반입 대역 `<YOUR_HARBOR_IP>`
- GitLab(사무실): `<YOUR_GITLAB_IP>` / 반입 대역 `<YOUR_GITLAB_IP>`
- ELTFR(사무실): `<YOUR_ELTFR_IP>` / 반입 대역 `<YOUR_ELTFR_IP>`

## 2) Kubernetes 노드

- `master-1`: `<YOUR_MASTER_IP>` (SSH port `10022`)
- `worker-1`: `<YOUR_WORKER1_IP>` (SSH port `10022`, NFS NIC `<YOUR_NFS_CIDR>.x`)
- `worker-2`: `<YOUR_WORKER2_IP>` (SSH port `10022`, NFS NIC `<YOUR_NFS_CIDR>.x`)
- `worker-ml-1`: `<YOUR_WORKER_ML1_IP>` (SSH port `10022`, NFS NIC `<YOUR_NFS_CIDR>.x`)

MetalLB 단일 IP(개발): `<YOUR_LB_IP>`

## 3) Bastion 정리

- 사무실 설치 작업용 bastion: `<YOUR_BASTION_IP>`
- 내부 대역 기준 표기: `<YOUR_BASTION_INTERNAL_IP>`
- 이 bastion은 "반입 대상 N"(비반입) 이므로, VMware 화면에서 4개 K8s 노드만 보일 수 있습니다.

즉, 화면에 `master/worker` 4대만 보이는 것은 정상이며,
필요 시 `docs/bh-bastion-setup.md` 절차로 `bh`를 별도로 만들어 동일 방식으로 연습하면 됩니다.

## 4) 연습용 env 파일

- 서버 맵 변수 템플릿: `scripts/templates/fss-office-inventory.env.example`
- 클러스터 부트스트랩 템플릿: `scripts/templates/fss-office-dev.env.example`

실행 전에는 런타임 파일로 복사해서 사용하세요.

```bash
mkdir -p /home/disadm/fss-support/k8s-dev/runtime
cp scripts/templates/fss-office-inventory.env.example /home/disadm/fss-support/k8s-dev/runtime/fss-office-inventory.env
cp scripts/templates/fss-office-dev.env.example /home/disadm/fss-support/k8s-dev/runtime/fss-office-dev.env
```
