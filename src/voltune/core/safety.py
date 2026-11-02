from __future__ import annotations

import os
import shutil
import stat
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Iterable, Optional


class RiskLevel(str, Enum):
    SAFE = "safe"
    CAUTION = "caution"
    ADVANCED = "advanced"
    DANGEROUS = "dangerous"


@dataclass(frozen=True)
class SafetyDecision:
    allowed: bool
    path: Path
    risk: RiskLevel
    reason: str
    is_reparse_point: bool = False


@dataclass(frozen=True)
class DeleteResult:
    path: Path
    allowed: bool
    deleted: bool
    dry_run: bool
    bytes_estimate: int
    reason: str


def _norm(path: Path | str) -> Path:
    raw = os.path.expandvars(os.path.expanduser(str(path))).strip()
    if not raw:
        raise ValueError("empty path")
    return Path(raw).absolute()


def _same_or_inside(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _is_reparse_point(path: Path) -> bool:
    try:
        st = path.lstat()
    except OSError:
        return False
    if stat.S_ISLNK(st.st_mode):
        return True
    attrs = getattr(st, "st_file_attributes", 0)
    reparse_flag = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
    return bool(attrs & reparse_flag)


def default_protected_paths() -> list[Path]:
    candidates: list[str] = []
    for key in ("WINDIR", "ProgramFiles", "ProgramFiles(x86)", "ProgramData"):
        value = os.environ.get(key)
        if value:
            candidates.append(value)
    system_drive = os.environ.get("SystemDrive", "C:")
    candidates.extend([
        system_drive + "\\Recovery",
        system_drive + "\\Boot",
        system_drive + "\\System Volume Information",
    ])
    return [_norm(p) for p in candidates if p]


class FilesystemSafety:
    """Central policy gate for destructive filesystem operations.

    The engine intentionally refuses broad system roots, reparse points by default,
    and user-whitelisted paths. Feature modules should call this instead of using
    shutil.rmtree()/Path.unlink() directly.
    """

    def __init__(
        self,
        *,
        protected_paths: Optional[Iterable[Path | str]] = None,
        whitelist: Optional[Iterable[Path | str]] = None,
        allowed_scopes: Optional[Iterable[Path | str]] = None,
        allow_reparse_points: bool = False,
    ) -> None:
        # ``None`` means use Voltune's default Windows protected paths. An
        # explicit iterable, including ``[]``, is an intentional override.
        # This distinction keeps tests/custom policy scopes deterministic and
        # avoids accidentally protecting the entire system drive.
        protected = (
            list(default_protected_paths())
            if protected_paths is None
            else [_norm(p) for p in protected_paths]
        )
        self.protected_paths = self._dedupe(protected)
        self.whitelist = self._dedupe(_norm(p) for p in (whitelist or []))
        self.allowed_scopes = self._dedupe(_norm(p) for p in (allowed_scopes or []))
        self.allow_reparse_points = allow_reparse_points

    @staticmethod
    def _dedupe(paths: Iterable[Path]) -> list[Path]:
        seen: set[str] = set()
        out: list[Path] = []
        for path in paths:
            key = os.path.normcase(str(path))
            if key not in seen:
                seen.add(key)
                out.append(path)
        return out

    def evaluate(self, path: Path | str, *, risk: RiskLevel = RiskLevel.CAUTION) -> SafetyDecision:
        try:
            target = _norm(path)
        except ValueError:
            return SafetyDecision(False, Path("."), risk, "Empty path is never a valid deletion target.")

        # Reject filesystem roots regardless of platform.
        if target.parent == target:
            return SafetyDecision(False, target, risk, "Filesystem roots are protected.")

        # Prevent deletion of protected roots or any parent that contains them. A
        # feature may explicitly authorize a narrow cleanup scope (for example
        # C:\Windows\Temp) without authorizing the surrounding Windows tree.
        inside_allowed_scope = any(_same_or_inside(target, scope) for scope in self.allowed_scopes)
        for protected in self.protected_paths:
            if _same_or_inside(target, protected) and not inside_allowed_scope:
                return SafetyDecision(False, target, risk, f"Target is inside protected path: {protected}")
            if _same_or_inside(protected, target):
                return SafetyDecision(False, target, risk, f"Target contains protected path: {protected}")

        # Persistent whitelist is stronger than a category selection.
        for allowed in self.whitelist:
            if _same_or_inside(target, allowed) or _same_or_inside(allowed, target):
                return SafetyDecision(False, target, risk, f"Target intersects whitelisted path: {allowed}")

        reparse = _is_reparse_point(target)
        if reparse and not self.allow_reparse_points:
            return SafetyDecision(False, target, risk, "Symlink/junction/reparse-point deletion is blocked by default.", True)

        return SafetyDecision(True, target, risk, "Allowed by filesystem safety policy.", reparse)

    def delete(self, path: Path | str, *, dry_run: bool = False, risk: RiskLevel = RiskLevel.CAUTION) -> DeleteResult:
        decision = self.evaluate(path, risk=risk)
        target = decision.path
        if not decision.allowed:
            return DeleteResult(target, False, False, dry_run, 0, decision.reason)
        if not target.exists() and not target.is_symlink():
            return DeleteResult(target, True, False, dry_run, 0, "Target no longer exists.")

        size = estimate_size(target)
        if dry_run:
            return DeleteResult(target, True, False, True, size, "Dry run: deletion skipped.")

        try:
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                target.unlink()
        except OSError as exc:
            return DeleteResult(target, True, False, False, size, f"Deletion failed: {exc}")

        deleted = not target.exists()
        return DeleteResult(target, True, deleted, False, size, "Deleted and verified." if deleted else "Deletion could not be verified.")


def estimate_size(path: Path | str) -> int:
    target = Path(path)
    try:
        if target.is_file() or target.is_symlink():
            return target.lstat().st_size
    except OSError:
        return 0

    total = 0
    stack = [target]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as it:
                for entry in it:
                    try:
                        if entry.is_symlink():
                            total += entry.stat(follow_symlinks=False).st_size
                        elif entry.is_dir(follow_symlinks=False):
                            stack.append(Path(entry.path))
                        else:
                            total += entry.stat(follow_symlinks=False).st_size
                    except OSError:
                        continue
        except OSError:
            continue
    return total
