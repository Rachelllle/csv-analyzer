from pathlib import Path

import pytest

from profiling import InvalidCSVError, load_csv, profile_column, profile_dataframe


def _write_csv(tmp_path: Path, content: str) -> Path:
    path = tmp_path / "test.csv"
    path.write_text(content, encoding="utf-8")
    return path


def test_type_inference(tmp_path: Path) -> None:
    csv_path = _write_csv(
        tmp_path,
        "id,age,city\n1,30,Paris\n2,25,Lyon\n",
    )
    df = load_csv(csv_path)

    assert df["id"].dtype == "int64"
    assert df["age"].dtype == "int64"
    assert df["city"].dtype == "object"


def test_postal_code_leading_zero_is_lost_to_int_inference(tmp_path: Path) -> None:
    # Piège CSV classique : une colonne de codes postaux tout en chiffres
    # ("01000") est lue par pandas comme un entier, le zéro initial est donc
    # perdu. Ce test documente ce comportement réel plutôt que de le corriger,
    # pour qu'il soit visible et volontaire plutôt que découvert en prod.
    csv_path = _write_csv(
        tmp_path,
        "postal_code\n01000\n02000\n75001\n",
    )
    df = load_csv(csv_path)

    assert df["postal_code"].dtype == "int64"
    assert df["postal_code"].iloc[0] == 1000  # et non "01000"


def test_missing_values_are_counted(tmp_path: Path) -> None:
    csv_path = _write_csv(
        tmp_path,
        "name,age\nAlice,30\nBob,\nCharlie,25\nDave,\n",
    )
    df = load_csv(csv_path)

    stats = profile_column(df["age"])

    assert stats["null_count"] == 2
    assert stats["null_pct"] == pytest.approx(50.0)


def test_duplicate_rows_are_detected(tmp_path: Path) -> None:
    csv_path = _write_csv(
        tmp_path,
        "name,age\nAlice,30\nBob,25\nAlice,30\n",
    )
    df = load_csv(csv_path)

    report = profile_dataframe(df)

    # 2 lignes identiques -> 1 doublon (pandas.duplicated() ne compte pas
    # la première occurrence).
    assert report["duplicate_count"] == 1
    assert report["row_count"] == 3


def test_invalid_csv_raises(tmp_path: Path) -> None:
    csv_path = _write_csv(tmp_path, "")

    with pytest.raises(InvalidCSVError):
        load_csv(csv_path)
