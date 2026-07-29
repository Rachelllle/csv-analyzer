-- Schéma de la base. Appliqué au démarrage de l'API (CREATE TABLE IF NOT EXISTS, idempotent).
-- Les UUID de job sont générés côté application (uuid4), pas par Postgres,
-- pour ne dépendre d'aucune extension serveur.

CREATE TABLE IF NOT EXISTS jobs (
    id              UUID PRIMARY KEY,
    filename        TEXT NOT NULL,
    s3_key          TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'running', 'done', 'failed')),
    error           TEXT,
    row_count       INTEGER,
    column_count    INTEGER,
    duplicate_count INTEGER,
    file_size_bytes BIGINT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at      TIMESTAMPTZ,
    finished_at     TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS column_stats (
    id           SERIAL PRIMARY KEY,
    job_id       UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    column_name  TEXT NOT NULL,
    dtype        TEXT NOT NULL,
    null_count   INTEGER NOT NULL,
    null_pct     NUMERIC(6, 2) NOT NULL,
    unique_count INTEGER NOT NULL,
    mean         DOUBLE PRECISION,
    std          DOUBLE PRECISION,
    min          DOUBLE PRECISION,
    max          DOUBLE PRECISION,
    top_value    TEXT
);

CREATE INDEX IF NOT EXISTS idx_column_stats_job_id ON column_stats (job_id);
CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs (created_at DESC);
