# Runbook

## 1. 호스트 상태 확인

```bash
systemctl status docker
systemctl status k3s
docker ps
```

## 2. 클러스터 상태 확인

```bash
kubectl get nodes
kubectl get pods -n data-platform-dev
kubectl get svc -n data-platform-dev
kubectl get pvc -n data-platform-dev
```

## 3. 플랫폼 이미지 재준비

```bash
bash scripts/build_k8s_images.sh --namespace edumgt --tag latest
```

Docker Hub push 가 필요하면:

```bash
bash scripts/publish_dockerhub.sh --namespace edumgt --tag latest
```

## 4. 플랫폼 적용

```bash
bash scripts/apply_k8s.sh --env dev
bash scripts/apply_k8s.sh --env prod
```

## 5. 플랫폼 초기화

```bash
bash scripts/reset_k8s.sh --env dev
bash scripts/reset_k8s.sh --env prod
```

## 6. 사용자별 Jupyter snapshot 확인

```bash
curl -sS http://localhost:30081/api/jupyter/snapshots/student01 | jq
```

snapshot publish:

```bash
curl -sS http://localhost:30081/api/jupyter/snapshots \
  -H 'Content-Type: application/json' \
  -d '{"username":"student01"}' | jq
```

## 7. 주요 복구 예시

```bash
sudo systemctl restart docker
sudo systemctl restart k3s
kubectl rollout restart deployment/backend -n data-platform-dev
kubectl rollout restart deployment/frontend -n data-platform-dev
kubectl rollout restart deployment/jupyter -n data-platform-dev
kubectl rollout restart deployment/airflow -n data-platform-dev
kubectl rollout restart deployment/gitlab -n data-platform-dev
```

## 8. Runner 활성화

```bash
bash scripts/apply_k8s.sh --env dev --with-runner
kubectl scale deployment/gitlab-runner -n data-platform-dev --replicas=1
```

## 9. 폐쇄망 번들 재생성

```bash
bash scripts/prepare_offline_bundle.sh --out-dir dist/offline-bundle
```

OVA 내부 기본 경로:

```bash
ls -lah /opt/k8s-data-platform/offline-bundle
```
