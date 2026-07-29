# CSV Analyzer

Mini-plateforme d'analyse de fichiers CSV : upload asynchrone, traitement en
arrière-plan avec pandas, consultation du rapport via API et page web.

## Stack

- **API** : FastAPI + uvicorn (Python 3.11)
- **Worker** : RQ (Redis Queue) + pandas
- **File d'attente** : Redis
- **Base** : PostgreSQL, accès via psycopg (SQL brut, pas d'ORM)
- **Fichiers** : backend local (dev) ou S3 via boto3 (prod)
- **Front** : une page HTML statique + fetch, sans framework

## Démarrage

```bash
cp .env.example .env
# éditer .env : au minimum POSTGRES_PASSWORD

docker compose up --build
```

- Frontend : http://localhost:8000/
- API : http://localhost:8000
- Health check : http://localhost:8000/health

Arrêter :

```bash
docker compose down
```

Arrêter et supprimer les volumes (repart de zéro) :

```bash
docker compose down -v
```

## Endpoints

| Méthode | Route          | Description                                      |
|---------|----------------|---------------------------------------------------|
| POST    | `/jobs`        | Upload multipart d'un CSV, crée le job, renvoie 202 + `job_id` |
| GET     | `/jobs`        | Liste paginée (`?limit=&offset=`)                 |
| GET     | `/jobs/{id}`   | Statut du job, et rapport complet si `status=done` |
| DELETE  | `/jobs/{id}`   | Supprime le job en base et le fichier associé      |
| GET     | `/health`      | 200 seulement si Postgres et Redis répondent        |

## Utiliser le stockage S3 en local

Par défaut `STORAGE_BACKEND=local` : les fichiers sont écrits dans le volume
Docker `uploads`, monté sur `/data/uploads` dans l'API et le worker.

Pour tester avec S3, dans `.env` :

```
STORAGE_BACKEND=s3
S3_BUCKET=mon-bucket
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=eu-west-1
```

`S3_ENDPOINT_URL` peut pointer vers un serveur compatible S3 (ex: MinIO) pour
tester sans compte AWS réel.

## Développement sans Docker

Chaque service (`api/`, `worker/`) a son propre `requirements.txt`. Lancer
Postgres et Redis localement (ou via `docker compose up postgres redis`),
renseigner `.env` avec `POSTGRES_HOST=localhost` et
`REDIS_URL=redis://localhost:6379/0`, puis :

```bash
cd api && pip install -r requirements.txt && uvicorn main:app --reload
cd worker && pip install -r requirements.txt && python worker.py
```

## Comportement en cas de CSV invalide

Le worker capture toute erreur de lecture (fichier vide, encodage non
supporté, erreur de parsing) : le job passe en `status=failed` avec un
message d'erreur en base, et le process worker continue de tourner pour les
jobs suivants.

## Logs

Les deux services émettent des logs JSON structurés sur stdout
(`timestamp`, `level`, `logger`, `message`, champs additionnels comme
`job_id`). Le contenu des fichiers CSV n'est jamais journalisé.
