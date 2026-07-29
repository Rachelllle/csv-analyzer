"""Accès Postgres pour l'API : pool de connexions et requêtes SQL brutes (pas d'ORM)."""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from psycopg_pool import ConnectionPool
from psycopg.rows import dict_row

_pool: ConnectionPool | None = None


def _dsn() -> str:
    return (
        f"host={os.environ['POSTGRES_HOST']} "
        f"port={os.environ.get('POSTGRES_PORT', '5432')} "
        f"dbname={os.environ['POSTGRES_DB']} "
        f"user={os.environ['POSTGRES_USER']} "
        f"password={os.environ['POSTGRES_PASSWORD']}"
    )


def get_pool() -> ConnectionPool:
    global _pool
    if _pool is None:
        _pool = ConnectionPool(conninfo=_dsn(), min_size=1, max_size=10, open=True)
    return _pool


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


def init_schema() -> None:
    schema_path = Path(__file__).parent / "schema.sql"
    ddl = schema_path.read_text(encoding="utf-8")
    with get_pool().connection() as conn:
        conn.execute(ddl)


def health_check() -> bool:
    try:
        with get_pool().connection() as conn:
            conn.execute("SELECT 1")
        return True
    except Exception:
        return False


def insert_job(job_id: str, filename: str, s3_key: str) -> None:
    with get_pool().connection() as conn:
        conn.execute(
            "INSERT INTO jobs (id, filename, s3_key, status) VALUES (%s, %s, %s, 'pending')",
            (job_id, filename, s3_key),
        )


def list_jobs(limit: int, offset: int) -> tuple[list[dict[str, Any]], int]:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT id::text, filename, status, error, row_count, column_count,
                       duplicate_count, file_size_bytes, created_at, started_at, finished_at
                FROM jobs
                ORDER BY created_at DESC
                LIMIT %s OFFSET %s
                """,
                (limit, offset),
            )
            rows = cur.fetchall()
            cur.execute("SELECT COUNT(*) AS total FROM jobs")
            total = cur.fetchone()["total"]
    return rows, total


def get_job(job_id: str) -> dict[str, Any] | None:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT id::text, filename, s3_key, status, error, row_count, column_count,
                       duplicate_count, file_size_bytes, created_at, started_at, finished_at
                FROM jobs WHERE id = %s
                """,
                (job_id,),
            )
            job = cur.fetchone()
            if job is None:
                return None
            cur.execute(
                """
                SELECT column_name, dtype, null_count, null_pct, unique_count,
                       mean, std, min, max, top_value
                FROM column_stats WHERE job_id = %s
                ORDER BY id
                """,
                (job_id,),
            )
            job["columns"] = cur.fetchall()
    return job


def delete_job(job_id: str) -> dict[str, Any] | None:
    """Supprime le job en base et retourne sa ligne (pour connaître s3_key), ou None si absent."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("DELETE FROM jobs WHERE id = %s RETURNING id, s3_key", (job_id,))
            row = cur.fetchone()
    return row
