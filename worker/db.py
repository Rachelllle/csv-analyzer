"""Accès Postgres pour le worker : lecture du job, mise à jour du statut, écriture du rapport."""
from __future__ import annotations

import os
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
        _pool = ConnectionPool(conninfo=_dsn(), min_size=1, max_size=5, open=True)
    return _pool


def get_job(job_id: str) -> dict[str, Any] | None:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT id, filename, s3_key FROM jobs WHERE id = %s", (job_id,))
            return cur.fetchone()


def mark_running(job_id: str) -> None:
    with get_pool().connection() as conn:
        conn.execute(
            "UPDATE jobs SET status = 'running', started_at = now() WHERE id = %s",
            (job_id,),
        )


def mark_failed(job_id: str, error: str) -> None:
    with get_pool().connection() as conn:
        conn.execute(
            "UPDATE jobs SET status = 'failed', error = %s, finished_at = now() WHERE id = %s",
            (error[:2000], job_id),
        )


def save_report(
    job_id: str,
    row_count: int,
    column_count: int,
    duplicate_count: int,
    file_size_bytes: int,
    columns: list[dict[str, Any]],
) -> None:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE jobs
                SET status = 'done', row_count = %s, column_count = %s,
                    duplicate_count = %s, file_size_bytes = %s, finished_at = now()
                WHERE id = %s
                """,
                (row_count, column_count, duplicate_count, file_size_bytes, job_id),
            )
            cur.executemany(
                """
                INSERT INTO column_stats
                    (job_id, column_name, dtype, null_count, null_pct, unique_count,
                     mean, std, min, max, top_value)
                VALUES (%(job_id)s, %(column_name)s, %(dtype)s, %(null_count)s, %(null_pct)s,
                        %(unique_count)s, %(mean)s, %(std)s, %(min)s, %(max)s, %(top_value)s)
                """,
                [{**col, "job_id": job_id} for col in columns],
            )
