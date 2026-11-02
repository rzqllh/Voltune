from __future__ import annotations

import fnmatch
import os
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Iterator, Optional

from voltune.core.safety import FilesystemSafety, RiskLevel, estimate_size


@dataclass(frozen=True)
class DiskEntry:
    path: str
    name: str
    size_bytes: int
    kind: str
    modified_at: float

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class DevArtifact:
    path: str
    project_root: str
    kind: str
    size_bytes: int
    modified_at: float
    age_days: float
    recent: bool
    default_selected: bool

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class InstallerCandidate:
    path: str
    size_bytes: int
    modified_at: float
    age_days: float
    extension: str

    def to_dict(self) -> dict:
        return asdict(self)


DEV_ARTIFACT_NAMES = {
    "node_modules": "Node.js dependencies",
    ".next": "Next.js build/cache",
    ".nuxt": "Nuxt build/cache",
    "dist": "Build output",
    "build": "Build output",
    "coverage": "Coverage output",
    ".pytest_cache": "Pytest cache",
    ".mypy_cache": "Mypy cache",
    "__pycache__": "Python bytecode cache",
    ".venv": "Python virtualenv",
    "venv": "Python virtualenv",
    "target": "Rust build output",
    ".gradle": "Gradle project cache",
}

PROJECT_MARKERS = {
    ".git", "package.json", "pyproject.toml", "Cargo.toml", "go.mod",
    "pom.xml", "build.gradle", "build.gradle.kts", "requirements.txt", "setup.py",
    "Pipfile", "*.sln", "*.csproj",
}

INSTALLER_EXTENSIONS = {
    ".exe", ".msi", ".msix", ".msixbundle", ".appx", ".appxbundle",
    ".iso", ".cab", ".zip", ".7z",
}

SKIP_DIRS = {
    "$recycle.bin", "system volume information", "windows", "program files",
    "program files (x86)", "programdata", ".git",
}


def _safe_stat(path: Path):
    try:
        return path.stat()
    except OSError:
        return None


def _iter_tree(root: Path, *, max_depth: int = 8) -> Iterator[tuple[Path, list[str], list[str]]]:
    root = root.expanduser().absolute()
    base_depth = len(root.parts)
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        depth = len(current_path.parts) - base_depth
        dirs[:] = [d for d in dirs if d.lower() not in SKIP_DIRS]
        if depth >= max_depth:
            dirs[:] = []
        yield current_path, dirs, files


def scan_children(root: Path | str, *, limit: int = 50) -> list[DiskEntry]:
    base = Path(root).expanduser().absolute()
    rows: list[DiskEntry] = []
    try:
        children = list(base.iterdir())
    except OSError:
        return rows

    for child in children:
        if child.is_symlink():
            continue
        st = _safe_stat(child)
        if not st:
            continue
        size = estimate_size(child)
        rows.append(DiskEntry(str(child), child.name, size, "dir" if child.is_dir() else "file", st.st_mtime))
    rows.sort(key=lambda item: item.size_bytes, reverse=True)
    return rows[:limit]


def find_large_files(root: Path | str, *, threshold_bytes: int = 500 * 1024 * 1024, limit: int = 100, max_depth: int = 12) -> list[DiskEntry]:
    base = Path(root).expanduser().absolute()
    found: list[DiskEntry] = []
    for current, _dirs, files in _iter_tree(base, max_depth=max_depth):
        for name in files:
            path = current / name
            if path.is_symlink():
                continue
            st = _safe_stat(path)
            if not st or st.st_size < threshold_bytes:
                continue
            found.append(DiskEntry(str(path), name, st.st_size, "file", st.st_mtime))
    found.sort(key=lambda item: item.size_bytes, reverse=True)
    return found[:limit]


def _has_marker(path: Path) -> bool:
    try:
        names = {p.name for p in path.iterdir()}
    except OSError:
        return False
    for marker in PROJECT_MARKERS:
        if "*" in marker:
            if any(fnmatch.fnmatch(name, marker) for name in names):
                return True
        elif marker in names:
            return True
    return False


