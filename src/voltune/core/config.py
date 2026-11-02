from __future__ import annotations

import os
from pathlib import Path
from typing import Iterable


def expand_paths(values: Iterable[str]) -> list[Path]:
    return [Path(os.path.expandvars(os.path.expanduser(v))).absolute() for v in values if v]


def default_storage_config() -> dict:
    return {
        "recent_project_days": 7,
        "large_file_threshold_mb": 500,
        "installer_min_age_days": 14,
        "installer_min_size_mb": 20,
        "dev_scan_roots": [
            r"%USERPROFILE%\Documents",
            r"%USERPROFILE%\Desktop",
            r"%USERPROFILE%\source",
        ],
        "installer_scan_roots": [
            r"%USERPROFILE%\Downloads",
            r"%USERPROFILE%\Desktop",
        ],
        "protected_paths": [
            r"%USERPROFILE%\.ollama",
            r"%USERPROFILE%\.claude",
            r"%USERPROFILE%\.cursor",
            r"%USERPROFILE%\.vscode",
            r"%LOCALAPPDATA%\Docker",
        ],
    }
