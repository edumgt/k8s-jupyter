#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from contextlib import ExitStack
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

ROOT_DIR = Path(__file__).resolve().parents[1]
BACKEND_DIR = ROOT_DIR / "apps" / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from fastapi import HTTPException
from kubernetes.client.exceptions import ApiException

from app.config import get_settings
from app.main import (
    bootstrap_teradata,
    create_jupyter_session,
    dashboard,
    login_demo_user,
    read_admin_sandbox_overview,
    read_jupyter_session,
    read_my_usage,
    require_authenticated_user,
    teradata_query,
)
from app.models import DemoUserLoginRequest, LabSessionRequest, TeradataBootstrapRequest, TeradataQueryRequest
from app.services import demo_users
from app.services.jupyter_sessions import _restore_workspace_script
from app.services.jupyter_snapshots import get_snapshot_status


def fake_session_summary(username: str, minutes_ago: int = 1) -> dict[str, object]:
    created_at = (datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)).isoformat()
    session_id = username.replace("@", "-").replace(".", "-")
    return {
        "session_id": session_id,
        "username": username,
        "namespace": "data-platform-dev",
        "pod_name": f"lab-{session_id}",
        "service_name": f"lab-{session_id}",
        "workspace_subpath": f"users/{session_id}",
        "image": "harbor.local/data-platform/k8s-data-platform-jupyter:latest",
        "status": "ready",
        "phase": "Running",
        "ready": True,
        "detail": "JupyterLab is ready on NodePort 31000.",
        "token": "demo-token",
        "node_port": 31000 + minutes_ago,
        "created_at": created_at,
    }


class DemoAuthFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        demo_users._memory_tokens.clear()
        demo_users._memory_metrics.clear()
        get_settings.cache_clear()

        self.session_state = {
            "test1@test.com": fake_session_summary("test1@test.com", minutes_ago=3),
        }

        def fake_ensure_lab_session(settings, username: str):
            summary = dict(self.session_state[username])
            demo_users.record_lab_launch(settings, username, str(summary["created_at"]))
            demo_users.sync_session_activity(settings, username, summary)
            return summary

        def fake_get_lab_session(settings, username: str):
            summary = dict(self.session_state[username])
            demo_users.sync_session_activity(settings, username, summary)
            return summary

        self.patches = ExitStack()
        self.patches.enter_context(patch("app.main.ensure_lab_session", fake_ensure_lab_session))
        self.patches.enter_context(patch("app.main.get_lab_session", fake_get_lab_session))
        self.patches.enter_context(patch("app.main.get_mongo_status", lambda url: (True, "ping ok")))
        self.patches.enter_context(patch("app.main.get_redis_status", lambda url: (True, "ping ok")))
        self.patches.enter_context(
            patch("app.services.jupyter_sessions.get_lab_session", fake_get_lab_session)
        )
        self.patches.enter_context(patch("app.services.demo_users._redis_client", lambda settings: None))

    def tearDown(self) -> None:
        self.patches.close()

    def login(self, username: str, password: str = "123456"):
        response = login_demo_user(DemoUserLoginRequest(username=username, password=password))
        current_user = require_authenticated_user(response.token)
        return response, current_user

    def test_demo_user_login_and_own_jupyter_session(self) -> None:
        login_response, current_user = self.login("test1@test.com")
        self.assertEqual(login_response.user.username, "test1@test.com")
        self.assertEqual(login_response.user.role, "user")

        session = create_jupyter_session(
            LabSessionRequest(username="test1@test.com"),
            current_user=current_user,
        )
        self.assertEqual(session.username, "test1@test.com")
        self.assertEqual(session.status, "ready")
        self.assertTrue(session.ready)
        self.assertIn("lab-test1-test-com", session.pod_name)

        with self.assertRaises(HTTPException) as exc:
            read_jupyter_session("admin@test.com", current_user=current_user)
        self.assertEqual(exc.exception.status_code, 403)

    def test_admin_can_monitor_sandbox_users(self) -> None:
        _response1, user1 = self.login("test1@test.com")

        create_jupyter_session(LabSessionRequest(username="test1@test.com"), current_user=user1)

        _admin_response, admin_user = self.login("admin@test.com")
        overview = read_admin_sandbox_overview(_current_user=admin_user)

        self.assertEqual(overview.summary.sandbox_user_count, 1)
        self.assertEqual(overview.summary.running_user_count, 1)

        users = {item.username: item for item in overview.users}
        self.assertEqual(users["test1@test.com"].launch_count, 1)
        self.assertGreaterEqual(users["test1@test.com"].current_session_seconds, 1)
        self.assertTrue(users["test1@test.com"].ready)

    def test_datax_module_blocks_jupyter_routes_and_hides_dashboard_service(self) -> None:
        _login_response, current_user = self.login("test1@test.com")
        _admin_response, admin_user = self.login("admin@test.com")

        with self.assertRaises(HTTPException) as usage_exc:
            read_my_usage(current_user=current_user, request_host="api.dataxflow.local")
        self.assertEqual(usage_exc.exception.status_code, 404)

        with self.assertRaises(HTTPException) as session_exc:
            create_jupyter_session(
                LabSessionRequest(username="test1@test.com"),
                current_user=current_user,
                request_host="api.dataxflow.local",
            )
        self.assertEqual(session_exc.exception.status_code, 404)

        with self.assertRaises(HTTPException) as admin_exc:
            read_admin_sandbox_overview(
                _current_user=admin_user,
                request_host="api.dataxflow.local",
            )
        self.assertEqual(admin_exc.exception.status_code, 404)

        datax_dashboard = dashboard(request_host="api.dataxflow.local")
        self.assertEqual(datax_dashboard.notebooks, [])
        self.assertNotIn("jupyter", {service.name for service in datax_dashboard.services})

        platform_dashboard = dashboard(request_host="dev-api.platform.local")
        self.assertIn("jupyter", {service.name for service in platform_dashboard.services})

    def test_platform_module_blocks_sql_routes_and_hides_query_dashboard_sections(self) -> None:
        _login_response, current_user = self.login("test1@test.com")
        _admin_response, admin_user = self.login("admin@test.com")

        with self.assertRaises(HTTPException) as query_exc:
            teradata_query(
                TeradataQueryRequest(sql="SELECT 1", limit=10),
                request_host="api.platform.local",
            )
        self.assertEqual(query_exc.exception.status_code, 404)

        with self.assertRaises(HTTPException) as bootstrap_exc:
            bootstrap_teradata(
                TeradataBootstrapRequest(dry_run=True),
                _current_user=admin_user,
                request_host="api.platform.local",
            )
        self.assertEqual(bootstrap_exc.exception.status_code, 404)

        platform_dashboard = dashboard(request_host="api.platform.local")
        self.assertEqual(platform_dashboard.sample_queries, [])
        self.assertEqual(platform_dashboard.teradata, {})

        datax_dashboard = dashboard(request_host="api.dataxflow.local")
        self.assertGreater(len(datax_dashboard.sample_queries), 0)
        self.assertIn("mode", datax_dashboard.teradata)

    def test_snapshot_status_falls_back_when_job_listing_is_forbidden(self) -> None:
        settings = get_settings()
        with patch(
            "app.services.jupyter_snapshots.get_batch_v1_api",
            side_effect=ApiException(status=403, reason="Forbidden"),
        ):
            snapshot = get_snapshot_status(settings, "test1@test.com")

        self.assertEqual(snapshot["status"], "missing")
        self.assertFalse(snapshot["restorable"])
        self.assertIn("base Jupyter image", snapshot["detail"])

    def test_restore_workspace_script_keeps_shell_variables_intact(self) -> None:
        settings = get_settings()
        script = _restore_workspace_script(
            settings,
            "harbor.local/data-platform/k8s-data-platform-jupyter:latest",
            "users/test1-test-com",
        )

        self.assertIn('workspace_dir="/workspace-volume/users/test1-test-com"', script)
        self.assertIn('${workspace_dir}', script)
        self.assertNotIn("NameError", script)


if __name__ == "__main__":
    unittest.main(verbosity=2)
