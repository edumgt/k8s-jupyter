#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT_DIR = Path(__file__).resolve().parents[1]
BACKEND_DIR = ROOT_DIR / "apps" / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.services.teradata import run_ansi_query, teradata_summary
from app.services.teradata_bootstrap import run_teradata_bootstrap


class _FakeCursor:
    def __init__(self) -> None:
        self.description = [("workload_name",), ("workload_status",)]
        self.executed: list[str] = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return None

    def execute(self, sql: str) -> None:
        self.executed.append(sql)

    def fetchmany(self, limit: int):
        rows = [
            ("daily-sync", "RUNNING"),
            ("inventory-refresh", "IDLE"),
        ]
        return rows[:limit]


class _FakeConnection:
    def __init__(self) -> None:
        self.cursor_instance = _FakeCursor()
        self.closed = False
        self.committed = False

    def cursor(self):
        return self.cursor_instance

    def commit(self) -> None:
        self.committed = True

    def close(self) -> None:
        self.closed = True


class _FakeSqlAlchemyResult:
    def __init__(self) -> None:
        self._rows = [
            {"workload_name": "daily-sync", "workload_status": "RUNNING"},
            {"workload_name": "inventory-refresh", "workload_status": "IDLE"},
        ]

    def keys(self) -> list[str]:
        return ["workload_name", "workload_status"]

    def mappings(self):
        return self

    def fetchmany(self, limit: int):
        return self._rows[:limit]


class _FakeSqlAlchemyConnection:
    def __init__(self) -> None:
        self.executed: list[str] = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return None

    def execute(self, statement):
        self.executed.append(str(statement))
        return _FakeSqlAlchemyResult()


class _FakeSqlAlchemyEngine:
    def __init__(self) -> None:
        self.connection = _FakeSqlAlchemyConnection()
        self.disposed = False

    def connect(self):
        return self.connection

    def dispose(self) -> None:
        self.disposed = True


class TeradataPostgresMockModeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.settings = types.SimpleNamespace(
            teradata_fake_mode=False,
            teradata_dbms="postgres",
            teradata_host="teradata-mock-postgres",
            teradata_port=5432,
            teradata_user="td_mock_user",
            teradata_password="td_mock_password",
            teradata_database="teradata_mock",
            teradata_encryptdata=False,
            teradata_bootstrap_sql_path=None,
        )

    def _psycopg_module(self, connection: _FakeConnection):
        module = types.SimpleNamespace()
        module.connect = lambda **kwargs: connection
        return module

    def test_summary_reports_postgres_mock_live_mode(self) -> None:
        summary = teradata_summary(self.settings)
        self.assertEqual(summary["mode"], "postgres-mock-live")
        self.assertIn("teradata-mock-postgres:5432/teradata_mock", summary["note"])

    def test_run_ansi_query_uses_postgres_driver(self) -> None:
        fake_engine = _FakeSqlAlchemyEngine()
        with patch("sqlalchemy.create_engine", return_value=fake_engine):
            result = run_ansi_query(self.settings, "SELECT workload_name, workload_status FROM t", 2)

        self.assertEqual(result["source"], "postgres")
        self.assertEqual(result["columns"], ["workload_name", "workload_status"])
        self.assertEqual(len(result["rows"]), 2)
        self.assertTrue(fake_engine.disposed)
        self.assertTrue(fake_engine.connection.executed)
        self.assertIn("SQLAlchemy", result["note"])

    def test_bootstrap_executes_mock_sql_on_postgres_driver(self) -> None:
        conn = _FakeConnection()
        fake_psycopg = self._psycopg_module(conn)
        with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as sql_file:
            sql_file.write(
                "--@@\nCREATE TABLE IF NOT EXISTS t1 (id INT);\n"
                "--@@\nINSERT INTO t1 (id) VALUES (1);\n"
            )
            sql_path = sql_file.name

        self.settings.teradata_bootstrap_sql_path = sql_path

        try:
            with patch.dict(sys.modules, {"psycopg": fake_psycopg}):
                result = run_teradata_bootstrap(self.settings, dry_run=False)
        finally:
            Path(sql_path).unlink(missing_ok=True)

        self.assertEqual(result["executed_count"], 2)
        self.assertIn("postgres", result["note"])
        self.assertTrue(conn.committed)
        self.assertTrue(conn.closed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
