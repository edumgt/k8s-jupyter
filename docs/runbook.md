# Runbook

## 1. 호스트 상태 확인

```bash
systemctl status k3s
```

## 2. 클러스터 상태 확인

```bash
kubectl get nodes
kubectl get pods -n data-platform-dev
kubectl get svc -n data-platform-dev
kubectl get pvc -n data-platform-dev
```

## 3. 플랫폼 적용

```bash
bash scripts/apply_k8s.sh --env dev
bash scripts/apply_k8s.sh --env prod
```

## 4. 플랫폼 초기화

```bash
bash scripts/reset_k8s.sh --env dev
bash scripts/reset_k8s.sh --env prod
```

## 5. 주요 NodePort 확인

```bash
kubectl get svc -n data-platform-dev
```

## 6. 장애 복구 예시

```bash
sudo systemctl restart k3s
kubectl rollout restart deployment/backend -n data-platform-dev
kubectl rollout restart deployment/frontend -n data-platform-dev
kubectl rollout restart deployment/jupyter -n data-platform-dev
kubectl rollout restart deployment/airflow -n data-platform-dev
kubectl rollout restart deployment/gitlab -n data-platform-dev
```

## 7. Runner 활성화

```bash
bash scripts/apply_k8s.sh --env dev --with-runner
kubectl scale deployment/gitlab-runner -n data-platform-dev --replicas=1
```

## 8. app repo export

```bash
bash scripts/export_gitlab_repos.sh --force
```

각 export 결과를 별도 GitLab project 로 push 한 뒤, 해당 repo 의 pipeline 이 Runner 를 통해 개별 app deployment 를 갱신합니다.

## 9. 보안 상태

```bash
sudo ufw status verbose
sudo fail2ban-client status
```
