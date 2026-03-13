from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.models import DashboardResponse, TeradataQueryRequest, TeradataQueryResponse
from app.services.catalog import quick_links, runtime_profile, sample_queries
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
            "detail": "JupyterLab pod exposed on 8888 or NodePort 30088",
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
