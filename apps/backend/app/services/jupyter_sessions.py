from __future__ import annotations

import hashlib
import re

from kubernetes import client
from kubernetes.client.exceptions import ApiException
from kubernetes.config.config_exception import ConfigException

from app.config import Settings
from app.services.kube_client import get_core_v1_api

SESSION_COMPONENT = "jupyter-session"
SESSION_LABEL_KEY = "platform.dev/session-id"
MANAGED_BY = "k8s-data-platform-api"


def canonical_username(username: str) -> str:
    normalized = username.strip().lower()
    if len(normalized) < 2 or len(normalized) > 48:
        raise ValueError("username must be between 2 and 48 characters")
    if not re.fullmatch(r"[a-z0-9._@-]+", normalized):
        raise ValueError("username may contain only letters, numbers, dot, underscore, dash, and @")
    return normalized


def build_session_id(username: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", username).strip("-")
    slug = (slug[:24] or "user").strip("-") or "user"
    digest = hashlib.sha1(username.encode("utf-8")).hexdigest()[:8]
    return f"{slug}-{digest}"


def build_session_token(settings: Settings, session_id: str) -> str:
    seed = f"{settings.jupyter_token}:{session_id}"
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()[:24]


def pod_name(session_id: str) -> str:
    return f"lab-{session_id}"


def service_name(session_id: str) -> str:
    return f"lab-{session_id}"


def _read_pod(api: client.CoreV1Api, namespace: str, name: str) -> client.V1Pod | None:
    try:
        return api.read_namespaced_pod(name=name, namespace=namespace)
    except ApiException as exc:
        if exc.status == 404:
            return None
        raise


def _read_service(api: client.CoreV1Api, namespace: str, name: str) -> client.V1Service | None:
    try:
        return api.read_namespaced_service(name=name, namespace=namespace)
    except ApiException as exc:
        if exc.status == 404:
            return None
        raise


def _session_labels(session_id: str) -> dict[str, str]:
    return {
        "app": SESSION_COMPONENT,
        "app.kubernetes.io/name": SESSION_COMPONENT,
        "app.kubernetes.io/component": SESSION_COMPONENT,
        "app.kubernetes.io/managed-by": MANAGED_BY,
        SESSION_LABEL_KEY: session_id,
    }


def _container_detail(pod: client.V1Pod) -> str | None:
    statuses = (pod.status.container_statuses if pod.status else None) or []
    for status in statuses:
        if status.ready:
            continue
        state = status.state
        if state and state.waiting:
            message = state.waiting.message or "container is starting"
            return f"{state.waiting.reason}: {message}"
        if state and state.terminated:
            message = state.terminated.message or "container terminated"
            return f"{state.terminated.reason}: {message}"
    return None


def _is_pod_ready(pod: client.V1Pod | None) -> bool:
    if pod is None or pod.status is None:
        return False
    conditions = pod.status.conditions or []
    return any(condition.type == "Ready" and condition.status == "True" for condition in conditions)


def _created_at(pod: client.V1Pod | None) -> str | None:
    if pod is None or pod.metadata is None or pod.metadata.creation_timestamp is None:
        return None
    return pod.metadata.creation_timestamp.isoformat()


def _session_summary(
    settings: Settings,
    username: str,
    pod: client.V1Pod | None,
    service: client.V1Service | None,
) -> dict[str, object]:
    session_id = build_session_id(username)
    node_port = None
    if service and service.spec and service.spec.ports:
        node_port = service.spec.ports[0].node_port

    phase = "Missing"
    if pod and pod.status and pod.status.phase:
        phase = pod.status.phase

    ready = _is_pod_ready(pod)
    if pod is None:
        status = "missing"
        detail = "No personal JupyterLab session exists yet."
    elif phase == "Failed":
        status = "failed"
        detail = _container_detail(pod) or "Pod failed to start."
    elif ready and node_port:
        status = "ready"
        detail = f"JupyterLab is ready on NodePort {node_port}."
    else:
        status = "provisioning"
        detail = _container_detail(pod) or "JupyterLab pod is being prepared."

    return {
        "session_id": session_id,
        "username": username,
        "namespace": settings.k8s_namespace,
        "pod_name": pod_name(session_id),
        "service_name": service_name(session_id),
        "status": status,
        "phase": phase,
        "ready": ready and bool(node_port),
        "detail": detail,
        "token": build_session_token(settings, session_id),
        "node_port": node_port,
        "created_at": _created_at(pod),
    }


def _create_pod(api: client.CoreV1Api, settings: Settings, username: str, session_id: str) -> None:
    pod = client.V1Pod(
        metadata=client.V1ObjectMeta(
            name=pod_name(session_id),
            labels=_session_labels(session_id),
            annotations={
                "platform.dev/username": username,
            },
        ),
        spec=client.V1PodSpec(
            restart_policy="Always",
            termination_grace_period_seconds=15,
            containers=[
                client.V1Container(
                    name="jupyter",
                    image=settings.jupyter_image,
                    image_pull_policy="IfNotPresent",
                    ports=[client.V1ContainerPort(container_port=8888)],
                    env=[
                        client.V1EnvVar(
                            name="JUPYTER_TOKEN",
                            value=build_session_token(settings, session_id),
                        ),
                    ],
                    resources=client.V1ResourceRequirements(
                        requests={"cpu": "100m", "memory": "256Mi"},
                        limits={"cpu": "1000m", "memory": "1Gi"},
                    ),
                    readiness_probe=client.V1Probe(
                        http_get=client.V1HTTPGetAction(path="/lab", port=8888),
                        initial_delay_seconds=5,
                        period_seconds=5,
                        timeout_seconds=2,
                        failure_threshold=18,
                    ),
                    liveness_probe=client.V1Probe(
                        http_get=client.V1HTTPGetAction(path="/lab", port=8888),
                        initial_delay_seconds=20,
                        period_seconds=10,
                        timeout_seconds=2,
                        failure_threshold=6,
                    ),
                )
            ],
        ),
    )
    api.create_namespaced_pod(namespace=settings.k8s_namespace, body=pod)


def _create_service(api: client.CoreV1Api, settings: Settings, session_id: str) -> None:
    service = client.V1Service(
        metadata=client.V1ObjectMeta(
            name=service_name(session_id),
            labels=_session_labels(session_id),
        ),
        spec=client.V1ServiceSpec(
            type="NodePort",
            selector={SESSION_LABEL_KEY: session_id},
            ports=[
                client.V1ServicePort(
                    name="http",
                    port=8888,
                    target_port=8888,
                    protocol="TCP",
                )
            ],
        ),
    )
    api.create_namespaced_service(namespace=settings.k8s_namespace, body=service)


def get_lab_session(settings: Settings, username: str) -> dict[str, object]:
    username = canonical_username(username)
    session_id = build_session_id(username)

    try:
        api = get_core_v1_api()
        pod = _read_pod(api, settings.k8s_namespace, pod_name(session_id))
        service = _read_service(api, settings.k8s_namespace, service_name(session_id))
        return _session_summary(settings, username, pod, service)
    except ConfigException as exc:
        raise RuntimeError("Kubernetes client configuration is unavailable.") from exc
    except ApiException as exc:
        raise RuntimeError(f"Kubernetes API error while reading Jupyter session: {exc.reason}") from exc


def ensure_lab_session(settings: Settings, username: str) -> dict[str, object]:
    username = canonical_username(username)
    session_id = build_session_id(username)

    try:
        api = get_core_v1_api()
        pod = _read_pod(api, settings.k8s_namespace, pod_name(session_id))
        if pod and pod.status and pod.status.phase in {"Failed", "Succeeded"}:
            api.delete_namespaced_pod(name=pod_name(session_id), namespace=settings.k8s_namespace)
            pod = None

        if pod is None:
            _create_pod(api, settings, username, session_id)

        service = _read_service(api, settings.k8s_namespace, service_name(session_id))
        if service is None:
            _create_service(api, settings, session_id)

        pod = _read_pod(api, settings.k8s_namespace, pod_name(session_id))
        service = _read_service(api, settings.k8s_namespace, service_name(session_id))
        return _session_summary(settings, username, pod, service)
    except ConfigException as exc:
        raise RuntimeError("Kubernetes client configuration is unavailable.") from exc
    except ApiException as exc:
        raise RuntimeError(f"Kubernetes API error while creating Jupyter session: {exc.reason}") from exc


def delete_lab_session(settings: Settings, username: str) -> dict[str, object]:
    username = canonical_username(username)
    session_id = build_session_id(username)

    try:
        api = get_core_v1_api()
        summary = get_lab_session(settings, username)

        try:
            api.delete_namespaced_service(name=service_name(session_id), namespace=settings.k8s_namespace)
        except ApiException as exc:
            if exc.status != 404:
                raise

        try:
            api.delete_namespaced_pod(name=pod_name(session_id), namespace=settings.k8s_namespace)
        except ApiException as exc:
            if exc.status != 404:
                raise

        summary["status"] = "deleted"
        summary["phase"] = "Deleted"
        summary["ready"] = False
        summary["detail"] = "Personal JupyterLab session resources were deleted."
        summary["node_port"] = None
        return summary
    except ConfigException as exc:
        raise RuntimeError("Kubernetes client configuration is unavailable.") from exc
    except ApiException as exc:
        raise RuntimeError(f"Kubernetes API error while deleting Jupyter session: {exc.reason}") from exc
