# dataxflow-frontend

`dataxflow.local`용 Vue3 + Quasar SPA 프론트엔드입니다.

## 배포 대상
- Harbor image: `harbor.local/${HARBOR_PROJECT:-data-platform}/k8s-dataxflow-frontend`
- Kubernetes deployment: `frontend` (`infra/k8s/dataxflow/overlays/dev/frontend.yaml`)

## 로컬 실행
```bash
cd apps/dataxflow-frontend
npm install --no-audit --no-fund
npm run dev
```

## 환경 파일
- `.env.dev` 기본 API: `http://api.dataxflow.local`
- `.env.prod` 기본 API: `http://api.dataxflow.local`
