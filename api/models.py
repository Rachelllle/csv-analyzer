"""Modèles Pydantic pour les réponses de l'API (pas de couche ORM)."""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class JobCreatedResponse(BaseModel):
    job_id: str
    status: str


class JobSummary(BaseModel):
    id: str
    filename: str
    status: str
    error: str | None = None
    row_count: int | None = None
    column_count: int | None = None
    duplicate_count: int | None = None
    file_size_bytes: int | None = None
    created_at: datetime
    started_at: datetime | None = None
    finished_at: datetime | None = None


class JobListResponse(BaseModel):
    items: list[JobSummary]
    total: int
    limit: int
    offset: int


class ColumnStat(BaseModel):
    column_name: str
    dtype: str
    null_count: int
    null_pct: float
    unique_count: int
    mean: float | None = None
    std: float | None = None
    min: float | None = None
    max: float | None = None
    top_value: str | None = None


class JobDetail(JobSummary):
    columns: list[ColumnStat] = []


class HealthResponse(BaseModel):
    status: str
    postgres: bool
    redis: bool
