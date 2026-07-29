"""Abstraction de stockage des fichiers uploadés : backend local (dev) ou S3 (prod).

Le choix se fait via la variable d'environnement STORAGE_BACKEND=local|s3.
"""
from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path
from typing import BinaryIO, Protocol

import boto3
from botocore.client import Config as BotoConfig


class Storage(Protocol):
    def upload(self, key: str, fileobj: BinaryIO) -> None:
        """Envoie le contenu de fileobj (positionné au début) sous la clé donnée."""

    def download_to_tmp(self, key: str) -> Path:
        """Télécharge l'objet vers un fichier temporaire local et retourne son chemin."""

    def delete(self, key: str) -> None:
        """Supprime l'objet. Ne lève pas d'erreur si absent."""


class LocalStorage:
    def __init__(self, base_path: str) -> None:
        self.base_path = Path(base_path)
        self.base_path.mkdir(parents=True, exist_ok=True)

    def _resolve(self, key: str) -> Path:
        # Empêche toute évasion du répertoire de base (ex: key = "../../etc/passwd")
        path = (self.base_path / key).resolve()
        if self.base_path.resolve() not in path.parents and path != self.base_path.resolve():
            raise ValueError("Clé de stockage invalide")
        return path

    def upload(self, key: str, fileobj: BinaryIO) -> None:
        dest = self._resolve(key)
        dest.parent.mkdir(parents=True, exist_ok=True)
        fileobj.seek(0)
        with open(dest, "wb") as out:
            shutil.copyfileobj(fileobj, out)

    def download_to_tmp(self, key: str) -> Path:
        src = self._resolve(key)
        fd, tmp_path = tempfile.mkstemp(suffix=".csv")
        os.close(fd)
        shutil.copyfile(src, tmp_path)
        return Path(tmp_path)

    def delete(self, key: str) -> None:
        path = self._resolve(key)
        path.unlink(missing_ok=True)


class S3Storage:
    def __init__(self, bucket: str, endpoint_url: str | None = None) -> None:
        self.bucket = bucket
        self.client = boto3.client(
            "s3",
            endpoint_url=endpoint_url or None,
            config=BotoConfig(signature_version="s3v4"),
        )

    def upload(self, key: str, fileobj: BinaryIO) -> None:
        fileobj.seek(0)
        self.client.upload_fileobj(fileobj, self.bucket, key)

    def download_to_tmp(self, key: str) -> Path:
        fd, tmp_path = tempfile.mkstemp(suffix=".csv")
        os.close(fd)
        self.client.download_file(self.bucket, key, tmp_path)
        return Path(tmp_path)

    def delete(self, key: str) -> None:
        self.client.delete_object(Bucket=self.bucket, Key=key)


def get_storage() -> Storage:
    backend = os.environ.get("STORAGE_BACKEND", "local").lower()
    if backend == "local":
        return LocalStorage(os.environ.get("LOCAL_STORAGE_PATH", "/data/uploads"))
    if backend == "s3":
        bucket = os.environ["S3_BUCKET"]
        endpoint_url = os.environ.get("S3_ENDPOINT_URL")
        return S3Storage(bucket=bucket, endpoint_url=endpoint_url)
    raise ValueError(f"STORAGE_BACKEND inconnu: {backend}")
