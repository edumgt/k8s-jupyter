# platform-backend

이 디렉터리는 GitLab 의 개별 app repo 로 push 하는 스캐폴드입니다.

## CI/CD 흐름

- GitLab Runner 가 pipeline 을 실행
- Kaniko 로 Harbor `data-platform/*` 이미지 빌드/푸시
- `kubectl set image` 로 Kubernetes deployment `backend` 갱신

## 필요한 GitLab CI 변수

- `HARBOR_USERNAME`
- `HARBOR_PASSWORD`
- `NEXUS_PYPI_INDEX_URL` (backend)
- `NEXUS_PYPI_TRUSTED_HOST` (backend)
- `NEXUS_NPM_REGISTRY` (frontend)
- `NEXUS_NPM_AUTH_B64` (frontend, optional)

브랜치는 `dev` 또는 `prod`를 사용하면 환경별 namespace/dev-proxy URL이 자동으로 적용됩니다.

## 배포 대상

- Harbor image: `harbor.local/${HARBOR_PROJECT:-data-platform}/k8s-data-platform-backend`
- Kubernetes deployment: `backend`

## JWT 로그인 연동 (프론트 모달)

- 로그인 API: `POST /api/auth/login`
- 요청 본문(JSON): `{"username":"test1@test.com","password":"123456"}`
- 응답: `access_token`, `token_type`(`bearer`), `expires_in`, `user` (기존 `token` 필드도 호환 유지)
- 인증 헤더: `Authorization: Bearer <access_token>` (기존 `x-auth-token`도 호환 유지)

예시:

```bash
curl -sS http://localhost:8000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"test1@test.com","password":"123456"}'
```

```bash
curl -sS http://localhost:8000/api/auth/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

환경변수(선택):

- `PLATFORM_AUTH_JWT_SECRET` (기본: `platform-auth-jwt`)
- `PLATFORM_AUTH_JWT_ALGORITHM` (기본: `HS256`)
- `PLATFORM_AUTH_JWT_TTL_SECONDS` (기본: `43200`, 12시간)
- `PLATFORM_CORS_ALLOW_ORIGINS` (콤마 구분 오리진 목록)
- `PLATFORM_CORS_ALLOW_ORIGIN_REGEX` (오리진 정규식)
- `PLATFORM_CORS_ALLOW_CREDENTIALS` (`true`/`false`)

## Teradata Bootstrap (관리자 전용)

Teradata 는 오픈소스 내장 DB가 아니라 외부 상용 DB 연결 방식입니다.
이 백엔드는 관리자 API로 bootstrap SQL(엔진성 SP + 메타/공통코드/계정 seed)을 실행할 수 있습니다.

- Endpoint: `POST /api/admin/teradata/bootstrap`
- 권한: admin JWT 필요 (`Authorization: Bearer <token>`)
- 기본 동작: `dry_run=true` 권장
- 기본 SQL 파일: `app/sql/teradata/bootstrap.sql`
- 구분자: SQL 파일에서 `--@@` 로 statement block 분리

필수 환경변수:

- `PLATFORM_TERADATA_FAKE_MODE=false`
- `PLATFORM_TERADATA_HOST`
- `PLATFORM_TERADATA_USER`
- `PLATFORM_TERADATA_PASSWORD`
- `PLATFORM_TERADATA_DATABASE`
- (선택) `PLATFORM_TERADATA_BOOTSTRAP_SQL_PATH` (커스텀 SQL 파일 경로)

예시:

```bash
# 1) admin 로그인
TOKEN=$(curl -sS http://localhost:8000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin@test.com","password":"123456"}' | jq -r '.access_token')

# 2) dry-run (권장)
curl -sS http://localhost:8000/api/admin/teradata/bootstrap \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"dry_run":true}'

# 3) 실제 실행
curl -sS http://localhost:8000/api/admin/teradata/bootstrap \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"dry_run":false}'
```
