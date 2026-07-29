"""Point d'entrée du worker RQ : écoute la file 'csv_jobs' et traite les jobs."""
from __future__ import annotations

import os

import redis
from rq import Queue, Worker

from logging_conf import configure_logging

logger = configure_logging("worker")


def main() -> None:
    conn = redis.from_url(os.environ["REDIS_URL"])
    queue = Queue("csv_jobs", connection=conn)
    logger.info("worker_started")
    worker = Worker([queue], connection=conn)
    worker.work(with_scheduler=False)


if __name__ == "__main__":
    main()
