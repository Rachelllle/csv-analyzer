"""Tâches RQ exécutées par le worker. Un CSV invalide fait échouer le job proprement,
sans jamais laisser une exception remonter et crasher le process worker."""
from __future__ import annotations

import logging

import db
from profiling import InvalidCSVError, load_csv, profile_dataframe
from storage import get_storage

logger = logging.getLogger("worker")


def process_job(job_id: str) -> None:
    job = db.get_job(job_id)
    if job is None:
        logger.error("job_not_found", extra={"job_id": job_id})
        return

    db.mark_running(job_id)
    logger.info("job_started", extra={"job_id": job_id})

    storage = get_storage()
    tmp_path = None
    try:
        tmp_path = storage.download_to_tmp(job["s3_key"])
        file_size_bytes = tmp_path.stat().st_size

        df = load_csv(tmp_path)
        report = profile_dataframe(df)

        db.save_report(
            job_id=job_id,
            row_count=report["row_count"],
            column_count=report["column_count"],
            duplicate_count=report["duplicate_count"],
            file_size_bytes=file_size_bytes,
            columns=report["columns"],
        )
        logger.info(
            "job_done",
            extra={"job_id": job_id, "row_count": report["row_count"], "column_count": report["column_count"]},
        )
    except InvalidCSVError as exc:
        db.mark_failed(job_id, str(exc))
        logger.warning("job_failed_invalid_csv", extra={"job_id": job_id, "error": str(exc)})
    except Exception as exc:  # noqa: BLE001 - on isole toute erreur pour ne pas crasher le worker
        db.mark_failed(job_id, f"Erreur interne lors du traitement : {exc}")
        logger.error("job_failed_unexpected", extra={"job_id": job_id, "error": str(exc)})
    finally:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)
