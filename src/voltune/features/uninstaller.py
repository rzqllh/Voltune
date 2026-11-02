from __future__ import annotations

import os
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

try:
    import winreg
except ImportError:  # makes static/unit testing possible off Windows
    winreg = None


@dataclass(frozen=True)
class InstalledApp:
    name: str
    publisher: str
    version: str
    uninstall_string: str
    install_location: str
    registry_hive: str

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class LeftoverCandidate:
    path: str
    confidence: str
    reason: str

    def to_dict(self) -> dict:
        return asdict(self)


def list_installed_apps() -> list[InstalledApp]:
    if winreg is None:
        return []
    locations = [
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM32"),
        (winreg.HKEY_CURRENT_USER, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKCU"),
    ]
    apps: dict[tuple[str, str], InstalledApp] = {}
    for hive, key_path, label in locations:
        try:
            key = winreg.OpenKey(hive, key_path)
        except OSError:
            continue
        with key:
            for i in range(winreg.QueryInfoKey(key)[0]):
                try:
                    sub = winreg.OpenKey(key, winreg.EnumKey(key, i))
                except OSError:
                    continue
                with sub:
                    def read(name: str) -> str:
                        try:
                            return str(winreg.QueryValueEx(sub, name)[0] or "")
                        except OSError:
                            return ""
                    display = read("DisplayName").strip()
                    if not display:
                        continue
                    app = InstalledApp(display, read("Publisher"), read("DisplayVersion"), read("UninstallString"), read("InstallLocation"), label)
                    apps[(display.casefold(), app.publisher.casefold())] = app
    return sorted(apps.values(), key=lambda a: a.name.casefold())


def leftover_candidates(app: InstalledApp, *, roots: Iterable[Path | str] | None = None) -> list[LeftoverCandidate]:
    normalized = "".join(ch for ch in app.name.casefold() if ch.isalnum())
    publisher = "".join(ch for ch in app.publisher.casefold() if ch.isalnum())
    if len(normalized) < 5:
        return []
    if roots is None:
        roots = [
            os.environ.get("APPDATA", ""),
            os.environ.get("LOCALAPPDATA", ""),
            os.environ.get("PROGRAMDATA", ""),
        ]
    out: list[LeftoverCandidate] = []
    for raw in roots:
        if not raw:
            continue
        root = Path(raw)
        if not root.exists():
            continue
        try:
            children = list(root.iterdir())
        except OSError:
            continue
        for child in children:
            name = "".join(ch for ch in child.name.casefold() if ch.isalnum())
            if not name:
                continue
            confidence = None
            reason = ""
            if name == normalized:
                confidence, reason = "HIGH", "Directory name exactly matches normalized application name."
            elif publisher and publisher in name and normalized[:6] in name:
                confidence, reason = "HIGH", "Publisher and application tokens both match."
            elif normalized in name or name in normalized:
                confidence, reason = "MEDIUM", "Normalized application name overlaps directory name."
            if confidence:
                out.append(LeftoverCandidate(str(child), confidence, reason))
    return out


def uninstall_command(app: InstalledApp) -> list[str]:
    """Parse a registry uninstall string into argv without invoking a shell."""
    import shlex

    raw = app.uninstall_string.strip()
    if not raw:
        return []
    try:
        parts = shlex.split(raw, posix=False)
    except ValueError:
        return []
    clean = []
    for token in parts:
        if len(token) >= 2 and token[0] == token[-1] and token[0] in ('"', "'"):
            token = token[1:-1]
        clean.append(token)
    if not clean:
        return []
    exe = Path(clean[0]).name.casefold()
    if exe in {"cmd", "cmd.exe", "powershell", "powershell.exe", "pwsh", "pwsh.exe", "wscript.exe", "cscript.exe"}:
        return []
    if exe in {"msiexec", "msiexec.exe"}:
        for idx, token in enumerate(clean[1:], start=1):
            upper = token.upper()
            if upper == "/I":
                clean[idx] = "/X"
                break
            if upper.startswith("/I{"):
                clean[idx] = "/X" + token[2:]
                break
    return clean
