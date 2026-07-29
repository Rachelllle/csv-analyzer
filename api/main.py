"""API FastAPI : reçoit les uploads CSV, enregistre les jobs, les met en file, sert les rapports."""
from __future__ import annotations

import logging
import os
import tempfile
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

import redis
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from rq import Queue

import db
from logging_conf import configure_logging
from models import HealthResponse, JobCreatedResponse, JobDetail, JobListResponse, JobSummary
from storage import get_storage

logger = logging.getLogger("api")

MAX_UPLOAD_SIZE_BYTES = int(os.environ.get("MAX_UPLOAD_SIZE_MB", "200")) * 1024 * 1024
UPLOAD_CHUNK_SIZE = 1024 * 1024

_redis_conn: redis.Redis | None = None
_queue: Queue | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_logging("api")
    db.init_schema()
    global _redis_conn, _queue
    _redis_conn = redis.from_url(os.environ["REDIS_URL"])
    _queue = Queue("csv_jobs", connection=_redis_conn)
    logger.info("api_started")
    yield
    db.close_pool()
    logger.info("api_stopped")


app = FastAPI(title="CSV Analyzer API", lifespan=lifespan)

FRONTEND_INDEX = Path(__file__).parent / "frontend" / "index.html"


@app.get("/")
def serve_frontend():
    if FRONTEND_INDEX.exists():
        return FileResponse(FRONTEND_INDEX)
    raise HTTPException(status_code=404, detail="Frontend introuvable")


@app.post("/jobs", status_code=202, response_model=JobCreatedResponse)
async def create_job(file: UploadFile = File(...)):
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=400, detail="Seuls les fichiers .csv sont acceptés")

    job_id = str(uuid.uuid4())
    s3_key = f"{job_id}/{file.filename}"

    # On matérialise l'upload dans un fichier temporaire en respectant la taille max,
    # avant de le transmettre au backend de stockage (local ou S3).
    total_size = 0
    with tempfile.NamedTemporaryFile(delete=False, suffix=".csv") as tmp:
        tmp_path = Path(tmp.name)
        while chunk := await file.read(UPLOAD_CHUNK_SIZE):
            total_size += len(chunk)
            if total_size > MAX_UPLOAD_SIZE_BYTES:
                tmp.close()
                tmp_path.unlink(missing_ok=True)
                raise HTTPException(status_code=413, detail="Fichier trop volumineux")
            tmp.write(chunk)

    try:
        storage = get_storage()
        with open(tmp_path, "rb") as f:
            storage.upload(s3_key, f)
    finally:
        tmp_path.unlink(missing_ok=True)

    db.insert_job(job_id, file.filename, s3_key)
    _queue.enqueue("tasks.process_job", job_id, job_timeout="30m")

    logger.info("job_created", extra={"job_id": job_id, "csv_filename": file.filename, "size_bytes": total_size})
    return JobCreatedResponse(job_id=job_id, status="pending")


@app.get("/jobs", response_model=JobListResponse)
def get_jobs(limit: int = 20, offset: int = 0):
    limit = max(1, min(limit, 100))
    offset = max(0, offset)
    rows, total = db.list_jobs(limit, offset)
    return JobListResponse(
        items=[JobSummary(**row) for row in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@app.get("/jobs/{job_id}", response_model=JobDetail)
def get_job(job_id: str):
    job = db.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job introuvable")
    return JobDetail(**job)


@app.delete("/jobs/{job_id}", status_code=204)
def delete_job(job_id: str):
    row = db.delete_job(job_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Job introuvable")
    try:
        get_storage().delete(row["s3_key"])
    except Exception:
        logger.warning("s3_delete_failed", extra={"job_id": job_id})
    return None


@app.get("/health", response_model=HealthResponse)
def health():
    postgres_ok = db.health_check()
    redis_ok = False
    try:
        redis_ok = bool(_redis_conn and _redis_conn.ping())
    except Exception:
        redis_ok = False

    status_code = 200 if (postgres_ok and redis_ok) else 503
    response = HealthResponse(
        status="ok" if (postgres_ok and redis_ok) else "degraded",
        postgres=postgres_ok,
        redis=redis_ok,
    )
    if status_code != 200:
        raise HTTPException(status_code=503, detail=response.model_dump())
    return response
