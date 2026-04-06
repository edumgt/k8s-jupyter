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
from app.services import demo_users


class ManagedUserAuthTests(unittest.TestCase):
    def setUp(self) -> None:
        get_settings.cache_clear()
        demo_users._memory_managed_users.clear()
        demo_users._memory_metrics.clear()
        self.redis_patch = patch("app.services.demo_users._redis_client", lambda settings: None)
        self.redis_patch.start()

    def tearDown(self) -> None:
        self.redis_patch.stop()

    def test_create_and_authenticate_managed_user(self) -> None:
        settings = get_settings()
        created = demo_users.create_managed_user(
            settings=settings,
            username="new-user@test.com",
            password="pass1234",
            role="user",
            display_name="New User",
        )
        self.assertEqual(created["username"], "new-user@test.com")
        self.assertEqual(created["role"], "user")

        authed = demo_users.authenticate_demo_user("new-user@test.com", "pass1234", settings)
        self.assertEqual(authed.username, "new-user@test.com")
        self.assertEqual(authed.display_name, "New User")


if __name__ == "__main__":
    unittest.main(verbosity=2)
