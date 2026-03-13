from typing import Any

from pydantic import BaseModel, Field


class ServiceStatus(BaseModel):
    name: str
    kind: str
    endpoint: str
    ok: bool
    detail: str


class QuickLink(BaseModel):
    name: str
    url: str
    description: str


class SampleQuery(BaseModel):
    name: str
    description: str
    sql: str


class DashboardResponse(BaseModel):
    runtime: dict[str, str]
    services: list[ServiceStatus]
    quick_links: list[QuickLink]
    sample_queries: list[SampleQuery]
    notebooks: list[str]
    teradata: dict[str, Any]


class TeradataQueryRequest(BaseModel):
    sql: str = Field(min_length=1)
    limit: int = Field(default=20, ge=1, le=200)


class TeradataQueryResponse(BaseModel):
    columns: list[str]
    rows: list[dict[str, Any]]
    source: str
    note: str


class LabSessionRequest(BaseModel):
    username: str = Field(min_length=2, max_length=48)


class LabSessionResponse(BaseModel):
    session_id: str
    username: str
    namespace: str
    pod_name: str
    service_name: str
    status: str
    phase: str
    ready: bool
    detail: str
    token: str
    node_port: int | None = None
    created_at: str | None = None


class ControlPlaneLoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=128)


class ControlPlaneSummary(BaseModel):
    cluster_name: str
    cluster_version: str
    current_namespace: str
    namespace_count: int
    node_count: int
    ready_node_count: int
    pod_count: int
    running_pod_count: int


class ControlPlaneNode(BaseModel):
    name: str
    ready: bool
    roles: str
    version: str
    internal_ip: str
    os_image: str
    kernel_version: str
    container_runtime: str
    created_at: str | None = None


class ControlPlanePod(BaseModel):
    namespace: str
    name: str
    ready: str
    status: str
    restarts: int
    node_name: str
    pod_ip: str | None = None
    created_at: str | None = None


class ControlPlaneDashboardResponse(BaseModel):
    summary: ControlPlaneSummary
    namespaces: list[str]
    nodes: list[ControlPlaneNode]
    pods: list[ControlPlanePod]


class ControlPlaneLoginResponse(BaseModel):
    token: str
    username: str
    dashboard: ControlPlaneDashboardResponse
