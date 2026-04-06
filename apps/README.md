# apps Directory Map

`apps` 디렉터리는 도메인별로 아래처럼 사용합니다.

## Jupyter (`jupyter.local`)
- Backend: `apps/jupyter-backend` -> `apps/adw-server-node` (alias)
- Frontend: `apps/jupyter-frontend` (physical directory)

## Dataxflow (`dataxflow.local`)
- Backend: `apps/dataxflow-backend` -> `apps/backend` (alias)
- Frontend: `apps/dataxflow-frontend` (physical directory)

## Canonical Source (호환 경로)
- `apps/adw-server-node`: Node 기반 Jupyter 거버넌스 API
- `apps/backend`: FastAPI 기반 dataxflow backend
- `apps/frontend`: 기존 공용 경로(legacy). 신규 변경은 도메인별 FE 경로에 반영 권장
