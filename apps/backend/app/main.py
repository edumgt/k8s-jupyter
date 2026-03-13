from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.models import (
    ControlPlaneDashboardResponse,
    ControlPlaneLoginRequest,
    ControlPlaneLoginResponse,
    DashboardResponse,
    LabSessionRequest,
    LabSessionResponse,
    TeradataQueryRequest,
    TeradataQueryResponse,
)
from app.services.catalog import quick_links, runtime_profile, sample_queries
from app.services.control_plane import (
    build_control_plane_dashboard,
    build_control_plane_token,
    verify_control_plane_credentials,
    verify_control_plane_token,
)
from app.services.jupyter_sessions import delete_lab_session, ensure_lab_session, get_lab_session
from app.services.mongo import get_mongo_status
from app.services.redis_store import get_redis_status
from app.services.teradata import run_ansi_query, teradata_summary

app = FastAPI(title="k8s-data-platform-api", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


def list_notebooks(notebooks_path: str) -> list[str]:
    path = Path(notebooks_path)
    if not path.exists():
        return []
    return sorted(item.name for item in path.iterdir() if item.suffix == ".ipynb")


def require_control_plane_access(
    x_control_plane_token: str | None = Header(default=None),
):
    settings = get_settings()
    if not verify_control_plane_token(settings, x_control_plane_token):
        raise HTTPException(status_code=401, detail="Control-plane login required.")
    return settings


@app.get("/healthz")
def healthz() -> dict[str, object]:
    settings = get_settings()
    mongo_ok, mongo_detail = get_mongo_status(settings.mongo_url)
    redis_ok, redis_detail = get_redis_status(settings.redis_url)
    overall_status = "ok" if mongo_ok and redis_ok else "degraded"
    return {
        "status": overall_status,
        "checks": {
            "mongodb": {"ok": mongo_ok, "detail": mongo_detail},
            "redis": {"ok": redis_ok, "detail": redis_detail},
        },
    }


@app.get("/api/notebooks")
def notebooks() -> dict[str, list[str]]:
    settings = get_settings()
    return {"items": list_notebooks(settings.notebooks_path)}


@app.get("/api/dashboard", response_model=DashboardResponse)
def dashboard() -> DashboardResponse:
    settings = get_settings()
    mongo_ok, mongo_detail = get_mongo_status(settings.mongo_url)
    redis_ok, redis_detail = get_redis_status(settings.redis_url)

    services = [
        {
            "name": "backend",
            "kind": "api",
            "endpoint": "http://backend:8000",
            "ok": True,
            "detail": "FastAPI service ready",
        },
        {
            "name": "mongodb",
            "kind": "database",
            "endpoint": settings.mongo_url,
            "ok": mongo_ok,
            "detail": mongo_detail,
        },
        {
            "name": "redis",
            "kind": "cache",
            "endpoint": settings.redis_url,
            "ok": redis_ok,
            "detail": redis_detail,
        },
        {
            "name": "control-plane-dashboard",
            "kind": "cluster-admin",
            "endpoint": settings.control_plane_url,
            "ok": True,
            "detail": "Frontend control-plane dashboard with node and pod inventory after admin login",
        },
        {
            "name": "airflow",
            "kind": "orchestrator",
            "endpoint": settings.airflow_url,
            "ok": True,
            "detail": "Airflow webserver exposed on 8080 or NodePort 30090",
        },
        {
            "name": "jupyter",
            "kind": "workbench",
            "endpoint": settings.jupyter_url,
            "ok": True,
            "detail": "Shared JupyterLab plus per-user Jupyter sessions launched from the frontend",
        },
        {
            "name": "gitlab",
            "kind": "cicd",
            "endpoint": settings.gitlab_url,
            "ok": True,
            "detail": "GitLab CE exposed on NodePort 30089 and SSH NodePort 30224",
        },
    ]

    return DashboardResponse(
        runtime=runtime_profile(settings),
        services=services,
        quick_links=quick_links(settings),
        sample_queries=sample_queries(),
        notebooks=list_notebooks(settings.notebooks_path),
        teradata=teradata_summary(settings),
    )


@app.post("/api/teradata/query", response_model=TeradataQueryResponse)
def teradata_query(request: TeradataQueryRequest) -> TeradataQueryResponse:
    settings = get_settings()
    result = run_ansi_query(settings, request.sql, request.limit)
    return TeradataQueryResponse(**result)


@app.post("/api/jupyter/sessions", response_model=LabSessionResponse)
def create_jupyter_session(request: LabSessionRequest) -> LabSessionResponse:
    settings = get_settings()
    try:
        return LabSessionResponse(**ensure_lab_session(settings, request.username))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.get("/api/jupyter/sessions/{username}", response_model=LabSessionResponse)
def read_jupyter_session(username: str) -> LabSessionResponse:
    settings = get_settings()
    try:
        return LabSessionResponse(**get_lab_session(settings, username))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.delete("/api/jupyter/sessions/{username}", response_model=LabSessionResponse)
def remove_jupyter_session(username: str) -> LabSessionResponse:
    settings = get_settings()
    try:
        return LabSessionResponse(**delete_lab_session(settings, username))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/api/control-plane/login", response_model=ControlPlaneLoginResponse)
def control_plane_login(request: ControlPlaneLoginRequest) -> ControlPlaneLoginResponse:
    settings = get_settings()
    if not verify_control_plane_credentials(settings, request.username, request.password):
        raise HTTPException(status_code=401, detail="Invalid control-plane credentials.")

    dashboard = build_control_plane_dashboard(settings, namespace="all")
    return ControlPlaneLoginResponse(
        token=build_control_plane_token(settings, request.username),
        username=request.username,
        dashboard=ControlPlaneDashboardResponse(**dashboard),
    )


@app.get("/api/control-plane/dashboard", response_model=ControlPlaneDashboardResponse)
def control_plane_dashboard(
    namespace: str = "all",
    settings=Depends(require_control_plane_access),
) -> ControlPlaneDashboardResponse:
    try:
        return ControlPlaneDashboardResponse(**build_control_plane_dashboard(settings, namespace))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