def _project_root_for(artifact: Path, scan_root: Path) -> Optional[Path]:
    current = artifact.parent
    while True:
        if _has_marker(current):
            return current
        if current == scan_root or current.parent == current:
            return None
        current = current.parent


def _project_activity(project_root: Path, artifact: Path, *, max_entries: int = 3000) -> float:
    activity = 0.0
    for path in (project_root, artifact, project_root / ".git" / "index"):
        st = _safe_stat(path)
        if st:
            activity = max(activity, st.st_mtime)
    base_depth = len(project_root.parts)
    seen = 0
    for current, dirs, files in os.walk(project_root, topdown=True, followlinks=False):
        current_path = Path(current)
        if len(current_path.parts) - base_depth >= 3:
            dirs[:] = []
        dirs[:] = [d for d in dirs if d not in DEV_ARTIFACT_NAMES and d != ".git"]
        for name in files:
            seen += 1
            st = _safe_stat(current_path / name)
            if st:
                activity = max(activity, st.st_mtime)
            if seen >= max_entries:
                return activity
    return activity


def scan_dev_artifacts(
    roots: Iterable[Path | str],
    *,
    recent_days: int = 7,
    max_depth: int = 8,
    safety: Optional[FilesystemSafety] = None,
) -> list[DevArtifact]:
    now = time.time()
    found: list[DevArtifact] = []
    seen: set[str] = set()
    for root_raw in roots:
        root = Path(os.path.expandvars(os.path.expanduser(str(root_raw)))).absolute()
        if not root.exists() or not root.is_dir():
            continue
        for current, dirs, _files in _iter_tree(root, max_depth=max_depth):
            matched = [d for d in list(dirs) if d in DEV_ARTIFACT_NAMES]
            for dirname in matched:
                path = current / dirname
                dirs.remove(dirname)  # artifact contents do not need recursive discovery
                key = os.path.normcase(str(path))
                if key in seen:
                    continue
                seen.add(key)
                if safety and not safety.evaluate(path, risk=RiskLevel.CAUTION).allowed:
                    continue
                st = _safe_stat(path)
                if not st:
                    continue
                project_root = _project_root_for(path, root)
                if project_root is None:
                    continue
                activity = _project_activity(project_root, path)
                age_days = max(0.0, (now - activity) / 86400)
                recent = age_days < recent_days
                found.append(DevArtifact(
                    path=str(path),
                    project_root=str(project_root),
                    kind=DEV_ARTIFACT_NAMES[dirname],
                    size_bytes=estimate_size(path),
                    modified_at=activity,
                    age_days=age_days,
                    recent=recent,
                    default_selected=not recent,
                ))
    found.sort(key=lambda item: item.size_bytes, reverse=True)
    return found


def find_installers(
    roots: Iterable[Path | str],
    *,
    min_size_bytes: int = 20 * 1024 * 1024,
    min_age_days: int = 14,
    max_depth: int = 5,
) -> list[InstallerCandidate]:
    now = time.time()
    found: list[InstallerCandidate] = []
    for raw in roots:
        root = Path(os.path.expandvars(os.path.expanduser(str(raw)))).absolute()
        if not root.exists() or not root.is_dir():
            continue
        for current, _dirs, files in _iter_tree(root, max_depth=max_depth):
            for name in files:
                path = current / name
                ext = path.suffix.lower()
                if ext not in INSTALLER_EXTENSIONS or path.is_symlink():
                    continue
                if ext in {".zip", ".7z"}:
                    stem = path.stem.casefold()
                    installer_tokens = ("setup", "installer", "install", "driver", "update", "bundle")
                    if not any(token in stem for token in installer_tokens):
                        continue
                st = _safe_stat(path)
                if not st or st.st_size < min_size_bytes:
                    continue
                age = max(0.0, (now - st.st_mtime) / 86400)
                if age < min_age_days:
                    continue
                found.append(InstallerCandidate(str(path), st.st_size, st.st_mtime, age, ext))
    found.sort(key=lambda item: item.size_bytes, reverse=True)
    return found
