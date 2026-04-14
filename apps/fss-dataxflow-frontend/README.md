# fss-dataxflow-frontend

`dataxflow.platform.local`용 Vue3 + Quasar SPA 프론트엔드입니다.

## 배포 대상
- Harbor image: `192.168.56.72/${HARBOR_PROJECT:-app}/fss-dataxflow-frontend`
- Kubernetes deployment: `fss-dataxflow-frontend` (별도 ELT 매니페스트에서 참조)

## 로컬 실행
```bash
cd apps/fss-dataxflow-frontend
npm install --no-audit --no-fund
npm run dev
```

## 환경 파일
- `.env.dev` 기본 API: `http://api.dataxflow.platform.local`
- `.env.prod` 기본 API: `http://api.dataxflow.platform.local`
