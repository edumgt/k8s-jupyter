# jupyter-frontend

`adw.local`/`adw.fss.or.kr`용 Vue3 + Quasar SPA 프론트엔드입니다.

## 배포 대상
- Harbor image: `harbor.local/app/fss-adw-frontend`
- Kubernetes deployment: `fss-adw-frontend` (`infra/k8s/fss/base/adw-app.yaml`)

## 로컬 실행
```bash
cd apps/jupyter-frontend
npm install --no-audit --no-fund
npm run dev
```

## 환경 파일
- `.env.dev` 기본 API: `http://adw.local`
- `.env.prod` 기본 API: `https://adw.fss.or.kr`
