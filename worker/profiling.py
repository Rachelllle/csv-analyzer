"""Analyse d'un CSV avec pandas. Fonctions pures, testables sans Redis/DB/S3."""
from __future__ import annotations

from pathlib import Path
from typing import Any

import pandas as pd


class InvalidCSVError(Exception):
    """Levée quand le fichier ne peut pas être interprété comme un CSV exploitable."""


def load_csv(path: Path) -> pd.DataFrame:
    try:
        df = pd.read_csv(path)
    except pd.errors.EmptyDataError as exc:
        raise InvalidCSVError("Le fichier CSV est vide") from exc
    except pd.errors.ParserError as exc:
        raise InvalidCSVError(f"Erreur de parsing CSV : {exc}") from exc
    except UnicodeDecodeError as exc:
        raise InvalidCSVError("Encodage du fichier non supporté (utf-8 attendu)") from exc

    if df.shape[1] == 0:
        raise InvalidCSVError("Aucune colonne détectée dans le fichier")

    return df


def profile_column(series: pd.Series) -> dict[str, Any]:
    total = len(series)
    null_count = int(series.isna().sum())
    null_pct = round((null_count / total * 100) if total else 0.0, 2)
    non_null = series.dropna()
    unique_count = int(non_null.nunique())

    mean = std = min_ = max_ = None
    if pd.api.types.is_numeric_dtype(series) and not non_null.empty:
        mean = float(non_null.mean())
        std = float(non_null.std()) if len(non_null) > 1 else 0.0
        min_ = float(non_null.min())
        max_ = float(non_null.max())

    top_value = None
    if not non_null.empty:
        mode = non_null.mode()
        if not mode.empty:
            top_value = str(mode.iloc[0])[:500]

    return {
        "column_name": str(series.name),
        "dtype": str(series.dtype),
        "null_count": null_count,
        "null_pct": null_pct,
        "unique_count": unique_count,
        "mean": mean,
        "std": std,
        "min": min_,
        "max": max_,
        "top_value": top_value,
    }


def profile_dataframe(df: pd.DataFrame) -> dict[str, Any]:
    return {
        "row_count": int(len(df)),
        "column_count": int(len(df.columns)),
        "duplicate_count": int(df.duplicated().sum()),
        "columns": [profile_column(df[col]) for col in df.columns],
    }
