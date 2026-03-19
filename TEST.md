# Kubernetes Test Snapshot (2026-03-19)

## 1) Current VM and Node IP Summary

| VM Name | Kubernetes Node | Role | State | Internal IP |
|---|---|---|---|---|
| k8s-data-platform | k8s-data-platform | control-plane | Running / Ready | 10.77.0.4 |
| k8s-worker-1 | k8s-worker-1 | worker | Running / Ready | 10.77.0.5 |
| k8s-worker-2 | k8s-worker-2 | worker | Running / Ready | 10.77.0.6 |
| k8s-worker-3 | removed | worker | Stopped | 10.77.0.7 (old) |

Running VMs (`VBoxManage list runningvms`):
- k8s-data-platform
- k8s-worker-1
- k8s-worker-2

Current Kubernetes nodes (`kubectl get nodes -o wide`):
- k8s-data-platform (10.77.0.4)
- k8s-worker-1 (10.77.0.5)
- k8s-worker-2 (10.77.0.6)

---

## 2) Service IP and NodePort Summary (`data-platform-dev`)

| Service | Type | ClusterIP | Service Port | NodePort | Access Example |
|---|---|---|---|---|---|
| airflow | NodePort | 10.99.64.233 | 8080/TCP | 30090 | `http://10.77.0.5:30090` |
| backend | NodePort | 10.108.80.33 | 8000/TCP | 30081 | `http://10.77.0.5:30081` |
| frontend | NodePort | 10.101.40.171 | 80/TCP | 30080 | `http://10.77.0.5:30080` |
| gitlab-web | NodePort | 10.102.234.133 | 8929/TCP, 22/TCP | 30089, 30224 | `http://10.77.0.5:30089`, `ssh -p 30224 ...` |
| jupyter | NodePort | 10.99.190.56 | 8888/TCP | 30088 | `http://10.77.0.5:30088` |
| nexus | NodePort | 10.98.114.37 | 8081/TCP | 30091 | `http://10.77.0.5:30091` |
| mongodb | ClusterIP | 10.106.245.2 | 27017/TCP | none | internal only |
| redis | ClusterIP | 10.96.125.129 | 6379/TCP | none | internal only |

---

## 3) SSH Rules Applied (Done)

Applied NAT network SSH forwarding rules:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" natnetwork modify --netname k8s-data-platform-net --port-forward-4 "ssh-cp:tcp:[127.0.0.1]:2222:[10.77.0.4]:22"
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" natnetwork modify --netname k8s-data-platform-net --port-forward-4 "ssh-w1:tcp:[127.0.0.1]:2201:[10.77.0.5]:22"
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" natnetwork modify --netname k8s-data-platform-net --port-forward-4 "ssh-w2:tcp:[127.0.0.1]:2202:[10.77.0.6]:22"
```

Windows host connectivity check:
- `127.0.0.1:2222` = open
- `127.0.0.1:2201` = open
- `127.0.0.1:2202` = open

Default account/password:
- username: `ubuntu`
- password: `ubuntu`

---

## 4) SSH Access from Windows and WSL

### 4.1 Windows terminal

```bash
ssh ubuntu@127.0.0.1 -p 2222   # control-plane
ssh ubuntu@127.0.0.1 -p 2201   # worker-1
ssh ubuntu@127.0.0.1 -p 2202   # worker-2
```

### 4.2 WSL terminal (recommended, reliable in this environment)

Use Windows OpenSSH client directly from WSL:

```bash
/mnt/c/Windows/System32/OpenSSH/ssh.exe ubuntu@127.0.0.1 -p 2222
/mnt/c/Windows/System32/OpenSSH/ssh.exe ubuntu@127.0.0.1 -p 2201
/mnt/c/Windows/System32/OpenSSH/ssh.exe ubuntu@127.0.0.1 -p 2202
```

Why this method:
- In this environment, native WSL Linux `ssh` to forwarded localhost ports may fail depending on WSL localhost forwarding mode.
- Windows `ssh.exe` always uses Windows networking stack, so it reaches VBox forwarded ports reliably.

### 4.3 Alternative (inside control-plane VM)

```bash
ssh ubuntu@10.77.0.5   # worker-1
ssh ubuntu@10.77.0.6   # worker-2
```

---

## 5) Move These VMs to Another VirtualBox Host

Recommended method: export/import OVA.

### 5.1 On source host (current PC)

1. Power off VMs.
2. Export OVA files:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm k8s-data-platform poweroff
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm k8s-worker-1 poweroff
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm k8s-worker-2 poweroff

& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" export k8s-data-platform --output C:\tmp\k8s-data-platform.ova
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" export k8s-worker-1 --output C:\tmp\k8s-worker-1.ova
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" export k8s-worker-2 --output C:\tmp\k8s-worker-2.ova
```

3. Copy `.ova` files to target PC.

### 5.2 On target host (other VirtualBox PC)

Import OVAs:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" import C:\tmp\k8s-data-platform.ova --vsys 0 --vmname k8s-data-platform
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" import C:\tmp\k8s-worker-1.ova --vsys 0 --vmname k8s-worker-1
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" import C:\tmp\k8s-worker-2.ova --vsys 0 --vmname k8s-worker-2
```

---

## 6) Network Setup After Import (Important)

Create (or update) NAT network:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" natnetwork add --netname k8s-data-platform-net --network 10.77.0.0/24 --dhcp on --enable
```

If it already exists, run:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" natnetwork modify --netname k8s-data-platform-net --network 10.77.0.0/24 --dhcp on --enable
```

Attach NIC1 of each VM to the NAT network:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" modifyvm k8s-data-platform --nic1 natnetwork --nat-network1 k8s-data-platform-net --cableconnected1 on
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" modifyvm k8s-worker-1 --nic1 natnetwork --nat-network1 k8s-data-platform-net --cableconnected1 on
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" modifyvm k8s-worker-2 --nic1 natnetwork --nat-network1 k8s-data-platform-net --cableconnected1 on
```

Apply SSH forwarding rules again on target host:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" natnetwork modify --netname k8s-data-platform-net --port-forward-4 "ssh-cp:tcp:[127.0.0.1]:2222:[10.77.0.4]:22"
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" natnetwork modify --netname k8s-data-platform-net --port-forward-4 "ssh-w1:tcp:[127.0.0.1]:2201:[10.77.0.5]:22"
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" natnetwork modify --netname k8s-data-platform-net --port-forward-4 "ssh-w2:tcp:[127.0.0.1]:2202:[10.77.0.6]:22"
```

---

## 7) Bring-Up and Post-Boot Checks

Start order:
1. control-plane (`k8s-data-platform`)
2. worker-1
3. worker-2

Commands:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm k8s-data-platform --type headless
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm k8s-worker-1 --type headless
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm k8s-worker-2 --type headless
```

Inside control-plane:

```bash
KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
KUBECONFIG=/etc/kubernetes/admin.conf kubectl get svc -n data-platform-dev -o wide
KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n data-platform-dev -o wide
```

If stale `k8s-worker-3` node appears:

```bash
KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete node k8s-worker-3 --ignore-not-found
```
