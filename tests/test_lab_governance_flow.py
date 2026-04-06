#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT_DIR = Path(__file__).resolve().parents[1]
BACKEND_DIR = ROOT_DIR / "apps" / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.config import get_settings
from app.services import demo_users, lab_governance


class LabGovernanceFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        get_settings.cache_clear()
        demo_users._memory_metrics.clear()
        demo_users._memory_managed_users.clear()
        lab_governance._memory_envs.clear()
        lab_governance._memory_resource_requests.clear()
        lab_governance._memory_env_requests.clear()
        lab_governance._memory_allocations.clear()
        lab_governance._memory_assignments.clear()

        self.patches = [
            patch("app.services.lab_governance._redis_client", lambda settings: None),
            patch("app.services.demo_users._redis_client", lambda settings: None),
            patch("app.services.lab_governance._ensure_user_home_pvc", lambda settings, username, disk_gib: "lab-home-test1"),
        ]
        for patcher in self.patches:
            patcher.start()

    def tearDown(self) -> None:
        for patcher in reversed(self.patches):
            patcher.stop()

    def test_resource_and_environment_approval_flow_builds_launch_profile(self) -> None:
        settings = get_settings()

        resource_request = lab_governance.submit_resource_request(
            settings=settings,
            username="test1@test.com",
            vcpu=2,
            memory_gib=1,
            disk_gib=10,
            note="Need private notebook resources",
        )
        reviewed_resource = lab_governance.review_resource_request(
            settings=settings,
            request_id=str(resource_request["request_id"]),
            approved=True,
            reviewed_by="admin@test.com",
            note="Approved for pilot",
        )
        self.assertEqual(reviewed_resource["status"], "approved")
        self.assertEqual(reviewed_resource["pvc_name"], "lab-home-test1")

        lab_governance.upsert_analysis_environment(
            settings=settings,
            env_id="jupyter-teradata-extension",
            name="Jupyter Teradata Extension",
            image="harbor.local/data-platform/jupyter-teradata-extension:latest",
            description="default",
            gpu_enabled=False,
            is_active=True,
            updated_by="admin@test.com",
        )

        env_request = lab_governance.submit_environment_request(
            settings=settings,
            username="test1@test.com",
            env_id="jupyter-teradata-extension",
            note="Use default env",
        )
        reviewed_env = lab_governance.review_environment_request(
            settings=settings,
            request_id=str(env_request["request_id"]),
            approved=True,
            reviewed_by="admin@test.com",
            note="Approved",
        )
        self.assertEqual(reviewed_env["status"], "approved")

        policy = lab_governance.get_user_lab_policy(settings, "test1@test.com")
        self.assertTrue(policy["ready"])
        self.assertEqual(policy["pvc_name"], "lab-home-test1")
        self.assertEqual(policy["analysis_env_id"], "jupyter-teradata-extension")

        launch_profile = lab_governance.get_user_lab_launch_profile(settings, "test1@test.com")
        self.assertEqual(launch_profile["pvc_name"], "lab-home-test1")
        self.assertEqual(launch_profile["cpu_limit"], "2")
        self.assertEqual(launch_profile["memory_limit"], "1Gi")


if __name__ == "__main__":
    unittest.main(verbosity=2)
