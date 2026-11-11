"""Portable default location for persistent native snapshot objects."""

import hashlib
import os
from pathlib import Path
import subprocess


def _absolute_env_path(name: str) -> Path | None:
    value = os.environ.get(name)
    if value is None:
        return None
    path = Path(value)
    if not path.is_absolute():
        raise ValueError(f"{name} must be an absolute path")
    return path.resolve()


def default_store(project: Path) -> Path:
    """Return the store location without creating it or changing runner settings."""
    override = _absolute_env_path("PZ_NATIVE_SNAPSHOT_STORE")
    if override is not None:
        return override

    project = Path(project).resolve()
    try:
        result = subprocess.run(
            ["git", "-C", str(project), "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True,
            text=True,
            check=True,
            timeout=15,
        )
        common_dir = Path(result.stdout.strip())
        if not result.stdout.strip() or not common_dir.is_absolute():
            raise ValueError("git returned an invalid common directory")
        identity = common_dir.resolve()
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        if (project / ".git").exists():
            raise RuntimeError(f"Cannot determine Git common directory for {project}") from exc
        identity = project

    repo_id = hashlib.sha256(os.fsencode(str(identity))).hexdigest()
    data_home = _absolute_env_path("XDG_DATA_HOME")
    if data_home is None:
        data_home = Path.home() / ".local" / "share"
    return (data_home / "pz-survivor-toolkit" / "native-snapshots" / repo_id).resolve()
