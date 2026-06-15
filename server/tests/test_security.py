from pathlib import Path

from app.core.security import safe_upload_path, sanitize_filename


def test_sanitize_filename_strips_path_segments() -> None:
    assert sanitize_filename("../../secret.txt") == "secret.txt"
    assert sanitize_filename(r"..\secret.txt") == ".._secret.txt"


def test_safe_upload_path_stays_inside_upload_dir(tmp_path: Path) -> None:
    destination = safe_upload_path(tmp_path, "../../secret.txt")

    assert destination == (tmp_path / "secret.txt").resolve()
