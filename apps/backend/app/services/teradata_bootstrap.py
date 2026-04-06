from __future__ import annotations

from pathlib import Path
from typing import Any

from app.config import Settings

SPLIT_MARKER = "--@@"


def _default_sql_path() -> Path:
    return Path(__file__).resolve().parents[1] / "sql" / "teradata" / "bootstrap.sql"


def _resolve_sql_path(settings: Settings) -> Path:
    if settings.teradata_bootstrap_sql_path:
        return Path(settings.teradata_bootstrap_sql_path)
    return _default_sql_path()


def _statement_preview(sql: str, limit: int = 140) -> str:
    flattened = " ".join(sql.split())
    if len(flattened) <= limit:
        return flattened
    return f"{flattened[: limit - 3]}..."


def _strip_trailing_semicolon(sql: str) -> str:
    trimmed = sql.strip()
    if trimmed.endswith(";"):
        return trimmed[:-1].rstrip()
    return trimmed


def _split_sql_statements(text: str) -> list[str]:
    statements: list[str] = []
    buffer: list[str] = []

    in_single = False
    in_double = False
    in_line_comment = False
    in_block_comment = False

    i = 0
    size = len(text)

    while i < size:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < size else ""

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
                buffer.append(ch)
            i += 1
            continue

        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
            else:
                i += 1
            continue

        if in_single:
            buffer.append(ch)
            if ch == "'" and nxt == "'":
                buffer.append(nxt)
                i += 2
                continue
            if ch == "'":
                in_single = False
            i += 1
            continue

        if in_double:
            buffer.append(ch)
            if ch == '"' and nxt == '"':
                buffer.append(nxt)
                i += 2
                continue
            if ch == '"':
                in_double = False
            i += 1
            continue

        if ch == "-" and nxt == "-":
            in_line_comment = True
            i += 2
            continue

        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue

        if ch == "'":
            in_single = True
            buffer.append(ch)
            i += 1
            continue

        if ch == '"':
            in_double = True
            buffer.append(ch)
            i += 1
            continue

        if ch == ";":
            statement = _strip_trailing_semicolon("".join(buffer))
            if statement:
                statements.append(statement)
            buffer = []
            i += 1
            continue

        buffer.append(ch)
        i += 1

    tail = _strip_trailing_semicolon("".join(buffer))
    if tail:
        statements.append(tail)

    return statements


def _extract_statements(sql_text: str) -> list[str]:
    if SPLIT_MARKER in sql_text:
        chunks = []
        for part in sql_text.split(SPLIT_MARKER)[1:]:
            chunk = _strip_trailing_semicolon(part)
            if chunk:
                chunks.append(chunk)
        return chunks

    return _split_sql_statements(sql_text)


def _validate_bootstrap_target(settings: Settings) -> None:
    if settings.teradata_fake_mode:
        raise ValueError(
            "PLATFORM_TERADATA_FAKE_MODE is true. Disable fake mode to run Teradata bootstrap."
        )

    missing = [
        name
        for name, value in (
            ("PLATFORM_TERADATA_HOST", settings.teradata_host),
            ("PLATFORM_TERADATA_USER", settings.teradata_user),
            ("PLATFORM_TERADATA_PASSWORD", settings.teradata_password),
        )
        if not value
    ]
    if missing:
        joined = ", ".join(missing)
        raise ValueError(f"Missing required Teradata settings: {joined}")


def run_teradata_bootstrap(settings: Settings, dry_run: bool = True) -> dict[str, Any]:
    _validate_bootstrap_target(settings)

    sql_path = _resolve_sql_path(settings)
    if not sql_path.exists():
        raise RuntimeError(f"Bootstrap SQL file not found: {sql_path}")

    sql_text = sql_path.read_text(encoding="utf-8")
    statements = _extract_statements(sql_text)
    if not statements:
        raise RuntimeError(
            "No executable statements were found in the bootstrap SQL file. "
            f"Use '{SPLIT_MARKER}' separators or semicolon-terminated SQL statements."
        )

    previews = [_statement_preview(statement) for statement in statements[:10]]

    if dry_run:
        return {
            "mode": "dry-run",
            "source_file": str(sql_path),
            "statement_count": len(statements),
            "executed_count": 0,
            "dry_run": True,
            "statement_previews": previews,
            "note": "Dry-run succeeded. Set dry_run=false to execute bootstrap statements.",
        }

    try:
        import teradatasql
    except ImportError as exc:  # pragma: no cover - import availability depends on runtime image
        raise RuntimeError(f"teradatasql import failed: {exc}") from exc

    connection = None
    executed_count = 0

    try:
        connection = teradatasql.connect(
            host=settings.teradata_host,
            user=settings.teradata_user,
            password=settings.teradata_password,
            database=settings.teradata_database,
            encryptdata="true" if settings.teradata_encryptdata else "false",
        )
        with connection.cursor() as cursor:
            for index, statement in enumerate(statements, start=1):
                try:
                    cursor.execute(statement)
                    executed_count += 1
                except Exception as exc:  # noqa: BLE001
                    preview = _statement_preview(statement)
                    raise RuntimeError(
                        f"Bootstrap failed at statement #{index}: {exc}. Statement preview: {preview}"
                    ) from exc

        try:
            connection.commit()
        except Exception:  # noqa: BLE001 - autocommit driver implementations may not expose commit
            pass

        return {
            "mode": "executed",
            "source_file": str(sql_path),
            "statement_count": len(statements),
            "executed_count": executed_count,
            "dry_run": False,
            "statement_previews": previews,
            "note": "Teradata bootstrap statements were executed successfully.",
        }
    except RuntimeError:
        raise
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError(f"Teradata bootstrap failed: {exc}") from exc
    finally:
        if connection is not None:
            connection.close()
