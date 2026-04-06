#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
BACKEND_DIR = ROOT_DIR / "apps" / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.services.teradata_bootstrap import _extract_statements, _split_sql_statements


class TeradataBootstrapSqlTests(unittest.TestCase):
    def test_split_sql_statements_ignores_comments_and_quoted_semicolons(self) -> None:
        sql = """
        -- this comment should be ignored;
        CREATE TABLE t1 (id INTEGER);
        INSERT INTO t1 VALUES ('a;b');
        /* block comment; should be ignored */
        INSERT INTO t1 VALUES ('c'';d');
        """

        statements = _split_sql_statements(sql)
        self.assertEqual(len(statements), 3)
        self.assertTrue(statements[0].strip().startswith("CREATE TABLE t1"))
        self.assertIn("VALUES ('a;b')", statements[1])
        self.assertIn("VALUES ('c'';d')", statements[2])

    def test_extract_statements_preserves_procedure_block_with_marker(self) -> None:
        sql = """
        -- header
        --@@
        REPLACE PROCEDURE sp_demo()
        BEGIN
          INSERT INTO t1 VALUES (1);
          INSERT INTO t1 VALUES (2);
        END;
        --@@
        INSERT INTO t1 VALUES (3);
        """

        statements = _extract_statements(sql)
        self.assertEqual(len(statements), 2)
        self.assertIn("REPLACE PROCEDURE sp_demo()", statements[0])
        self.assertIn("INSERT INTO t1 VALUES (2);", statements[0])
        self.assertIn("INSERT INTO t1 VALUES (3)", statements[1])


if __name__ == "__main__":
    unittest.main(verbosity=2)
