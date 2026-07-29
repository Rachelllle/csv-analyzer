# syntax=docker/dockerfile:1
#
# Contexte de build : la racine du repo (pas ./api), pour pouvoir COPY
# frontend/ en plus du code api/. Build avec :
#   docker build -f api/Dockerfile -t csv-analyzer-api .

FROM python:3.11-slim AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY api/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.11-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends libpq5 curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 appuser \
    && useradd --uid 1000 --gid appuser --shell /usr/sbin/nologin --create-home appuser

WORKDIR /app

COPY --from=builder /root/.local /home/appuser/.local
COPY --chown=appuser:appuser api/ .
# Frontend statique intégré à l'image : le conteneur redevient immuable
# (un déploiement = une image = un frontend), plus de montage volume ni de
# copie séparée par le pipeline.
COPY --chown=appuser:appuser frontend/ ./frontend/

RUN mkdir -p /data/uploads && chown -R appuser:appuser /data/uploads

ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER appuser

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
