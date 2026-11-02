#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VOLTUNE
Windows Performance, Maintenance, Network & Recovery Utility

Designed for Windows 11 / PowerShell 5.1+.
Run as Administrator.

Source dependencies:
    pip install rich psutil dnspython

Notes:
- Safe Mode is the default.
- Experimental tweaks are intentionally separated from normal maintenance.
- Every main-menu return clears the screen before drawing the menu again.
- State-changing commands are logged and, where practical, snapshotted for restore.
"""

from __future__ import annotations

import ctypes
import json
import os
import re
import shutil
import socket
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Tuple

try:
    import psutil
    import dns.resolver
    import dns.exception
    import winreg
    from rich import box
    from rich.align import Align
    from rich.console import Console
    from rich.panel import Panel
    from rich.progress import Progress, SpinnerColumn, TextColumn
    from rich.prompt import Confirm, Prompt
    from rich.table import Table
except ImportError as exc:
    missing = str(exc).split("'")[-2] if "'" in str(exc) else str(exc)
    print(f"Missing dependency: {missing}")
    print("Install dependencies with:")
    print(f'  "{sys.executable}" -m pip install rich psutil dnspython')
    sys.exit(2)

from voltune.core.config import default_storage_config, expand_paths
from voltune.core.safety import FilesystemSafety, RiskLevel
from voltune.features.storage_intelligence import (
    find_installers,
    find_large_files,
    scan_children,
    scan_dev_artifacts,
)
from voltune.features.system_monitor import collect_snapshot
from voltune.features.uninstaller import (
    leftover_candidates,
    list_installed_apps,
    uninstall_command,
)


# =============================================================================
# GLOBALS / PATHS
# =============================================================================

console = Console()
SESSION_ID = uuid.uuid4().hex[:12]


def _app_dir() -> Path:
    """Return the writable Voltune data directory.

    Frozen builds keep config/state/logs next to the executable. During a source
    checkout we use the repository root. Installed-package fallback uses
    %LOCALAPPDATA%\\Voltune so site-packages is never treated as writable state.
    """
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    override = os.environ.get("VOLTUNE_HOME")
    if override:
        return Path(override).expanduser().resolve()
    here = Path(__file__).resolve()
    repo_root = here.parents[2] if len(here.parents) >= 3 else here.parent
    if (repo_root / "pyproject.toml").exists():
        return repo_root
    local = os.environ.get("LOCALAPPDATA")
    return Path(local) / "Voltune" if local else Path.home() / ".voltune"


APP_DIR = _app_dir()
CONFIG_PATH = APP_DIR / "config.json"
STATE_PATH = APP_DIR / "state.json"
LOG_DIR = APP_DIR / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_PATH = LOG_DIR / f"voltune-{datetime.now():%Y-%m-%d_%H%M%S}-{SESSION_ID}.log"

ULTIMATE_TEMPLATE_GUID = "e9a42b02-d5df-448d-aa00-03f14749eb61"
BALANCED_GUID = "381b4222-f694-41f0-9685-ff5bb260df2e"
HIGH_PERF_GUID = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
POWER_SAVER_GUID = "a1841308-3541-4fab-bc81-f71556f20b4a"

DEFAULT_CONFIG: Dict[str, Any] = {
    "schema_version": 2,
    "ui": {
        "safe_mode": True,
        "dry_run": False,
        "pause_after_action": True,
    },
    "storage": default_storage_config(),
    "gaming_mode": {
        "kill_browsers_comm": [
            "msedge.exe", "firefox.exe", "opera.exe", "brave.exe", "vivaldi.exe",
            "Teams.exe", "Discord.exe", "zoom.exe", "slack.exe", "Skype.exe",
            "telegram.exe", "whatsapp.exe",
        ],
        "kill_cloud_sync": ["OneDrive.exe", "googledrivesync.exe", "GoogleDriveFS.exe", "dropbox.exe", "BoxSync.exe"],
        "kill_vendor_optional": [
            "MSI.TerminalServer.exe", "MSI_LAN_Manager_Tool.exe", "DSATray.exe",
            "IntelGraphicsSoftware.exe", "NAHIMICUI3.exe", "SonicStudio3.exe",
        ],
        "services_stop": ["WSearch", "SysMain", "CDPSvc", "DiagTrack", "WerSvc"],
        "set_high_performance": True,
    },
    "startup_apps": {
        "OneDrive": ["HKCU", r"Software\Microsoft\Windows\CurrentVersion\Run", "OneDrive"],
        "Teams": ["HKCU", r"Software\Microsoft\Windows\CurrentVersion\Run", "com.squirrel.Teams.Teams"],
        "Discord": ["HKCU", r"Software\Microsoft\Windows\CurrentVersion\Run", "Discord"],
        "Spotify": ["HKCU", r"Software\Microsoft\Windows\CurrentVersion\Run", "Spotify"],
        "Steam": ["HKCU", r"Software\Microsoft\Windows\CurrentVersion\Run", "Steam"],
        "Skype": ["HKCU", r"Software\Microsoft\Windows\CurrentVersion\Run", "Skype"],
        "Adobe GC": ["HKCU", r"Software\Microsoft\Windows\CurrentVersion\Run", "AdobeGCInvoker-1.0"],
        "CCleaner": ["HKLM", r"Software\Microsoft\Windows\CurrentVersion\Run", "CCleaner64"],
        "Google Update": ["HKCU", r"Software\Microsoft\Windows\CurrentVersion\Run", "Google Update"],
    },
    "bloat_apps": [
        ["Xbox", "*Xbox*", "Microsoft Consumer"],
        ["Bing News", "*BingNews*", "Microsoft Consumer"],
        ["Bing Weather", "*BingWeather*", "Microsoft Consumer"],
        ["Groove Music", "*ZuneMusic*", "Media"],
        ["Movies & TV", "*ZuneVideo*", "Media"],
        ["Skype builtin", "*SkypeApp*", "Communication"],
        ["Mixed Reality Portal", "*MixedReality*", "Optional"],
        ["Get Help", "*GetHelp*", "Optional"],
        ["Get Started / Tips", "*Getstarted*", "Optional"],
        ["Solitaire", "*MicrosoftSolitaire*", "Microsoft Consumer"],
        ["Teams builtin", "*MicrosoftTeams*", "Communication"],
        ["Clipchamp", "*ClipChamp*", "Media"],
        ["Disney+", "*Disney*", "Microsoft Consumer"],
        ["TikTok", "*TikTok*", "Microsoft Consumer"],
        ["Instagram", "*Instagram*", "Microsoft Consumer"],
        ["Facebook", "*Facebook*", "Microsoft Consumer"],
        ["Prime Video", "*AmazonVideo*", "Media"],
        ["Spotify builtin", "*SpotifyAB*", "Media"],
        ["Power Automate", "*PowerAutomate*", "Optional"],
        ["People", "*People*", "Optional"],
        ["Mail and Calendar", "*windowscommunicationsapps*", "Communication"],
        ["Maps", "*WindowsMaps*", "Optional"],
        ["Feedback Hub", "*WindowsFeedbackHub*", "Optional"],
        ["Phone Link", "*YourPhone*", "Communication"],
        ["3D Viewer", "*Microsoft3DViewer*", "Optional"],
    ],
    "dns_providers": [
        {"name": "Cloudflare", "primary": "1.1.1.1", "secondary": "1.0.0.1"},
        {"name": "Google", "primary": "8.8.8.8", "secondary": "8.8.4.4"},
        {"name": "Quad9", "primary": "9.9.9.9", "secondary": "149.112.112.112"},
        {"name": "OpenDNS", "primary": "208.67.222.222", "secondary": "208.67.220.220"},
        {"name": "CleanBrowsing", "primary": "185.228.168.9", "secondary": "185.228.169.9"},
    ],
    "dns_test_domains": [
        "google.com", "youtube.com", "github.com", "microsoft.com", "cloudflare.com"
    ],
    "latency_targets": [
        ["1.1.1.1", "Cloudflare"],
        ["8.8.8.8", "Google DNS"],
        ["9.9.9.9", "Quad9"],
    ],
}

DEFAULT_STATE: Dict[str, Any] = {
    "schema_version": 2,
    "startup_backup": {},
    "gaming_session": None,
    "ultimate_guid": None,
    "history": [],
    "snapshots": {},
}


# =============================================================================
# CORE UTILITIES
# =============================================================================

@dataclass
class CmdResult:
    command: str
    returncode: int
    stdout: str = ""
    stderr: str = ""
    timed_out: bool = False
    skipped: bool = False

    @property
    def ok(self) -> bool:
        return self.returncode == 0 and not self.timed_out


def log(message: str, level: str = "INFO") -> None:
    line = f"{datetime.now().isoformat(timespec='seconds')} [{level}] [{SESSION_ID}] {message}\n"
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass


def atomic_write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_name, path)
    finally:
        try:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)
        except Exception:
            pass


def deep_merge(defaults: Any, loaded: Any) -> Any:
    if isinstance(defaults, dict) and isinstance(loaded, dict):
        result = dict(defaults)
        for key, value in loaded.items():
            if key in defaults:
                result[key] = deep_merge(defaults[key], value)
            else:
                result[key] = value
        return result
    return loaded


def _load_json_resilient(path: Path, defaults: Dict[str, Any]) -> Dict[str, Any]:
    if not path.exists():
        atomic_write_json(path, defaults)
        return json.loads(json.dumps(defaults))
    try:
        with open(path, "r", encoding="utf-8") as f:
            raw = json.load(f)
        return deep_merge(defaults, raw)
    except Exception as exc:
        corrupt = path.with_name(f"{path.stem}.corrupt.{datetime.now():%Y%m%d_%H%M%S}{path.suffix}")
        try:
            shutil.move(str(path), str(corrupt))
        except Exception:
            pass
        log(f"Corrupt JSON {path}: {exc}; moved to {corrupt}", "ERROR")
        atomic_write_json(path, defaults)
        return json.loads(json.dumps(defaults))


CONFIG = _load_json_resilient(CONFIG_PATH, DEFAULT_CONFIG)
STATE = _load_json_resilient(STATE_PATH, DEFAULT_STATE)


def save_config() -> None:
    atomic_write_json(CONFIG_PATH, CONFIG)


def save_state() -> None:
    if len(STATE.get("history", [])) > 250:
        STATE["history"] = STATE["history"][-250:]
    atomic_write_json(STATE_PATH, STATE)


def add_history(action: str, status: str, detail: str = "", snapshot_id: Optional[str] = None) -> None:
    STATE.setdefault("history", []).append({
        "id": uuid.uuid4().hex[:10],
        "time": datetime.now().isoformat(timespec="seconds"),
        "action": action,
        "status": status,
        "detail": detail,
        "snapshot_id": snapshot_id,
    })
    save_state()


def create_snapshot(kind: str, data: Dict[str, Any]) -> str:
    sid = f"{kind}-{datetime.now():%Y%m%d%H%M%S}-{uuid.uuid4().hex[:6]}"
    STATE.setdefault("snapshots", {})[sid] = {
        "kind": kind,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "data": data,
    }
    save_state()
    return sid


def delete_snapshot(snapshot_id: str) -> None:
    STATE.setdefault("snapshots", {}).pop(snapshot_id, None)
    save_state()


def is_admin() -> bool:
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def require_admin() -> None:
    if is_admin():
        return
    console.print("[bold yellow]Administrator access is required.[/]")
    args = " ".join(f'"{a}"' for a in sys.argv)
    ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, args, None, 1)
    sys.exit(0)


def quote_cmd(cmd: Sequence[str]) -> str:
    return subprocess.list2cmdline([str(x) for x in cmd])


def run(cmd: Sequence[str], timeout: int = 30, *, mutating: bool = False, check: bool = False) -> CmdResult:
    cmd = [str(x) for x in cmd]
    pretty = quote_cmd(cmd)
    if mutating and CONFIG["ui"].get("dry_run", False):
        log(f"DRY-RUN {pretty}")
        return CmdResult(pretty, 0, stdout="DRY RUN", skipped=True)
    try:
        cp = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, errors="replace")
        result = CmdResult(pretty, cp.returncode, cp.stdout or "", cp.stderr or "")
        log(f"CMD rc={cp.returncode}: {pretty}\nSTDOUT={result.stdout[-2000:]}\nSTDERR={result.stderr[-2000:]}")
        if check and not result.ok:
            raise RuntimeError(f"Command failed ({result.returncode}): {pretty}\n{result.stderr.strip()}")
        return result
    except subprocess.TimeoutExpired as exc:
        result = CmdResult(pretty, 124, str(exc.stdout or ""), str(exc.stderr or ""), timed_out=True)
        log(f"TIMEOUT: {pretty}", "ERROR")
        if check:
            raise RuntimeError(f"Command timed out: {pretty}")
        return result
    except Exception as exc:
        log(f"EXCEPTION running {pretty}: {exc}", "ERROR")
        if check:
            raise
        return CmdResult(pretty, 1, stderr=str(exc))


def run_ps(script: str, timeout: int = 30, *, mutating: bool = False, check: bool = False) -> CmdResult:
    return run(["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script],
               timeout=timeout, mutating=mutating, check=check)


def ps_json(script: str, timeout: int = 30) -> Any:
    wrapper = f"$ProgressPreference='SilentlyContinue'; {script} | ConvertTo-Json -Depth 8 -Compress"
    r = run_ps(wrapper, timeout=timeout)
    if not r.ok or not r.stdout.strip():
        return None
    try:
        return json.loads(r.stdout.strip())
    except Exception:
        return None


def header(title: str, subtitle: Optional[str] = None) -> None:
    content = f"[bold white]{title}[/]"
    if subtitle:
        content += f"\n[dim]{subtitle}[/]"
    console.print()
    console.print(Panel(Align.center(content), style="red", border_style="bold red", padding=(0, 4)))
    console.print()


def pause() -> None:
    if CONFIG["ui"].get("pause_after_action", True):
        console.input("\n  [dim]Press Enter to return to main menu...[/]")


def info(msg: str) -> None:
    console.print(f"  [bold cyan]→[/] {msg}")


def warn(msg: str) -> None:
    console.print(f"  [bold yellow]⚠[/] {msg}")


def error(msg: str) -> None:
    console.print(f"  [bold red]✗[/] {msg}")


def success(msg: str) -> None:
    console.print(f"  [bold green]✓[/] {msg}")


def fmt_bytes(value: int) -> str:
    size = float(value)
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024 or unit == "TB":
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def safe_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return default


def dry_run_notice() -> None:
    if CONFIG["ui"].get("dry_run"):
        console.print("  [bold yellow]DRY RUN ON[/]  [dim]No mutating command will be executed.[/]\n")


# =============================================================================
# WINDOWS REGISTRY / SERVICE / PROCESS HELPERS
# =============================================================================

HIVE_MAP = {"HKCU": winreg.HKEY_CURRENT_USER, "HKLM": winreg.HKEY_LOCAL_MACHINE}


def reg_read(hive: int, path: str, name: str) -> Tuple[bool, Any, Optional[int]]:
    try:
        key = winreg.OpenKey(hive, path, 0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY)
        value, kind = winreg.QueryValueEx(key, name)
        winreg.CloseKey(key)
        return True, value, kind
    except Exception:
        return False, None, None


def reg_set(hive: int, path: str, name: str, kind: int, value: Any) -> bool:
    if CONFIG["ui"].get("dry_run"):
        log(f"DRY-RUN REG SET {path}::{name}={value}")
        return True
    try:
        key = winreg.CreateKeyEx(hive, path, 0, winreg.KEY_SET_VALUE | winreg.KEY_WOW64_64KEY)
        winreg.SetValueEx(key, name, 0, kind, value)
        winreg.CloseKey(key)
        log(f"REG SET {path}::{name}={value}")
        return True
    except Exception as exc:
        log(f"REG SET FAILED {path}::{name}: {exc}", "ERROR")
        return False


def reg_delete(hive: int, path: str, name: str) -> bool:
    if CONFIG["ui"].get("dry_run"):
        log(f"DRY-RUN REG DELETE {path}::{name}")
        return True
    try:
        key = winreg.OpenKey(hive, path, 0, winreg.KEY_SET_VALUE | winreg.KEY_WOW64_64KEY)
        winreg.DeleteValue(key, name)
        winreg.CloseKey(key)
        log(f"REG DELETE {path}::{name}")
        return True
    except FileNotFoundError:
        return True
    except Exception as exc:
        log(f"REG DELETE FAILED {path}::{name}: {exc}", "ERROR")
        return False


def capture_registry_values(items: List[Tuple[str, str, str]]) -> Dict[str, Any]:
    snap: Dict[str, Any] = {}
    for hive_name, path, name in items:
        hive = HIVE_MAP[hive_name]
        exists, value, kind = reg_read(hive, path, name)
        snap[f"{hive_name}|{path}|{name}"] = {"exists": exists, "value": value, "kind": kind}
    return snap


def restore_registry_snapshot(snapshot: Dict[str, Any]) -> Tuple[int, int]:
    ok_count = fail_count = 0
    for composite, item in snapshot.items():
        hive_name, path, name = composite.split("|", 2)
        hive = HIVE_MAP[hive_name]
        if item.get("exists"):
            ok = reg_set(hive, path, name, int(item["kind"]), item.get("value"))
        else:
            ok = reg_delete(hive, path, name)
        ok_count += int(ok)
        fail_count += int(not ok)
    return ok_count, fail_count


def get_service_state(name: str) -> Dict[str, Any]:
    script = (
        f"$s=Get-CimInstance Win32_Service -Filter \"Name='{name.replace("'", "''")}'\" -ErrorAction SilentlyContinue; "
        "if($s){[pscustomobject]@{Name=$s.Name;State=$s.State;StartMode=$s.StartMode}}"
    )
    data = ps_json(script)
    return data if isinstance(data, dict) else {"Name": name, "State": "Missing", "StartMode": "Unknown"}


def svc_stop(name: str) -> bool:
    state = get_service_state(name)
    if state.get("State") in ("Stopped", "Missing"):
        return True
    r = run(["sc", "stop", name], timeout=20, mutating=True)
    if r.skipped:
        return True
    time.sleep(0.3)
    return get_service_state(name).get("State") == "Stopped"


def svc_start(name: str) -> bool:
    state = get_service_state(name)
    if state.get("State") in ("Running", "Missing"):
        return state.get("State") == "Running"
    r = run(["sc", "start", name], timeout=20, mutating=True)
    if r.skipped:
        return True
    time.sleep(0.5)
    return get_service_state(name).get("State") == "Running"


def svc_set_start(name: str, mode: str) -> bool:
    # sc.exe syntax requires a separate argument after start=
    mapping = {"Disabled": "disabled", "Auto": "auto", "Manual": "demand", "Automatic": "auto"}
    value = mapping.get(mode, mode.lower())
    r = run(["sc", "config", name, "start=", value], timeout=20, mutating=True)
    return r.ok or r.skipped


def kill_proc(name: str) -> int:
    if CONFIG["ui"].get("dry_run"):
        matches = [p for p in psutil.process_iter(["name"]) if (p.info.get("name") or "").lower() == name.lower()]
        log(f"DRY-RUN kill {name}: {len(matches)} matches")
        return len(matches)
    killed = 0
    for p in psutil.process_iter(["pid", "name"]):
        try:
            if (p.info.get("name") or "").lower() == name.lower():
                p.kill()
                killed += 1
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return killed


def proc_running(name: str) -> bool:
    lname = name.lower()
    for p in psutil.process_iter(["name"]):
        try:
            if (p.info.get("name") or "").lower() == lname:
                return True
        except Exception:
            pass
    return False


# =============================================================================
# POWER PLAN HELPERS
# =============================================================================


def get_power_plans() -> Dict[str, str]:
    r = run(["powercfg", "/list"])
    plans: Dict[str, str] = {}
    if r.ok:
        for line in r.stdout.splitlines():
            m = re.search(r"([0-9a-fA-F-]{36})\s+\((.+?)\)", line)
            if m:
                plans[m.group(2).strip()] = m.group(1).lower()
    return plans


def get_active_power_plan() -> Dict[str, str]:
    r = run(["powercfg", "/getactivescheme"])
    if r.ok:
        m = re.search(r"([0-9a-fA-F-]{36})\s+\((.+?)\)", r.stdout)
        if m:
            return {"guid": m.group(1).lower(), "name": m.group(2).strip()}
    return {"guid": "", "name": "Unknown"}


def set_power_plan(guid: str) -> bool:
    r = run(["powercfg", "/setactive", guid], mutating=True)
    if r.skipped:
        return True
    active = get_active_power_plan()
    return active.get("guid", "").lower() == guid.lower()


def find_plan_by_keyword(keyword: str) -> Optional[Tuple[str, str]]:
    keyword = keyword.lower()
    for name, guid in get_power_plans().items():
        if keyword in name.lower():
            return name, guid
    return None


def ensure_ultimate_plan() -> Tuple[bool, Optional[str], str]:
    existing = find_plan_by_keyword("ultimate")
    if existing:
        return True, existing[1], f"Already installed as '{existing[0]}'"

    r = run(["powercfg", "/duplicatescheme", ULTIMATE_TEMPLATE_GUID], timeout=30, mutating=True)
    if r.skipped:
        return True, ULTIMATE_TEMPLATE_GUID, "Dry run: would install Ultimate Performance"
    if not r.ok:
        return False, None, (r.stderr or r.stdout or "powercfg failed").strip()

    # /duplicatescheme returns the NEW GUID. Use it directly, then verify against /list.
    m = re.search(r"([0-9a-fA-F-]{36})", r.stdout + "\n" + r.stderr)
    new_guid = m.group(1).lower() if m else None
    plans = get_power_plans()
    if new_guid and new_guid in [g.lower() for g in plans.values()]:
        if not CONFIG["ui"].get("dry_run"):
            STATE["ultimate_guid"] = new_guid
            save_state()
        return True, new_guid, "Ultimate Performance installed"

    # Fallback: some localized builds make output parsing awkward. Re-detect by name.
    existing = find_plan_by_keyword("ultimate")
    if existing:
        if not CONFIG["ui"].get("dry_run"):
            STATE["ultimate_guid"] = existing[1]
            save_state()
        return True, existing[1], f"Installed as '{existing[0]}'"
    return False, None, "Command completed, but the new scheme could not be verified."


# =============================================================================
# NETWORK HELPERS
# =============================================================================


def get_active_adapter() -> Optional[Dict[str, Any]]:
    script = r"""
$candidates = Get-NetIPConfiguration | Where-Object {
    $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up'
}
$ranked = foreach($c in $candidates){
    $ipif = Get-NetIPInterface -InterfaceIndex $c.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    [pscustomobject]@{ Config=$c; Metric=if($ipif){$ipif.InterfaceMetric}else{99999} }
}
$chosen = $ranked | Sort-Object Metric | Select-Object -First 1
if($chosen){
 $cfg=$chosen.Config
 [pscustomobject]@{
   InterfaceAlias=$cfg.InterfaceAlias
   InterfaceIndex=$cfg.InterfaceIndex
   InterfaceMetric=$chosen.Metric
   IPv4=($cfg.IPv4Address.IPAddress | Select-Object -First 1)
   Gateway=($cfg.IPv4DefaultGateway.NextHop | Select-Object -First 1)
   DnsServers=@($cfg.DNSServer.ServerAddresses)
   Description=$cfg.NetAdapter.InterfaceDescription
 }
}
"""
    data = ps_json(script)
    return data if isinstance(data, dict) else None


def get_adapter_dns(interface_index: int) -> List[str]:
    script = (
        f"(Get-DnsClientServerAddress -InterfaceIndex {int(interface_index)} -AddressFamily IPv4 "
        "-ErrorAction SilentlyContinue).ServerAddresses"
    )
    data = ps_json(script)
    if isinstance(data, list):
        return [str(x) for x in data]
    if isinstance(data, str):
        return [data]
    return []


def set_adapter_dns(interface_index: int, servers: Sequence[str]) -> bool:
    quoted = ",".join(f"'{s}'" for s in servers)
    script = f"Set-DnsClientServerAddress -InterfaceIndex {int(interface_index)} -ServerAddresses ({quoted}) -ErrorAction Stop"
    r = run_ps(script, mutating=True)
    if r.skipped:
        return True
    if not r.ok:
        return False
    actual = get_adapter_dns(interface_index)
    return actual[:len(servers)] == list(servers)


def reset_adapter_dns(interface_index: int) -> bool:
    r = run_ps(
        f"Set-DnsClientServerAddress -InterfaceIndex {int(interface_index)} -ResetServerAddresses -ErrorAction Stop",
        mutating=True,
    )
    return r.ok or r.skipped


def flush_dns() -> bool:
    r = run(["ipconfig", "/flushdns"], timeout=15, mutating=True)
    return r.ok or r.skipped


def ping_once(host: str, timeout_ms: int = 2000) -> Optional[int]:
    # Use .NET Ping instead of scraping localized ping.exe output. This works on
    # Windows PowerShell 5.1 as well as newer PowerShell versions.
    safe_host = host.replace("'", "''")
    script = (
        "$p = New-Object System.Net.NetworkInformation.Ping; "
        f"try {{$r=$p.Send('{safe_host}', {int(timeout_ms)}); "
        "if($r.Status -eq [System.Net.NetworkInformation.IPStatus]::Success){$r.RoundtripTime}} "
        "catch {} finally {$p.Dispose()}"
    )
    r = run_ps(script, timeout=max(5, timeout_ms // 1000 + 3))
    if not r.ok:
        return None
    m = re.search(r"\d+(?:\.\d+)?", r.stdout.strip())
    return int(float(m.group(0))) if m else None


def ping_series(host: str, count: int = 5) -> List[Optional[int]]:
    values: List[Optional[int]] = []
    for _ in range(count):
        values.append(ping_once(host))
    return values


def latency_stats(values: Sequence[Optional[int]]) -> Dict[str, float]:
    valid = [float(v) for v in values if v is not None]
    loss = 100.0 * (len(values) - len(valid)) / max(1, len(values))
    if not valid:
        return {"min": 0, "avg": 0, "max": 0, "jitter": 0, "loss": loss}
    deltas = [abs(valid[i] - valid[i - 1]) for i in range(1, len(valid))]
    return {
        "min": min(valid),
        "avg": statistics.mean(valid),
        "max": max(valid),
        "jitter": statistics.mean(deltas) if deltas else 0,
        "loss": loss,
    }


def dns_query_ms(nameserver: str, domain: str, timeout: float = 2.0) -> Optional[float]:
    resolver = dns.resolver.Resolver(configure=False)
    resolver.nameservers = [nameserver]
    resolver.timeout = timeout
    resolver.lifetime = timeout
    start = time.perf_counter()
    try:
        resolver.resolve(domain, "A", raise_on_no_answer=False)
        return round((time.perf_counter() - start) * 1000.0, 2)
    except Exception:
        return None


def benchmark_dns_provider(provider: Dict[str, str], domains: Sequence[str], rounds: int = 2) -> Dict[str, Any]:
    primary = provider["primary"]
    samples: List[Optional[float]] = []
    for _ in range(rounds):
        for domain in domains:
            samples.append(dns_query_ms(primary, domain))
    valid = [x for x in samples if x is not None]
    success_rate = 100.0 * len(valid) / max(1, len(samples))
    if valid:
        ordered = sorted(valid)
        p95_index = min(len(ordered) - 1, max(0, int(round(0.95 * (len(ordered) - 1)))))
        median = statistics.median(valid)
        p95 = ordered[p95_index]
    else:
        median = p95 = 9999.0
    return {
        "name": provider["name"],
        "primary": primary,
        "secondary": provider["secondary"],
        "median": round(median, 2),
        "p95": round(p95, 2),
        "success": round(success_rate, 1),
        "samples": len(samples),
    }


# =============================================================================
# STARTUP / APPX HELPERS
# =============================================================================


def _read_startup_val(hive_str: str, path: str, name: str) -> Tuple[Any, Optional[int]]:
    exists, value, kind = reg_read(HIVE_MAP[hive_str], path, name)
    return (value, kind) if exists else (None, None)


def _startup_disable(hive_str: str, path: str, name: str, label: str) -> bool:
    value, kind = _read_startup_val(hive_str, path, name)
    if value is None:
        return False
    STATE["startup_backup"][label] = {
        "hive": hive_str, "path": path, "name": name, "value": value, "kind": kind
    }
    save_state()
    ok = reg_delete(HIVE_MAP[hive_str], path, name)
    return ok


def _startup_restore(label: str) -> bool:
    backup = STATE.get("startup_backup", {}).get(label)
    if not backup:
        return False
    ok = reg_set(
        HIVE_MAP[backup["hive"]], backup["path"], backup["name"], int(backup["kind"]), backup["value"]
    )
    if ok and not CONFIG["ui"].get("dry_run"):
        del STATE["startup_backup"][label]
        save_state()
    return ok


# =============================================================================
# 1. GAMING SESSION + PREFLIGHT
# =============================================================================


def gaming_preflight_data() -> Dict[str, Any]:
    ram = psutil.virtual_memory()
    cpu = psutil.cpu_percent(interval=0.5)
    active = get_active_power_plan()
    adapter = get_active_adapter()
    gateway_latency = ping_once(adapter["Gateway"]) if adapter and adapter.get("Gateway") else None
    running = []
    for name in CONFIG["gaming_mode"]["kill_cloud_sync"] + CONFIG["gaming_mode"]["kill_browsers_comm"]:
        if proc_running(name):
            running.append(name)
    return {
        "cpu": cpu,
        "ram_available": ram.available,
        "ram_percent": ram.percent,
        "power": active,
        "adapter": adapter,
        "gateway_latency": gateway_latency,
        "background": running,
    }


def gaming_preflight() -> None:
    console.clear()
    header("GAMING PREFLIGHT", "Read-only check before starting a gaming session")
    data = gaming_preflight_data()
    t = Table(box=box.ROUNDED, show_header=False, padding=(0, 2))
    t.add_column("Check", style="bold white", width=20)
    t.add_column("Result", width=55)
    t.add_row("CPU Load", f"{data['cpu']:.0f}%")
    t.add_row("Available RAM", fmt_bytes(data["ram_available"]))
    t.add_row("Power Plan", data["power"].get("name", "Unknown"))
    t.add_row("Network", data["adapter"].get("InterfaceAlias", "Unknown") if data["adapter"] else "Not detected")
    t.add_row("Gateway Latency", f"{data['gateway_latency']} ms" if data["gateway_latency"] is not None else "No reply")
    bg = data["background"]
    t.add_row("Closable Background", ", ".join(bg[:8]) + (" …" if len(bg) > 8 else "") if bg else "None detected")
    console.print(t)
    console.print("\n  [dim]This screen does not change anything. Gaming Session is the action that follows.[/]")
    pause()


def start_gaming_session() -> None:
    console.clear()
    header("GAMING SESSION", "Temporarily reduces background activity and restores the original state when finished")
    dry_run_notice()

    existing = STATE.get("gaming_session")
    if existing and existing.get("active"):
        warn("A previous Gaming Session is still marked active. Restore it first from Restore & History.")
        pause()
        return

    gm = CONFIG["gaming_mode"]
    service_states = {name: get_service_state(name) for name in gm["services_stop"]}
    power_before = get_active_power_plan()
    process_before = []
    for name in gm["kill_browsers_comm"] + gm["kill_cloud_sync"] + gm["kill_vendor_optional"]:
        if proc_running(name):
            process_before.append(name)

    snapshot = {
        "power_before": power_before,
        "services_before": service_states,
        "processes_running_before": process_before,
        "started_at": datetime.now().isoformat(timespec="seconds"),
    }
    sid = create_snapshot("gaming", snapshot)
    STATE["gaming_session"] = {"active": True, "snapshot_id": sid, **snapshot}
    save_state()

    console.print("  [bold white]What will happen:[/]")
    console.print(f"  • Stop up to {len(gm['services_stop'])} optional background services")
    console.print(f"  • Close detected browser/communication/cloud apps ({len(process_before)} currently running)")
    console.print("  • Switch to High Performance when available")
    console.print("  • Original service states and power plan are saved for restore")
    console.print("  [dim]Closed applications are not auto-relaunched. Unsaved work is your responsibility.[/]\n")
    if not Confirm.ask("  Start Gaming Session?", default=False):
        STATE["gaming_session"] = None
        delete_snapshot(sid)
        return

    failures: List[str] = []
    with Progress(SpinnerColumn(style="red"), TextColumn("{task.description}"), console=console) as prog:
        task = prog.add_task("Closing configured background applications...", total=None)
        killed = 0
        for name in process_before:
            killed += kill_proc(name)
        prog.update(task, description=f"[green]✓[/] Closed {killed} matching process(es)")

        task = prog.add_task("Stopping optional background services...", total=None)
        stopped = 0
        for name, before in service_states.items():
            if before.get("State") == "Running":
                if svc_stop(name):
                    stopped += 1
                else:
                    failures.append(f"Could not stop {name}")
        prog.update(task, description=f"[green]✓[/] Stopped {stopped} service(s)" if not failures else f"[yellow]![/] Services stopped with {len(failures)} warning(s)")

        task = prog.add_task("Selecting High Performance power plan...", total=None)
        hp = find_plan_by_keyword("high performance")
        if gm.get("set_high_performance") and hp:
            if set_power_plan(hp[1]):
                prog.update(task, description="[green]✓[/] High Performance active")
            else:
                failures.append("Could not activate High Performance")
                prog.update(task, description="[yellow]![/] High Performance could not be verified")
        else:
            prog.update(task, description="[dim]High Performance not available; power plan unchanged[/]")

        task = prog.add_task("Flushing DNS cache...", total=None)
        ok = flush_dns()
        prog.update(task, description="[green]✓[/] DNS cache flushed" if ok else "[yellow]![/] DNS flush failed")

    add_history("Gaming Session", "active" if not failures else "warning", "; ".join(failures), sid)
    console.print()
    console.print(Panel(
        "[bold green]Gaming Session is active.[/]\n"
        "When you are finished, press Enter below to restore the original service states and power plan.\n"
        "[dim]If the toolkit closes unexpectedly, Restore & History can recover the saved session.[/]",
        border_style="green",
    ))
    console.input("\n  Press Enter to end Gaming Session and restore...")
    restore_gaming_session()
    pause()


def restore_gaming_session() -> bool:
    session = STATE.get("gaming_session")
    if not session or not session.get("active"):
        return True
    sid = session.get("snapshot_id")
    failures = []

    services = session.get("services_before", {})
    for name, before in services.items():
        wanted = before.get("State")
        if wanted == "Running":
            if not svc_start(name):
                failures.append(f"{name}: could not restore Running")
        elif wanted == "Stopped":
            if not svc_stop(name):
                failures.append(f"{name}: could not restore Stopped")

    guid = session.get("power_before", {}).get("guid")
    if guid and not set_power_plan(guid):
        failures.append("Original power plan could not be restored")

    STATE["gaming_session"] = None
    save_state()
    if sid:
        delete_snapshot(sid)
    add_history("Gaming Session Restore", "success" if not failures else "warning", "; ".join(failures))
    if not failures:
        success("Gaming Session restored to the saved system state.")
    else:
        warn("Gaming restore completed with warnings: " + "; ".join(failures))
    return not failures


# =============================================================================
# 2. POWER PLANS
# =============================================================================


def power_plan_manager() -> None:
    while True:
        console.clear()
        header("POWER PLANS", "Choose Windows power behavior. Higher performance can increase heat and battery use.")
        dry_run_notice()
        active = get_active_power_plan()
        plans = get_power_plans()
        console.print(f"  Current: [bold cyan]{active['name']}[/]  [dim]{active['guid']}[/]\n")

        t = Table(box=box.SIMPLE, show_header=False, padding=(0, 2))
        t.add_column(width=5, style="bold red")
        t.add_column(width=24, style="bold white")
        t.add_column(width=52, style="dim")
        t.add_row("[1]", "Balanced", "Recommended default. Windows balances speed, heat and power use.")
        t.add_row("[2]", "High Performance", "Keeps the system more responsive at higher idle power use.")
        t.add_row("[3]", "Ultimate Performance", "Desktop/workstation-oriented plan. May be unavailable on some laptops/Modern Standby PCs.")
        t.add_row("[4]", "Power Saver", "Reduces power use; useful on battery when available.")
        t.add_row("[5]", "Install Ultimate", "Creates Ultimate only if it is not already installed, then verifies the new GUID.")
        t.add_row("[0]", "Back", "Return to main menu.")
        console.print(t)
        choice = Prompt.ask("  [bold red]Choose[/]", choices=["0", "1", "2", "3", "4", "5"], show_choices=False)
        if choice == "0":
            return

        if choice == "5":
            ok, guid, msg = ensure_ultimate_plan()
            success(msg) if ok else error(msg)
            pause()
            continue

        keyword_map = {"1": "balanced", "2": "high performance", "3": "ultimate", "4": "power saver"}
        keyword = keyword_map[choice]
        found = find_plan_by_keyword(keyword)
        if choice == "3" and not found:
            saved_ultimate = STATE.get("ultimate_guid")
            if saved_ultimate and saved_ultimate.lower() in [g.lower() for g in get_power_plans().values()]:
                found = ("Ultimate Performance", saved_ultimate)
        if not found:
            if choice == "3":
                warn("Ultimate Performance is not installed. Use [5] Install Ultimate first.")
            else:
                warn(f"'{keyword.title()}' is not exposed by this PC's current power configuration.")
            pause()
            continue

        before = get_active_power_plan()
        sid = create_snapshot("power", {"before": before})
        if set_power_plan(found[1]):
            success(f"Active power plan → {found[0]}")
            add_history("Power Plan", "success", f"{before['name']} → {found[0]}", sid)
        else:
            error("Windows did not confirm the requested power plan.")
            add_history("Power Plan", "failed", f"Requested {found[0]}", sid)
        pause()


# =============================================================================
# 3. PERFORMANCE SETTINGS
# =============================================================================

VISUAL_KEYS = [
    ("HKCU", r"Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects", "VisualFXSetting"),
    ("HKCU", r"Control Panel\Desktop", "MenuShowDelay"),
    ("HKCU", r"Control Panel\Desktop\WindowMetrics", "MinAnimate"),
    ("HKCU", r"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "TaskbarAnimations"),
    ("HKCU", r"Software\Microsoft\Windows\DWM", "EnableAeroPeek"),
]

GAME_DVR_KEYS = [
    ("HKCU", r"System\GameConfigStore", "GameDVR_Enabled"),
    ("HKLM", r"SOFTWARE\Policies\Microsoft\Windows\GameDVR", "AllowgameDVR"),
    ("HKCU", r"SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR", "AppCaptureEnabled"),
]


def apply_visual_performance() -> Tuple[bool, str]:
    sid = create_snapshot("visual", {"registry": capture_registry_values(VISUAL_KEYS)})
    HKCU = winreg.HKEY_CURRENT_USER
    checks = [
        reg_set(HKCU, VISUAL_KEYS[0][1], VISUAL_KEYS[0][2], winreg.REG_DWORD, 2),
        reg_set(HKCU, VISUAL_KEYS[1][1], VISUAL_KEYS[1][2], winreg.REG_SZ, "0"),
        reg_set(HKCU, VISUAL_KEYS[2][1], VISUAL_KEYS[2][2], winreg.REG_SZ, "0"),
        reg_set(HKCU, VISUAL_KEYS[3][1], VISUAL_KEYS[3][2], winreg.REG_DWORD, 0),
        reg_set(HKCU, VISUAL_KEYS[4][1], VISUAL_KEYS[4][2], winreg.REG_DWORD, 0),
    ]
    ok = all(checks)
    add_history("Visual Performance", "success" if ok else "warning", "Reduced animations and delays", sid)
    return ok, sid


def disable_game_dvr() -> Tuple[bool, str]:
    sid = create_snapshot("gamedvr", {"registry": capture_registry_values(GAME_DVR_KEYS)})
    checks = [
        reg_set(winreg.HKEY_CURRENT_USER, GAME_DVR_KEYS[0][1], GAME_DVR_KEYS[0][2], winreg.REG_DWORD, 0),
        reg_set(winreg.HKEY_LOCAL_MACHINE, GAME_DVR_KEYS[1][1], GAME_DVR_KEYS[1][2], winreg.REG_DWORD, 0),
        reg_set(winreg.HKEY_CURRENT_USER, GAME_DVR_KEYS[2][1], GAME_DVR_KEYS[2][2], winreg.REG_DWORD, 0),
    ]
    ok = all(checks)
    add_history("Game DVR", "success" if ok else "warning", "Disabled capture/Game DVR", sid)
    return ok, sid


def performance_settings() -> None:
    while True:
        console.clear()
        header("PERFORMANCE SETTINGS", "Safe, reversible Windows settings. Experimental tweaks live in Advanced.")
        dry_run_notice()
        t = Table(box=box.SIMPLE, show_header=False, padding=(0, 2))
        t.add_column(width=5, style="bold red")
        t.add_column(width=28, style="bold white")
        t.add_column(width=48, style="dim")
        t.add_row("[1]", "Reduce Visual Effects", "Cuts animations/delays. Original registry values are snapshotted.")
        t.add_row("[2]", "Disable Game DVR", "Turns off Windows game capture/background recording settings.")
        t.add_row("[3]", "Apply Recommended", "Applies [1] + [2]. No HPET/Nagle folklore in the safe bundle.")
        t.add_row("[0]", "Back", "")
        console.print(t)
        c = Prompt.ask("  [bold red]Choose[/]", choices=["0", "1", "2", "3"], show_choices=False)
        if c == "0": return
        if c in ("1", "3"):
            ok, _ = apply_visual_performance()
            success("Visual performance settings applied.") if ok else warn("Some visual settings failed to apply.")
        if c in ("2", "3"):
            ok, _ = disable_game_dvr()
            success("Game DVR settings disabled.") if ok else warn("Some Game DVR settings failed to apply.")
        pause()


# =============================================================================
# 4. STORAGE CLEANUP
# =============================================================================


def folder_size(path: Path, limit_files: int = 200000) -> Tuple[int, int]:
    total = 0
    count = 0
    if not path.exists():
        return 0, 0
    try:
        for root, _dirs, files in os.walk(path):
            for name in files:
                if count >= limit_files:
                    return total, count
                fp = Path(root) / name
                try:
                    total += fp.stat().st_size
                    count += 1
                except Exception:
                    pass
    except Exception:
        pass
    return total, count


def clean_path(path: Path) -> Tuple[int, int]:
    removed = bytes_removed = 0
    if not path.exists():
        return 0, 0
    safety = FilesystemSafety(
        whitelist=expand_paths(_storage_cfg().get("protected_paths", [])),
        allowed_scopes=[path],
    )
    # Delete children, not the category root itself. Every mutation passes the
    # central filesystem policy, including symlink/reparse and whitelist checks.
    for root, dirs, files in os.walk(path, topdown=False, followlinks=False):
        for name in files:
            fp = Path(root) / name
            try:
                result = safety.delete(fp, dry_run=CONFIG["ui"].get("dry_run", False), risk=RiskLevel.SAFE)
                if result.deleted or result.dry_run:
                    removed += 1
                    bytes_removed += result.bytes_estimate
            except Exception:
                pass
        for name in dirs:
            dp = Path(root) / name
            try:
                # At this point directories should be empty; the same gate still
                # rejects reparse points and user-protected intersections.
                safety.delete(dp, dry_run=CONFIG["ui"].get("dry_run", False), risk=RiskLevel.SAFE)
            except Exception:
                pass
    return removed, bytes_removed


def browser_cache_paths() -> List[Path]:
    paths: List[Path] = []
    local = Path(os.path.expandvars(r"%LOCALAPPDATA%"))
    for base in [local / "Google/Chrome/User Data", local / "Microsoft/Edge/User Data"]:
        if base.exists():
            for profile in base.iterdir():
                if profile.is_dir() and (profile.name == "Default" or profile.name.startswith("Profile ")):
                    for rel in ["Cache/Cache_Data", "Code Cache", "GPUCache"]:
                        p = profile / rel
                        if p.exists(): paths.append(p)
    ff = local / "Mozilla/Firefox/Profiles"
    if ff.exists():
        for profile in ff.iterdir():
            p = profile / "cache2"
            if p.exists(): paths.append(p)
    return paths


def cleanup_categories() -> Dict[str, List[Path]]:
    return {
        "User Temp": [Path(os.path.expandvars(r"%TEMP%"))],
        "Windows Temp": [Path(os.path.expandvars(r"%WINDIR%\Temp"))],
        "Browser Cache": browser_cache_paths(),
        "WER Reports": [
            Path(os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\Windows\WER")),
            Path(os.path.expandvars(r"%ProgramData%\Microsoft\Windows\WER")),
        ],
        "Windows Update Cache": [Path(os.path.expandvars(r"%WINDIR%\SoftwareDistribution\Download"))],
        "Thumbnail Cache": [Path(os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\Windows\Explorer"))],
    }


def clean_thumbnail_cache() -> Tuple[int, int]:
    explorer = Path(os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\Windows\Explorer"))
    removed = total = 0
    if not explorer.exists(): return 0, 0
    safety = FilesystemSafety(
        whitelist=expand_paths(_storage_cfg().get("protected_paths", [])),
        allowed_scopes=[explorer],
    )
    for pattern in ("thumbcache_*.db", "iconcache_*.db"):
        for fp in explorer.glob(pattern):
            try:
                result = safety.delete(fp, dry_run=CONFIG["ui"].get("dry_run", False), risk=RiskLevel.SAFE)
                if result.deleted or result.dry_run:
                    removed += 1
                    total += result.bytes_estimate
            except Exception:
                pass
    return removed, total


def storage_cleanup() -> None:
    console.clear()
    header("STORAGE CLEANUP", "Preview first, then clean only the categories you choose. Prefetch is intentionally left alone.")
    dry_run_notice()
    cats = cleanup_categories()
    preview = []
    with Progress(SpinnerColumn(style="red"), TextColumn("{task.description}"), console=console) as prog:
        for name, paths in cats.items():
            task = prog.add_task(f"Scanning {name}...", total=None)
            if name == "Thumbnail Cache":
                explorer = paths[0]
                size = count = 0
                if explorer.exists():
                    for pattern in ("thumbcache_*.db", "iconcache_*.db"):
                        for fp in explorer.glob(pattern):
                            try: size += fp.stat().st_size; count += 1
                            except Exception: pass
            else:
                pairs = [folder_size(p) for p in paths]
                size = sum(x[0] for x in pairs); count = sum(x[1] for x in pairs)
            preview.append((name, size, count))
            prog.update(task, description=f"[green]✓[/] {name}: {fmt_bytes(size)}")

    t = Table(box=box.ROUNDED, header_style="bold red")
    t.add_column("#", width=4)
    t.add_column("Category", width=25)
    t.add_column("Estimated", justify="right", width=15)
    t.add_column("Files", justify="right", width=10)
    for i, (name, size, count) in enumerate(preview, 1):
        t.add_row(str(i), name, fmt_bytes(size), f"{count:,}")
    console.print(t)
    console.print("\n  Enter numbers separated by spaces, [bold white]ALL[/], or [bold white]BACK[/].")
    raw = Prompt.ask("  [bold red]Clean[/]")
    if raw.strip().upper() == "BACK" or not raw.strip(): return
    if raw.strip().upper() == "ALL":
        selected = list(range(len(preview)))
    else:
        selected = []
        for tok in raw.split():
            try:
                idx = int(tok) - 1
                if 0 <= idx < len(preview): selected.append(idx)
            except ValueError: pass
    if not selected:
        warn("No valid categories selected."); pause(); return

    browser_names = ["chrome.exe", "msedge.exe", "firefox.exe"]
    if any(proc_running(n) for n in browser_names) and any(preview[i][0] == "Browser Cache" for i in selected):
        warn("A supported browser is running. Locked cache files may be skipped.")
    if not Confirm.ask("  Delete the selected caches/temp files?", default=False): return

    total_files = total_bytes = 0
    wu_stopped = {}
    for idx in selected:
        name = preview[idx][0]
        if name == "Windows Update Cache":
            for svc in ("wuauserv", "bits"):
                wu_stopped[svc] = get_service_state(svc)
                if wu_stopped[svc].get("State") == "Running": svc_stop(svc)
        if name == "Thumbnail Cache":
            n, b = clean_thumbnail_cache()
        else:
            n = b = 0
            for p in cats[name]:
                a, c = clean_path(p); n += a; b += c
        total_files += n; total_bytes += b
        success(f"{name}: removed {n:,} file(s), {fmt_bytes(b)}")

    for svc, state in wu_stopped.items():
        if state.get("State") == "Running": svc_start(svc)
        elif state.get("State") == "Stopped": svc_stop(svc)

    # Recycle Bin is explicit, never automatic.
    if Confirm.ask("  Also empty Recycle Bin?", default=False):
        if CONFIG["ui"].get("dry_run"):
            success("Dry run: Recycle Bin would be emptied.")
        else:
            flags = 0x1 | 0x2 | 0x4
            rc = ctypes.windll.shell32.SHEmptyRecycleBinW(None, None, flags)
            success("Recycle Bin emptied.") if rc == 0 else warn(f"Recycle Bin returned code {rc}.")

    add_history("Storage Cleanup", "success", f"{total_files} files / {fmt_bytes(total_bytes)}")
    if CONFIG["ui"].get("dry_run"):
        summary = f"Would remove approximately [bold]{total_files:,}[/] file(s) · [bold]{fmt_bytes(total_bytes)}[/]."
        title = "Cleanup dry run"
    else:
        summary = f"Removed [bold]{total_files:,}[/] file(s) · reclaimed approximately [bold]{fmt_bytes(total_bytes)}[/]."
        title = "Cleanup complete"
    console.print(Panel(summary, title=title, border_style="green"))
    pause()


def dism_component_cleanup() -> None:
    console.clear(); header("WINDOWS COMPONENT CLEANUP", "Runs Microsoft's DISM component-store cleanup separately from normal cache cleaning.")
    if not Confirm.ask("  Run DISM /StartComponentCleanup?", default=False): return
    r = run(["dism", "/online", "/cleanup-image", "/startcomponentcleanup"], timeout=900, mutating=True)
    if r.ok or r.skipped:
        success("DISM component cleanup completed.")
        add_history("DISM Cleanup", "success")
    else:
        error("DISM cleanup failed. Check the log for details.")
        add_history("DISM Cleanup", "failed", r.stderr[-500:])
    pause()


# =============================================================================
# 5. NETWORK REPAIR
# =============================================================================


def network_repair() -> None:
    while True:
        console.clear()
        header("NETWORK REPAIR", "Safe repair handles common issues. Destructive reset is separated and clearly marked.")
        dry_run_notice()
        adapter = get_active_adapter()
        if adapter:
            console.print(f"  Active adapter: [bold cyan]{adapter['InterfaceAlias']}[/] · IP {adapter.get('IPv4')} · GW {adapter.get('Gateway')}\n")
        t = Table(box=box.SIMPLE, show_header=False, padding=(0, 2))
        t.add_column(width=5, style="bold red"); t.add_column(width=27, style="bold white"); t.add_column(width=50, style="dim")
        t.add_row("[1]", "Safe Network Repair", "Flush DNS, clear ARP, renew DHCP when the active adapter uses DHCP.")
        t.add_row("[2]", "Winsock Reset", "Requires restart. More invasive than normal cache repair.")
        t.add_row("[3]", "Destructive Reset", "TCP/IP + IPv6 + firewall reset. Backs up firewall policy first.")
        t.add_row("[0]", "Back", "")
        console.print(t)
        c = Prompt.ask("  [bold red]Choose[/]", choices=["0", "1", "2", "3"], show_choices=False)
        if c == "0": return
        if c == "1": safe_network_repair(); pause()
        elif c == "2":
            if Confirm.ask("  Reset Winsock? A restart is normally required.", default=False):
                r = run(["netsh", "winsock", "reset"], mutating=True)
                success("Winsock reset completed; restart Windows.") if (r.ok or r.skipped) else error("Winsock reset failed.")
                add_history("Winsock Reset", "success" if (r.ok or r.skipped) else "failed")
            pause()
        elif c == "3": destructive_network_reset(); pause()


def adapter_uses_dhcp(interface_index: int) -> Optional[bool]:
    data = ps_json(f"(Get-NetIPInterface -InterfaceIndex {int(interface_index)} -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).Dhcp")
    if isinstance(data, str): return data.lower() == "enabled"
    return None


def safe_network_repair() -> None:
    console.clear(); header("SAFE NETWORK REPAIR")
    adapter = get_active_adapter()
    if not adapter:
        error("No active IPv4 adapter with a default gateway was detected."); return
    results = []
    results.append(("Flush DNS", flush_dns()))
    arp = run(["netsh", "interface", "ip", "delete", "arpcache"], mutating=True)
    results.append(("Clear ARP", arp.ok or arp.skipped))

    dhcp = adapter_uses_dhcp(int(adapter["InterfaceIndex"]))
    if dhcp:
        # Renew only. Releasing first can unnecessarily drop connectivity if renew becomes slow.
        renew = run(["ipconfig", "/renew", adapter["InterfaceAlias"]], timeout=45, mutating=True)
        results.append(("DHCP renew", renew.ok or renew.skipped))
    else:
        info("DHCP renew skipped because the active adapter does not appear to use DHCP.")

    time.sleep(0.5)
    after = get_active_adapter()
    connectivity = bool(after and after.get("Gateway") and ping_once(after["Gateway"]) is not None)
    results.append(("Gateway verification", connectivity or CONFIG["ui"].get("dry_run")))
    for label, ok in results:
        success(label) if ok else warn(f"{label} failed or could not be verified")
    add_history("Safe Network Repair", "success" if all(x[1] for x in results) else "warning")


def destructive_network_reset() -> None:
    console.clear(); header("DESTRUCTIVE NETWORK RESET", "This resets TCP/IP, IPv6 and Windows Firewall policy.")
    warn("Custom firewall and connection-security rules can be removed.")
    if not Confirm.ask("  Continue with destructive reset?", default=False): return

    backup_path = APP_DIR / f"firewall-backup-{datetime.now():%Y%m%d_%H%M%S}.wfw"
    export = run(["netsh", "advfirewall", "export", str(backup_path)], timeout=30, mutating=True)
    if export.ok or export.skipped:
        success(f"Firewall policy backup: {backup_path.name}")
    else:
        error("Firewall backup failed. Destructive reset aborted.")
        return

    commands = [
        ("TCP/IP reset", ["netsh", "int", "ip", "reset"]),
        ("IPv6 reset", ["netsh", "int", "ipv6", "reset"]),
        ("Firewall reset", ["netsh", "advfirewall", "reset"]),
    ]
    statuses = []
    for label, cmd in commands:
        r = run(cmd, timeout=60, mutating=True)
        ok = r.ok or r.skipped
        statuses.append(ok)
        success(label) if ok else error(label)
    add_history("Destructive Network Reset", "success" if all(statuses) else "warning", f"Firewall backup: {backup_path.name}")
    warn("Restart Windows before judging the result.")


# =============================================================================
# 6. STARTUP MANAGER
# =============================================================================


def startup_manager() -> None:
    items = list(CONFIG["startup_apps"].items())
    while True:
        console.clear(); header("STARTUP MANAGER", "Toggle common startup entries. Disabled registry values are backed up for restoration.")
        dry_run_notice()
        t = Table(box=box.ROUNDED, header_style="bold red")
        t.add_column("#", width=4); t.add_column("App", width=18); t.add_column("Status", width=22); t.add_column("Command / source", width=55)
        for i, (label, (hive, path, name)) in enumerate(items, 1):
            value, _kind = _read_startup_val(hive, path, name)
            if value is not None: status = "[green]ENABLED[/]"
            elif label in STATE.get("startup_backup", {}): status = "[yellow]disabled · restorable[/]"
            else: status = "[dim]not found / disabled[/]"
            t.add_row(str(i), label, status, str(value)[:55] if value else f"{hive}\\{path}::{name}")
        console.print(t)
        console.print("\n  Number = toggle · [bold white]F[/] = open Startup folder · [bold white]T[/] = show enabled startup Scheduled Tasks · [bold white]0[/] = Back")
        raw = Prompt.ask("  [bold red]Choose[/]", default="0").strip()
        if raw == "0": return
        if raw.upper() == "F":
            subprocess.Popen(["explorer", "shell:startup"]); pause(); continue
        if raw.upper() == "T":
            startup_tasks_view(); pause(); continue
        try:
            idx = int(raw) - 1
        except ValueError:
            continue
        if not (0 <= idx < len(items)): continue
        label, (hive, path, name) = items[idx]
        value, _kind = _read_startup_val(hive, path, name)
        if value is not None:
            ok = _startup_disable(hive, path, name, label)
            success(f"{label} disabled and backed up.") if ok else error(f"Could not disable {label}.")
        else:
            ok = _startup_restore(label)
            success(f"{label} restored.") if ok else warn(f"No saved value exists for {label}.")
        add_history("Startup Toggle", "success" if ok else "warning", label)
        pause()


def startup_tasks_view() -> None:
    console.clear(); header("STARTUP SCHEDULED TASKS", "Read-only view of enabled logon/startup scheduled tasks")
    data = ps_json(r"""
Get-ScheduledTask | Where-Object {
 $_.State -ne 'Disabled' -and ($_.Triggers.CimClass.CimClassName -match 'Logon|Boot')
} | Select-Object TaskName,TaskPath,State
""", timeout=30)
    rows = data if isinstance(data, list) else ([data] if isinstance(data, dict) else [])
    t = Table(box=box.ROUNDED, header_style="bold red")
    t.add_column("Task", width=38); t.add_column("Path", width=38); t.add_column("State", width=12)
    for row in rows[:100]:
        t.add_row(str(row.get("TaskName", "")), str(row.get("TaskPath", "")), str(row.get("State", "")))
    console.print(t if rows else "  [dim]No matching tasks found.[/]")


# =============================================================================
# 7. APP MANAGER / DEBLOAT
# =============================================================================


def appx_installed(pattern: str) -> bool:
    p = pattern.replace("'", "''")
    r = run_ps(f"if(Get-AppxPackage -Name '{p}' -ErrorAction SilentlyContinue){{exit 0}}else{{exit 3}}")
    return r.returncode == 0


def app_manager() -> None:
    console.clear(); header("APP MANAGER / DEBLOAT", "Only detected optional Appx packages are listed. Removal is explicit and verified.")
    dry_run_notice()
    detected = []
    with Progress(SpinnerColumn(style="red"), TextColumn("{task.description}"), console=console) as prog:
        for label, pattern, category in CONFIG["bloat_apps"]:
            task = prog.add_task(f"Checking {label}...", total=None)
            if appx_installed(pattern): detected.append((label, pattern, category))
            prog.update(task, description=f"[green]✓[/] Checked {label}")
    if not detected:
        info("No configured optional Appx packages were detected."); pause(); return

    t = Table(box=box.ROUNDED, header_style="bold red")
    t.add_column("#", width=4); t.add_column("App", width=26); t.add_column("Category", width=23); t.add_column("Pattern", width=30)
    for i, row in enumerate(detected, 1): t.add_row(str(i), row[0], row[2], row[1])
    console.print(t)
    console.print("\n  Numbers separated by spaces · [bold white]BACK[/] to return.")
    raw = Prompt.ask("  [bold red]Remove[/]")
    if raw.upper() == "BACK" or not raw.strip(): return
    idxs = []
    for tok in raw.split():
        try:
            x = int(tok)-1
            if 0 <= x < len(detected): idxs.append(x)
        except ValueError: pass
    if not idxs: warn("No valid selection."); pause(); return

    console.print("\n  Removal scope:")
    console.print("  [1] Current user only  [dim]safest[/]")
    console.print("  [2] Current user + provisioning  [dim]also prevents selected package from provisioning for new users[/]")
    console.print("  [3] All users + provisioning  [dim]Advanced Mode only; affects every local user profile[/]")
    scope = Prompt.ask("  [bold red]Scope[/]", choices=["1", "2", "3"], default="1", show_choices=False)
    if scope == "3" and CONFIG["ui"].get("safe_mode", True):
        warn("All-user removal is locked in Safe Mode.")
        pause(); return
    if not Confirm.ask(f"  Remove {len(idxs)} selected package pattern(s)?", default=False): return

    for idx in idxs:
        label, pattern, _category = detected[idx]
        escaped = pattern.replace("'", "''")
        if scope == "3":
            script = f"Get-AppxPackage -AllUsers -Name '{escaped}' -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue"
        else:
            script = f"Get-AppxPackage -Name '{escaped}' -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue"
        r = run_ps(script, timeout=120, mutating=True)
        if scope in ("2", "3"):
            prov = (
                f"Get-AppxProvisionedPackage -Online | Where-Object {{$_.DisplayName -like '{escaped}'}} | "
                "Remove-AppxProvisionedPackage -Online -AllUsers -ErrorAction SilentlyContinue | Out-Null"
            )
            run_ps(prov, timeout=120, mutating=True)
        still = appx_installed(pattern) if not CONFIG["ui"].get("dry_run") else False
        if (r.ok or r.skipped) and not still:
            if CONFIG["ui"].get("dry_run"):
                success(f"Dry run: would remove {label}")
            else:
                success(f"Removed: {label}")
            add_history("App Remove", "success", label)
        else:
            warn(f"Could not fully verify removal: {label}")
            add_history("App Remove", "warning", label)
    pause()


# =============================================================================
# 8. APP UPDATES / WINGET
# =============================================================================


def app_updates() -> None:
    while True:
        console.clear(); header("APP UPDATES", "Uses WinGet. Preview updates first; nothing is upgraded automatically just by opening this page.")
        if not shutil.which("winget"):
            error("WinGet was not found on this PC."); pause(); return
        t = Table(box=box.SIMPLE, show_header=False, padding=(0, 2))
        t.add_column(width=5, style="bold red"); t.add_column(width=25, style="bold white"); t.add_column(width=55, style="dim")
        t.add_row("[1]", "List Available Updates", "Read-only WinGet update list.")
        t.add_row("[2]", "Upgrade One Package", "Enter exact WinGet package ID/name and upgrade only that package.")
        t.add_row("[3]", "Upgrade All", "Runs winget upgrade --all after an explicit confirmation.")
        t.add_row("[0]", "Back", "")
        console.print(t)
        c = Prompt.ask("  [bold red]Choose[/]", choices=["0","1","2","3"], show_choices=False)
        if c == "0": return
        if c == "1":
            r = run(["winget", "list", "--upgrade-available", "--accept-source-agreements"], timeout=120)
            console.print(r.stdout if r.stdout.strip() else r.stderr); pause()
        elif c == "2":
            pkg = Prompt.ask("  Exact package ID or query").strip()
            if pkg and Confirm.ask(f"  Upgrade '{pkg}'?", default=False):
                r = run(["winget", "upgrade", "--id", pkg, "--exact", "--accept-source-agreements", "--accept-package-agreements"], timeout=1200, mutating=True)
                success("WinGet command completed.") if (r.ok or r.skipped) else error("WinGet upgrade failed.")
                console.print(r.stdout[-4000:] if r.stdout else r.stderr[-4000:]); add_history("App Upgrade", "success" if (r.ok or r.skipped) else "failed", pkg); pause()
        elif c == "3":
            warn("This can update many third-party applications and may close/restart some installers.")
            if Confirm.ask("  Upgrade all packages WinGet considers upgradeable?", default=False):
                r = run(["winget", "upgrade", "--all", "--accept-source-agreements", "--accept-package-agreements"], timeout=3600, mutating=True)
                success("WinGet upgrade-all completed.") if (r.ok or r.skipped) else warn("WinGet finished with errors; inspect the output/log.")
                console.print((r.stdout or r.stderr)[-6000:]); add_history("App Upgrade All", "success" if (r.ok or r.skipped) else "warning"); pause()


# =============================================================================
# 9. DNS BENCHMARK & SWITCH
# =============================================================================


def dns_benchmark_switch() -> None:
    console.clear(); header("DNS BENCHMARK & SWITCH", "Tests real DNS queries, ranks resolvers, then lets you apply and verify a provider.")
    dry_run_notice()
    adapter = get_active_adapter()
    if not adapter:
        error("No active IPv4 adapter with a default gateway was detected."); pause(); return
    idx = int(adapter["InterfaceIndex"])
    current_dns = get_adapter_dns(idx)
    console.print(f"  Adapter : [bold cyan]{adapter['InterfaceAlias']}[/]  [dim]{adapter.get('Description','')}[/]")
    console.print(f"  Current DNS: [bold white]{', '.join(current_dns) if current_dns else 'Automatic / not reported'}[/]\n")

    providers = CONFIG["dns_providers"]
    domains = CONFIG["dns_test_domains"]
    results = []
    with Progress(SpinnerColumn(style="red"), TextColumn("{task.description}"), console=console) as prog:
        for pvd in providers:
            task = prog.add_task(f"Testing {pvd['name']} ({pvd['primary']})...", total=None)
            res = benchmark_dns_provider(pvd, domains, rounds=2)
            results.append(res)
            prog.update(task, description=f"[green]✓[/] {pvd['name']}: median {res['median']} ms / {res['success']}% success")
    results.sort(key=lambda x: (-x["success"], x["median"], x["p95"]))

    t = Table(box=box.ROUNDED, header_style="bold red")
    t.add_column("#", width=4); t.add_column("Provider", width=18); t.add_column("Primary", width=17)
    t.add_column("Median", justify="right", width=10); t.add_column("P95", justify="right", width=10); t.add_column("Success", justify="right", width=10)
    for i, r in enumerate(results, 1):
        name = ("★ " if i == 1 and r["success"] >= 80 else "") + r["name"]
        t.add_row(str(i), name, r["primary"], f"{r['median']:.1f} ms" if r['median'] < 9000 else "timeout", f"{r['p95']:.1f} ms" if r['p95'] < 9000 else "timeout", f"{r['success']:.0f}%")
    console.print(t)
    console.print("\n  [A] Apply best · [S] Select provider · [R] Restore Automatic/DHCP · [B] Back")
    action = Prompt.ask("  [bold red]Choose[/]", default="B").upper()
    if action == "B": return
    if action == "R":
        before = current_dns
        sid = create_snapshot("dns", {"interface_index": idx, "interface_alias": adapter["InterfaceAlias"], "dns_before": before})
        ok = reset_adapter_dns(idx)
        flush_dns()
        after = get_adapter_dns(idx)
        if ok:
            success(f"DNS reset to adapter defaults. Current reported servers: {', '.join(after) if after else 'automatic'}")
            add_history("DNS Reset", "success", adapter["InterfaceAlias"], sid)
        else:
            error("Windows did not confirm the DNS reset.")
        pause(); return

    chosen = None
    if action == "A": chosen = results[0]
    elif action == "S":
        raw = Prompt.ask("  Provider number")
        try:
            chosen = results[int(raw)-1]
        except Exception:
            warn("Invalid provider."); pause(); return
    if not chosen: return
    if chosen["success"] < 80:
        warn("The selected resolver had a low benchmark success rate. Applying it is not recommended.")
        if not Confirm.ask("  Apply anyway?", default=False): return

    sid = create_snapshot("dns", {"interface_index": idx, "interface_alias": adapter["InterfaceAlias"], "dns_before": current_dns})
    servers = [chosen["primary"], chosen["secondary"]]
    if set_adapter_dns(idx, servers):
        flush_dns()
        verify_ms = dns_query_ms(chosen["primary"], "microsoft.com")
        actual = get_adapter_dns(idx)
        if actual[:2] == servers and verify_ms is not None:
            success(f"{chosen['name']} applied and verified: {', '.join(servers)} · test query {verify_ms:.1f} ms")
            add_history("DNS Change", "success", f"{adapter['InterfaceAlias']} → {chosen['name']} ({', '.join(servers)})", sid)
        else:
            warn("DNS setting changed, but end-to-end verification was incomplete.")
            add_history("DNS Change", "warning", chosen["name"], sid)
    else:
        error("Failed to apply DNS servers.")
        add_history("DNS Change", "failed", chosen["name"], sid)
    pause()


# =============================================================================
# 10. NETWORK DIAGNOSTICS
# =============================================================================


def network_diagnostics() -> None:
    console.clear(); header("NETWORK DIAGNOSTICS", "Read-only checks to separate local Wi-Fi/LAN, internet and DNS problems.")
    adapter = get_active_adapter()
    if not adapter:
        error("No active adapter with a default IPv4 gateway was detected."); pause(); return
    gateway = adapter.get("Gateway")
    checks = []
    gw_vals = ping_series(gateway, 5) if gateway else []
    gw_stats = latency_stats(gw_vals) if gw_vals else {"avg":0,"loss":100,"jitter":0,"min":0,"max":0}
    checks.append(("Gateway", f"{gw_stats['avg']:.1f} ms / {gw_stats['loss']:.0f}% loss", gw_stats["loss"] == 0 and gw_stats["avg"] < 20))

    internet_vals = ping_series("1.1.1.1", 5)
    internet_stats = latency_stats(internet_vals)
    checks.append(("Internet", f"{internet_stats['avg']:.1f} ms / {internet_stats['loss']:.0f}% loss / jitter {internet_stats['jitter']:.1f} ms", internet_stats["loss"] < 20))

    dns_servers = get_adapter_dns(int(adapter["InterfaceIndex"]))
    dns_ms = dns_query_ms(dns_servers[0], "microsoft.com") if dns_servers else None
    checks.append(("DNS", f"{dns_ms:.1f} ms" if dns_ms is not None else "failed", dns_ms is not None))

    https = False
    try:
        s = socket.create_connection(("www.microsoft.com", 443), timeout=3)
        s.close(); https = True
    except Exception: pass
    checks.append(("HTTPS Reachability", "OK" if https else "failed", https))

    t = Table(box=box.ROUNDED, header_style="bold red")
    t.add_column("Check", width=25); t.add_column("Result", width=45); t.add_column("Status", width=12)
    for label, value, ok in checks: t.add_row(label, value, "[green]OK[/]" if ok else "[yellow]CHECK[/]")
    console.print(t)

    likely = "No obvious issue detected."
    if gw_stats["loss"] > 0 or gw_stats["avg"] >= 20: likely = "Local network/Wi-Fi/router path looks suspicious."
    elif internet_stats["loss"] >= 20: likely = "Internet/ISP path is unstable while the local gateway looks healthier."
    elif dns_ms is None: likely = "Connectivity works, but DNS resolution is failing."
    elif dns_ms > 100: likely = "DNS resolution is working but relatively slow; run DNS Benchmark & Switch."
    console.print(Panel(likely, title="Likely interpretation", border_style="cyan"))
    if Confirm.ask("  Run traceroute to 1.1.1.1?", default=False):
        r = run(["tracert", "-d", "-h", "20", "1.1.1.1"], timeout=90)
        console.print(r.stdout or r.stderr)
    pause()


# =============================================================================
# 11. LATENCY MONITOR
# =============================================================================


def latency_monitor() -> None:
    while True:
        console.clear(); header("LATENCY MONITOR", "Continuous ping with latency, jitter and packet-loss statistics. Ctrl+C stops the monitor.")
        adapter = get_active_adapter()
        targets = list(CONFIG["latency_targets"])
        if adapter and adapter.get("Gateway"):
            targets.insert(0, [adapter["Gateway"], f"Gateway ({adapter['InterfaceAlias']})"])
        t = Table(box=box.SIMPLE, show_header=False, padding=(0, 2))
        t.add_column(width=5, style="bold red"); t.add_column(width=20); t.add_column(width=35)
        for i, (host, label) in enumerate(targets, 1): t.add_row(f"[{i}]", host, label)
        custom = len(targets)+1
        t.add_row(f"[{custom}]", "Custom", "IP address or hostname")
        t.add_row("[0]", "Back", "")
        console.print(t)
        raw = Prompt.ask("  [bold red]Choose[/]", default="0")
        if raw == "0": return
        if raw == str(custom): host = Prompt.ask("  Target").strip()
        else:
            try: host = targets[int(raw)-1][0]
            except Exception: continue
        continuous_latency(host)


def continuous_latency(host: str) -> None:
    console.clear(); header(f"LATENCY MONITOR // {host}", "Ctrl+C to stop")
    values: List[Optional[int]] = []
    seq = 0
    try:
        while True:
            seq += 1
            ms = ping_once(host)
            values.append(ms)
            st = latency_stats(values)
            dot = "[green]●[/]" if ms is not None else "[red]●[/]"
            current = f"{ms} ms" if ms is not None else "timeout"
            console.print(f"  {dot} #{seq:>4}  {current:<10}  [dim]avg {st['avg']:.1f} · jitter {st['jitter']:.1f} · min {st['min']:.0f} · max {st['max']:.0f} · loss {st['loss']:.1f}%[/]")
            time.sleep(1)
    except KeyboardInterrupt:
        st = latency_stats(values)
        console.print(f"\n  [bold]Summary:[/] avg {st['avg']:.1f} ms · jitter {st['jitter']:.1f} ms · loss {st['loss']:.1f}%")
        pause()


# =============================================================================
# 12. SYSTEM DASHBOARD (CIM, NO WMIC)
# =============================================================================


def cim_first(class_name: str, props: Sequence[str]) -> Dict[str, Any]:
    selects = ",".join(props)
    data = ps_json(f"Get-CimInstance {class_name} -ErrorAction SilentlyContinue | Select-Object -First 1 {selects}")
    return data if isinstance(data, dict) else {}


def cim_many(class_name: str, props: Sequence[str]) -> List[Dict[str, Any]]:
    selects = ",".join(props)
    data = ps_json(f"Get-CimInstance {class_name} -ErrorAction SilentlyContinue | Select-Object {selects}")
    if isinstance(data, list): return [x for x in data if isinstance(x, dict)]
    if isinstance(data, dict): return [data]
    return []


def system_dashboard() -> None:
    console.clear(); header("SYSTEM DASHBOARD", "Hardware, Windows, storage, security and network overview using CIM instead of deprecated WMIC")
    osd = cim_first("Win32_OperatingSystem", ["Caption","Version","BuildNumber","OSArchitecture","LastBootUpTime"])
    cpu = cim_first("Win32_Processor", ["Name","NumberOfCores","NumberOfLogicalProcessors","MaxClockSpeed","VirtualizationFirmwareEnabled","SecondLevelAddressTranslationExtensions"])
    gpus = cim_many("Win32_VideoController", ["Name","DriverVersion"])
    board = cim_first("Win32_BaseBoard", ["Manufacturer","Product"])
    bios = cim_first("Win32_BIOS", ["SMBIOSBIOSVersion","ReleaseDate"])
    physical_disks = ps_json("Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object FriendlyName,MediaType,BusType,HealthStatus,OperationalStatus,Size")
    if isinstance(physical_disks, dict): physical_disks = [physical_disks]
    if not isinstance(physical_disks, list): physical_disks = []
    secure_boot = ps_json("try { [pscustomobject]@{Enabled=[bool](Confirm-SecureBootUEFI -ErrorAction Stop)} } catch { [pscustomobject]@{Enabled=$null} }")
    tpm = ps_json("try { Get-Tpm -ErrorAction Stop | Select-Object TpmPresent,TpmReady,TpmEnabled } catch { $null }")
    activation = ps_json("Get-CimInstance SoftwareLicensingProduct -ErrorAction SilentlyContinue | Where-Object {$_.PartialProductKey -and $_.Name -like 'Windows*'} | Select-Object -First 1 Name,LicenseStatus")
    mem = psutil.virtual_memory(); disk = psutil.disk_usage("C:\\")
    adapter = get_active_adapter(); power = get_active_power_plan()

    t = Table(box=box.ROUNDED, show_header=False, padding=(0, 2))
    t.add_column(width=20, style="bold red"); t.add_column(width=72, style="bold white")
    t.add_row("Windows", f"{osd.get('Caption','N/A')} · {osd.get('Version','')} · build {osd.get('BuildNumber','')} · {osd.get('OSArchitecture','')}")
    t.add_row("CPU", f"{cpu.get('Name','N/A')} · {cpu.get('NumberOfCores','?')}C/{cpu.get('NumberOfLogicalProcessors','?')}T · max {cpu.get('MaxClockSpeed','?')} MHz")
    virt = cpu.get('VirtualizationFirmwareEnabled')
    t.add_row("Virtualization", "Enabled in firmware" if virt is True else "Not enabled / not reported" if virt is False else "Unknown")
    t.add_row("RAM", f"{fmt_bytes(mem.total)} total · {fmt_bytes(mem.available)} available · {mem.percent:.0f}% used")
    t.add_row("Disk C:", f"{fmt_bytes(disk.total)} total · {fmt_bytes(disk.free)} free · {disk.percent:.0f}% used")
    for i, pd in enumerate(physical_disks[:6], 1):
        size = fmt_bytes(int(pd.get('Size') or 0)) if pd.get('Size') else "?"
        t.add_row(f"Physical Disk {i}", f"{pd.get('FriendlyName','?')} · {pd.get('MediaType','?')} · {pd.get('BusType','?')} · {size} · health {pd.get('HealthStatus','?')}")
    t.add_row("GPU", " | ".join(f"{g.get('Name','')} ({g.get('DriverVersion','')})" for g in gpus) or "N/A")
    t.add_row("Motherboard", f"{board.get('Manufacturer','')} {board.get('Product','')}".strip() or "N/A")
    t.add_row("BIOS", f"{bios.get('SMBIOSBIOSVersion','N/A')} · {bios.get('ReleaseDate','')}")
    if isinstance(secure_boot, dict):
        sb = secure_boot.get('Enabled'); t.add_row("Secure Boot", "Enabled" if sb is True else "Disabled" if sb is False else "Unsupported / unknown")
    if isinstance(tpm, dict):
        t.add_row("TPM", f"present {tpm.get('TpmPresent')} · ready {tpm.get('TpmReady')} · enabled {tpm.get('TpmEnabled')}")
    if isinstance(activation, dict):
        t.add_row("Activation", "Licensed" if activation.get('LicenseStatus') == 1 else f"License status {activation.get('LicenseStatus')}")
    t.add_row("Power Plan", power.get("name", "Unknown"))
    if adapter:
        t.add_row("Network", f"{adapter.get('InterfaceAlias')} · {adapter.get('IPv4')} · GW {adapter.get('Gateway')}")
        t.add_row("DNS", ", ".join(get_adapter_dns(int(adapter['InterfaceIndex']))) or "Automatic / unknown")
    console.print(t)

    if Confirm.ask("  Export this dashboard to JSON?", default=False):
        out = APP_DIR / f"system-report-{datetime.now():%Y%m%d_%H%M%S}.json"
        report = {
            "os":osd,"cpu":cpu,"gpu":gpus,"motherboard":board,"bios":bios,
            "ram":dict(mem._asdict()),"disk":dict(disk._asdict()),"physical_disks":physical_disks,
            "secure_boot":secure_boot,"tpm":tpm,"activation":activation,"network":adapter,"power":power
        }
        atomic_write_json(out, report); success(f"Saved: {out.name}")
    pause()


# =============================================================================
# 13. SYSTEM HEALTH + SELF DIAGNOSTICS
# =============================================================================


def system_health() -> None:
    console.clear(); header("SYSTEM HEALTH", "Read-only summary. It reports issues instead of changing Windows behind your back.")
    checks: List[Tuple[str,str,str]] = []
    mem = psutil.virtual_memory(); disk = psutil.disk_usage("C:\\")
    checks.append(("RAM", f"{mem.percent:.0f}% used", "OK" if mem.percent < 90 else "WARN"))
    checks.append(("Disk C:", f"{disk.percent:.0f}% used · {fmt_bytes(disk.free)} free", "OK" if disk.percent < 90 else "WARN"))
    adapter = get_active_adapter()
    checks.append(("Network adapter", adapter.get("InterfaceAlias", "") if adapter else "not detected", "OK" if adapter else "WARN"))
    if adapter and adapter.get("Gateway"):
        gw = ping_once(adapter["Gateway"]); checks.append(("Gateway", f"{gw} ms" if gw is not None else "no reply", "OK" if gw is not None else "WARN"))
    internet = ping_once("1.1.1.1"); checks.append(("Internet", f"{internet} ms" if internet is not None else "no reply", "OK" if internet is not None else "WARN"))
    if adapter:
        dns_servers = get_adapter_dns(int(adapter["InterfaceIndex"])); dms = dns_query_ms(dns_servers[0], "microsoft.com") if dns_servers else None
        checks.append(("DNS", f"{dms:.1f} ms" if dms is not None else "query failed", "OK" if dms is not None and dms < 120 else "WARN"))
    defender = ps_json("Get-MpComputerStatus -ErrorAction SilentlyContinue | Select-Object AntivirusEnabled,RealTimeProtectionEnabled,AntivirusSignatureLastUpdated")
    if isinstance(defender, dict):
        enabled = bool(defender.get("AntivirusEnabled")) and bool(defender.get("RealTimeProtectionEnabled"))
        checks.append(("Defender", "real-time protection on" if enabled else "protection not fully enabled", "OK" if enabled else "WARN"))
    checks.append(("Power Plan", get_active_power_plan().get("name","Unknown"), "OK"))
    checks.append(("WinGet", "available" if shutil.which("winget") else "not found", "OK" if shutil.which("winget") else "INFO"))
    checks.append(("State file", str(STATE_PATH.name), "OK" if STATE_PATH.exists() else "WARN"))
    checks.append(("Log file", str(LOG_PATH.name), "OK"))

    t = Table(box=box.ROUNDED, header_style="bold red")
    t.add_column("Check", width=25); t.add_column("Result", width=52); t.add_column("Status", width=10)
    for label, result, status in checks:
        color = "green" if status == "OK" else "yellow" if status == "WARN" else "cyan"
        t.add_row(label, result, f"[{color}]{status}[/]")
    console.print(t)
    console.print(f"\n  [dim]Session log: {LOG_PATH}[/]")
    pause()


# =============================================================================
# 14. DEFENDER
# =============================================================================


def defender_center() -> None:
    while True:
        console.clear(); header("WINDOWS DEFENDER", "Status, signature updates and scans using Microsoft's Defender PowerShell commands")
        status = ps_json("Get-MpComputerStatus -ErrorAction SilentlyContinue | Select-Object AntivirusEnabled,AntispywareEnabled,RealTimeProtectionEnabled,AntivirusSignatureVersion,AntivirusSignatureLastUpdated,QuickScanAge,FullScanAge")
        if isinstance(status, dict):
            t = Table(box=box.ROUNDED, show_header=False, padding=(0,2))
            t.add_column(width=30, style="bold red"); t.add_column(width=55)
            for k, v in status.items(): t.add_row(k, str(v))
            console.print(t)
        else:
            warn("Microsoft Defender status could not be queried. Another antivirus or edition policy may be in use.")
        console.print("\n  [1] Update signatures  [2] Quick scan  [3] Show detected threats  [0] Back")
        c = Prompt.ask("  [bold red]Choose[/]", choices=["0","1","2","3"], show_choices=False)
        if c == "0": return
        if c == "1":
            r = run_ps("Update-MpSignature -ErrorAction Stop", timeout=600, mutating=True)
            success("Defender signatures updated.") if (r.ok or r.skipped) else error("Signature update failed.")
            add_history("Defender Update", "success" if (r.ok or r.skipped) else "failed"); pause()
        elif c == "2":
            r = run_ps("Start-MpScan -ScanType QuickScan -ErrorAction Stop", timeout=3600, mutating=True)
            success("Quick scan command completed.") if (r.ok or r.skipped) else error("Quick scan failed.")
            add_history("Defender Quick Scan", "success" if (r.ok or r.skipped) else "failed"); pause()
        elif c == "3":
            data = ps_json("Get-MpThreatDetection -ErrorAction SilentlyContinue | Select-Object ThreatID,InitialDetectionTime,Resources,ActionSuccess")
            rows = data if isinstance(data,list) else ([data] if isinstance(data,dict) else [])
            console.print_json(data=rows) if rows else info("No threat-detection records returned.")
            pause()


# =============================================================================
# 15. PRIVACY CONTROLS
# =============================================================================

PRIVACY_ITEMS = {
    "Telemetry": {
        "registry": [
            ("HKLM", r"SOFTWARE\Policies\Microsoft\Windows\DataCollection", "AllowTelemetry", winreg.REG_DWORD, 0),
            ("HKLM", r"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection", "AllowTelemetry", winreg.REG_DWORD, 0),
        ],
        "services": ["DiagTrack", "dmwappushservice"],
    },
    "Activity History": {
        "registry": [
            ("HKLM", r"SOFTWARE\Policies\Microsoft\Windows\System", "EnableActivityFeed", winreg.REG_DWORD, 0),
            ("HKLM", r"SOFTWARE\Policies\Microsoft\Windows\System", "PublishUserActivities", winreg.REG_DWORD, 0),
            ("HKLM", r"SOFTWARE\Policies\Microsoft\Windows\System", "UploadUserActivities", winreg.REG_DWORD, 0),
        ], "services": []
    },
    "Advertising ID": {
        "registry": [("HKCU", r"Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo", "Enabled", winreg.REG_DWORD, 0)], "services": []
    },
    "Bing Search Suggestions": {
        "registry": [("HKCU", r"SOFTWARE\Policies\Microsoft\Windows\Explorer", "DisableSearchBoxSuggestions", winreg.REG_DWORD, 1)], "services": []
    },
    "Clipboard Sync": {
        "registry": [
            ("HKCU", r"Software\Microsoft\Clipboard", "EnableClipboardHistory", winreg.REG_DWORD, 0),
            ("HKLM", r"SOFTWARE\Policies\Microsoft\Windows\System", "AllowClipboardHistory", winreg.REG_DWORD, 0),
            ("HKLM", r"SOFTWARE\Policies\Microsoft\Windows\System", "AllowCrossDeviceClipboard", winreg.REG_DWORD, 0),
        ], "services": []
    },
}


def privacy_controls() -> None:
    while True:
        console.clear(); header("PRIVACY CONTROLS", "Recommended privacy settings with registry/service snapshots for restoration.")
        dry_run_notice()
        names = list(PRIVACY_ITEMS)
        t = Table(box=box.ROUNDED, header_style="bold red")
        t.add_column("#", width=4); t.add_column("Control", width=28); t.add_column("What it changes", width=55)
        descriptions = {
            "Telemetry":"Reduces Windows diagnostic/telemetry collection where policy permits.",
            "Activity History":"Stops activity-feed publishing/upload policy.",
            "Advertising ID":"Disables the per-user advertising identifier.",
            "Bing Search Suggestions":"Disables web suggestions in Windows search box policy.",
            "Clipboard Sync":"Disables clipboard history/cross-device clipboard policy.",
        }
        for i,n in enumerate(names,1): t.add_row(str(i),n,descriptions[n])
        t.add_row("A","Apply Recommended","Apply all controls above, each with a snapshot.")
        t.add_row("0","Back","")
        console.print(t)
        raw = Prompt.ask("  [bold red]Choose[/]", default="0").upper()
        if raw == "0": return
        selected = names if raw == "A" else []
        if not selected:
            try: selected = [names[int(raw)-1]]
            except Exception: continue
        for name in selected:
            item = PRIVACY_ITEMS[name]
            reg_items = [(h,p,n) for h,p,n,_k,_v in item["registry"]]
            services = {svc:get_service_state(svc) for svc in item["services"]}
            sid = create_snapshot("privacy", {"name":name,"registry":capture_registry_values(reg_items),"services":services})
            oks = []
            for hive_name,path,key,kind,value in item["registry"]:
                oks.append(reg_set(HIVE_MAP[hive_name],path,key,kind,value))
            for svc in item["services"]:
                svc_stop(svc); oks.append(svc_set_start(svc,"Disabled"))
            ok = all(oks)
            success(f"{name} applied.") if ok else warn(f"{name} applied with warning(s).")
            add_history("Privacy Control", "success" if ok else "warning", name, sid)
        pause()


# =============================================================================
# 16. RESTORE & HISTORY
# =============================================================================


def restore_history() -> None:
    while True:
        console.clear(); header("RESTORE & HISTORY", "View recent changes and restore supported snapshots. This is the toolkit's safety net.")
        session = STATE.get("gaming_session")
        if session and session.get("active"):
            warn(f"Unrestored Gaming Session detected from {session.get('started_at','unknown time')}.")
            console.print("  [bold white]G[/] Restore Gaming Session now\n")

        history = list(reversed(STATE.get("history", [])[-20:]))
        t = Table(box=box.ROUNDED, header_style="bold red")
        t.add_column("#", width=4); t.add_column("Time", width=20); t.add_column("Action", width=26); t.add_column("Status", width=12); t.add_column("Restore", width=10); t.add_column("Detail", width=38)
        restorable_indices: Dict[str,str] = {}
        for i,h in enumerate(history,1):
            sid = h.get("snapshot_id")
            can = bool(sid and sid in STATE.get("snapshots", {}))
            if can: restorable_indices[str(i)] = sid
            t.add_row(str(i),h.get("time","").replace("T"," "),h.get("action",""),h.get("status",""),"yes" if can else "—",h.get("detail","")[:38])
        console.print(t)
        console.print("\n  Enter a restorable row number · [bold white]G[/] gaming recovery · [bold white]P[/] create Windows restore point · [bold white]0[/] Back")
        raw = Prompt.ask("  [bold red]Choose[/]", default="0").upper()
        if raw == "0": return
        if raw == "G":
            restore_gaming_session(); pause(); continue
        if raw == "P":
            create_windows_restore_point(); pause(); continue
        sid = restorable_indices.get(raw)
        if not sid:
            warn("That history item has no supported snapshot to restore."); pause(); continue
        restore_snapshot(sid); pause()


def restore_snapshot(snapshot_id: str) -> None:
    snap = STATE.get("snapshots", {}).get(snapshot_id)
    if not snap:
        error("Snapshot not found."); return
    kind = snap.get("kind"); data = snap.get("data", {})
    if kind in ("visual","gamedvr","nagle","fullscreen"):
        ok, fail = restore_registry_snapshot(data.get("registry", {}))
        success(f"Registry snapshot restored ({ok} value(s)).") if fail == 0 else warn(f"Restored {ok}; failed {fail}.")
    elif kind == "privacy":
        ok, fail = restore_registry_snapshot(data.get("registry", {}))
        for svc, before in data.get("services", {}).items():
            mode = before.get("StartMode")
            if mode and mode not in ("Unknown","Missing"): svc_set_start(svc, mode)
            if before.get("State") == "Running": svc_start(svc)
            elif before.get("State") == "Stopped": svc_stop(svc)
        success(f"Privacy snapshot restored ({ok} registry value(s)).") if fail == 0 else warn("Privacy restore completed with registry warnings.")
    elif kind == "power":
        guid = data.get("before",{}).get("guid")
        success("Power plan restored.") if guid and set_power_plan(guid) else error("Could not restore power plan.")
    elif kind == "dns":
        idx = int(data.get("interface_index",0)); servers = data.get("dns_before",[])
        ok = set_adapter_dns(idx, servers) if servers else reset_adapter_dns(idx)
        if ok: flush_dns(); success("Previous DNS configuration restored.")
        else: error("Could not restore previous DNS configuration.")
    elif kind == "gaming":
        restore_gaming_session(); return
    else:
        warn(f"Restore handler for snapshot type '{kind}' is not implemented."); return
    add_history("Restore Snapshot", "success", snapshot_id)
    if not CONFIG["ui"].get("dry_run"): delete_snapshot(snapshot_id)


def create_windows_restore_point() -> None:
    warn("Windows may refuse a new restore point if System Protection is disabled or one was created too recently.")
    if not Confirm.ask("  Request a Windows restore point?", default=False): return
    desc = f"Voltune {datetime.now():%Y-%m-%d %H:%M}"
    r = run_ps(f"Checkpoint-Computer -Description '{desc}' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop", timeout=120, mutating=True)
    success("Windows restore point requested successfully.") if (r.ok or r.skipped) else warn("Windows did not create the restore point. Check System Protection and the log.")
    add_history("Restore Point", "success" if (r.ok or r.skipped) else "warning", desc)


# =============================================================================
# 17. EXPERIMENTAL TWEAKS
# =============================================================================


def require_advanced_mode() -> bool:
    if CONFIG["ui"].get("safe_mode", True):
        warn("Safe Mode is ON. Press [M] on the main menu to enable Advanced Mode first.")
        pause(); return False
    return True


def experimental_tweaks() -> None:
    if not require_advanced_mode(): return
    while True:
        console.clear(); header("EXPERIMENTAL TWEAKS", "Advanced only. These are not part of the recommended optimization bundle.")
        warn("Benchmark before/after. 'Feels faster' is not telemetry.")
        t = Table(box=box.SIMPLE, show_header=False, padding=(0,2))
        t.add_column(width=5,style="bold red"); t.add_column(width=28,style="bold white"); t.add_column(width=55,style="dim")
        t.add_row("[1]","Nagle / TCP ACK override","Apply TcpAckFrequency=1 + TCPNoDelay=1 to the ACTIVE IPv4 adapter only.")
        t.add_row("[2]","Restore Nagle overrides","Remove the overrides from the active adapter.")
        t.add_row("[3]","Fullscreen optimization flags","Legacy GameConfigStore flags. Treat as per-system experiment.")
        t.add_row("[4]","Restore fullscreen flags","Restore saved registry state when available via History.")
        t.add_row("[5]","BCD timer overrides","View/remove useplatformclock + disabledynamictick overrides. Setting them is intentionally not automated.")
        t.add_row("[0]","Back","")
        console.print(t)
        c = Prompt.ask("  [bold red]Choose[/]", choices=["0","1","2","3","4","5"], show_choices=False)
        if c == "0": return
        if c in ("1","2"): nagle_override(c=="1")
        elif c == "3": fullscreen_override()
        elif c == "4": info("Use Restore & History to restore the saved fullscreen snapshot.")
        elif c == "5": bcd_timer_overrides()
        pause()


def active_tcpip_registry_path() -> Optional[str]:
    adapter = get_active_adapter()
    if not adapter: return None
    idx = int(adapter["InterfaceIndex"])
    # Map InterfaceIndex to NetCfgInstanceId GUID.
    data = ps_json(f"Get-CimInstance Win32_NetworkAdapter -Filter \"InterfaceIndex={idx}\" | Select-Object -First 1 GUID")
    guid = data.get("GUID") if isinstance(data,dict) else None
    if not guid: return None
    return rf"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{guid}"


def nagle_override(enable: bool) -> None:
    path = active_tcpip_registry_path()
    if not path: error("Could not map the active adapter to its TCP/IP registry interface."); return
    items = [("HKLM",path,"TcpAckFrequency"),("HKLM",path,"TCPNoDelay")]
    sid = create_snapshot("nagle", {"registry":capture_registry_values(items),"path":path})
    if enable:
        ok = reg_set(winreg.HKEY_LOCAL_MACHINE,path,"TcpAckFrequency",winreg.REG_DWORD,1) and reg_set(winreg.HKEY_LOCAL_MACHINE,path,"TCPNoDelay",winreg.REG_DWORD,1)
        success("Nagle-related overrides applied to the active adapter only. Reboot may be required.") if ok else error("Could not apply overrides.")
        add_history("Nagle Override", "success" if ok else "failed", path, sid)
    else:
        ok = reg_delete(winreg.HKEY_LOCAL_MACHINE,path,"TcpAckFrequency") and reg_delete(winreg.HKEY_LOCAL_MACHINE,path,"TCPNoDelay")
        success("Nagle-related overrides removed from the active adapter.") if ok else error("Could not remove overrides.")
        add_history("Nagle Override Remove", "success" if ok else "failed", path, sid)


def fullscreen_override() -> None:
    items = [("HKCU",r"System\GameConfigStore","GameDVR_FSEBehaviorMode"),("HKCU",r"System\GameConfigStore","GameDVR_HonorUserFSEBehaviorMode")]
    sid = create_snapshot("fullscreen", {"registry":capture_registry_values(items)})
    ok = reg_set(winreg.HKEY_CURRENT_USER,items[0][1],items[0][2],winreg.REG_DWORD,2) and reg_set(winreg.HKEY_CURRENT_USER,items[1][1],items[1][2],winreg.REG_DWORD,0)
    success("Legacy fullscreen flags applied. Reboot/sign-out may be needed.") if ok else error("Could not apply fullscreen flags.")
    add_history("Fullscreen Flags", "success" if ok else "failed", snapshot_id=sid)


def bcd_timer_overrides() -> None:
    r = run(["bcdedit","/enum","{current}"])
    relevant = []
    for line in r.stdout.splitlines():
        if "useplatformclock" in line.lower() or "disabledynamictick" in line.lower(): relevant.append(line.strip())
    console.print("\n  Current overrides:")
    console.print("\n".join(f"  {x}" for x in relevant) if relevant else "  [dim]No useplatformclock/disabledynamictick override found.[/]")
    console.print("\n  This toolkit does NOT set these as a gaming optimization. It can only remove explicit overrides to return Windows to default behavior.")
    if relevant and Confirm.ask("  Remove both explicit timer overrides?", default=False):
        a = run(["bcdedit","/deletevalue","useplatformclock"],mutating=True)
        b = run(["bcdedit","/deletevalue","disabledynamictick"],mutating=True)
        ok = (a.ok or a.skipped or "not found" in a.stderr.lower()) and (b.ok or b.skipped or "not found" in b.stderr.lower())
        success("BCD timer overrides removed. Restart required.") if ok else warn("One or more BCD delete operations returned an error.")
        add_history("BCD Timer Restore", "success" if ok else "warning")


# =============================================================================
# 18. MEMORY TOOLS
# =============================================================================


def memory_tools() -> None:
    if not require_advanced_mode(): return
    while True:
        console.clear(); header("ADVANCED MEMORY TOOLS", "Diagnostics and working-set trimming. More free RAM does not automatically mean more performance.")
        mem = psutil.virtual_memory()
        console.print(f"  RAM: [bold]{fmt_bytes(mem.available)} available[/] / {fmt_bytes(mem.total)} total · {mem.percent:.0f}% used\n")
        console.print("  [1] Show top RAM processes\n  [2] Trim selected process working set\n  [3] Trim non-critical user process working sets\n  [0] Back\n")
        c = Prompt.ask("  [bold red]Choose[/]", choices=["0","1","2","3"], show_choices=False)
        if c == "0": return
        if c == "1": top_memory_processes(); pause()
        elif c == "2": trim_selected_process(); pause()
        elif c == "3": trim_user_working_sets(); pause()


def top_memory_processes(limit: int = 20) -> List[Tuple[int,str,int]]:
    rows=[]
    for p in psutil.process_iter(["pid","name","memory_info"]):
        try: rows.append((p.info["pid"],p.info.get("name") or "?",p.info["memory_info"].rss))
        except Exception: pass
    rows.sort(key=lambda x:x[2], reverse=True)
    t=Table(box=box.ROUNDED,header_style="bold red"); t.add_column("PID",justify="right"); t.add_column("Process",width=35); t.add_column("Working Set",justify="right")
    for pid,name,rss in rows[:limit]: t.add_row(str(pid),name,fmt_bytes(rss))
    console.print(t)
    return rows[:limit]


def trim_process_working_set(pid: int) -> bool:
    PROCESS_SET_QUOTA = 0x0100
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_bool, ctypes.c_uint32]
    kernel32.OpenProcess.restype = ctypes.c_void_p
    kernel32.SetProcessWorkingSetSize.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_size_t]
    kernel32.SetProcessWorkingSetSize.restype = ctypes.c_bool
    kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
    kernel32.CloseHandle.restype = ctypes.c_bool
    if CONFIG["ui"].get("dry_run"): return True
    handle = kernel32.OpenProcess(PROCESS_SET_QUOTA | PROCESS_QUERY_LIMITED_INFORMATION, False, int(pid))
    if not handle: return False
    try:
        minus_one = ctypes.c_size_t(-1).value
        return bool(kernel32.SetProcessWorkingSetSize(handle, minus_one, minus_one))
    finally:
        kernel32.CloseHandle(handle)


def trim_selected_process() -> None:
    rows = top_memory_processes(20)
    raw = Prompt.ask("  PID to trim", default="0")
    try: pid=int(raw)
    except ValueError: return
    if pid in (0,4,os.getpid()): warn("That PID is protected from this action."); return
    try: name=psutil.Process(pid).name()
    except Exception: name=str(pid)
    if not Confirm.ask(f"  Trim working set for {name} ({pid})?",default=False): return
    before=psutil.virtual_memory().available; ok=trim_process_working_set(pid); time.sleep(.3); after=psutil.virtual_memory().available
    if ok: success(f"Working set trim requested. Available RAM changed by {fmt_bytes(max(0,after-before))}.")
    else: error("Windows rejected the working-set trim.")


def trim_user_working_sets() -> None:
    protected = {"system","registry","memory compression","secure system","csrss.exe","wininit.exe","winlogon.exe","services.exe","lsass.exe","dwm.exe","explorer.exe"}
    if not Confirm.ask("  Trim non-critical user process working sets? This can increase page faults afterward.",default=False): return
    trimmed=0
    for p in psutil.process_iter(["pid","name","username"]):
        try:
            name=(p.info.get("name") or "").lower()
            if p.pid in (0,4,os.getpid()) or name in protected: continue
            username=(p.info.get("username") or "").lower()
            if "system" in username or "service" in username: continue
            if trim_process_working_set(p.pid): trimmed+=1
        except Exception: pass
    success(f"Trim request succeeded for {trimmed} user process(es).")
    add_history("Working Set Trim", "success", f"{trimmed} processes")


# =============================================================================
# 19. PROCESS INSPECTOR
# =============================================================================


def process_inspector() -> None:
    while True:
        console.clear()
        header("PROCESS INSPECTOR", "See which applications are using CPU, RAM and disk before deciding whether anything should be closed")

        # First cpu_percent call primes psutil's per-process counters.
        procs = []
        for p in psutil.process_iter(["pid", "name", "username", "memory_info"]):
            try:
                p.cpu_percent(None)
                io = p.io_counters()
                procs.append({
                    "proc": p,
                    "pid": p.pid,
                    "name": p.info.get("name") or "?",
                    "user": p.info.get("username") or "",
                    "rss": p.info["memory_info"].rss if p.info.get("memory_info") else 0,
                    "io0": (io.read_bytes + io.write_bytes) if io else 0,
                })
            except Exception:
                pass
        time.sleep(0.8)
        rows = []
        for item in procs:
            p = item["proc"]
            try:
                cpu = p.cpu_percent(None) / max(1, psutil.cpu_count(logical=True) or 1)
                io = p.io_counters()
                io_now = (io.read_bytes + io.write_bytes) if io else item["io0"]
                io_rate = max(0, io_now - item["io0"]) / 0.8
                rows.append({**item, "cpu": cpu, "io_rate": io_rate})
            except Exception:
                pass

        t = Table(box=box.ROUNDED, header_style="bold red")
        t.add_column("PID", justify="right", width=8)
        t.add_column("Process", width=30)
        t.add_column("CPU", justify="right", width=10)
        t.add_column("RAM", justify="right", width=13)
        t.add_column("Disk I/O", justify="right", width=14)
        ranked = sorted(rows, key=lambda x: (x["cpu"], x["rss"], x["io_rate"]), reverse=True)[:25]
        for r in ranked:
            t.add_row(str(r["pid"]), r["name"], f"{r['cpu']:.1f}%", fmt_bytes(r["rss"]), f"{fmt_bytes(int(r['io_rate']))}/s")
        console.print(t)
        console.print("\n  [R] Refresh · [K] End a process (Advanced Mode only) · [0] Back")
        c = Prompt.ask("  [bold red]Choose[/]", default="0").upper()
        if c == "0": return
        if c == "R": continue
        if c == "K":
            if CONFIG["ui"].get("safe_mode", True):
                warn("Ending processes is locked in Safe Mode. Toggle Advanced Mode from the main menu first.")
                pause(); continue
            raw = Prompt.ask("  PID to end", default="0")
            try: pid = int(raw)
            except ValueError: continue
            if pid in (0, 4, os.getpid()):
                warn("That PID is protected from this action."); pause(); continue
            try:
                p = psutil.Process(pid); name = p.name()
                if not Confirm.ask(f"  End {name} (PID {pid})? Unsaved work in that app can be lost.", default=False):
                    continue
                if CONFIG["ui"].get("dry_run"):
                    success(f"Dry run: would terminate {name} ({pid}).")
                else:
                    p.terminate()
                    try: p.wait(5)
                    except psutil.TimeoutExpired: p.kill()
                    success(f"Ended {name} ({pid}).")
                add_history("Process End", "success", f"{name} ({pid})")
            except (psutil.NoSuchProcess, psutil.AccessDenied) as exc:
                warn(f"Could not end that process: {exc}")
            pause()



# =============================================================================
# STORAGE INTELLIGENCE / VNEXT
# =============================================================================


def _storage_cfg() -> Dict[str, Any]:
    return CONFIG.setdefault("storage", default_storage_config())


def _storage_safety() -> FilesystemSafety:
    cfg = _storage_cfg()
    return FilesystemSafety(whitelist=expand_paths(cfg.get("protected_paths", [])))


def _show_disk_entries(entries: Sequence[Any], title: str) -> None:
    t = Table(box=box.ROUNDED, header_style="bold red")
    t.add_column("#", width=4)
    t.add_column("Type", width=7)
    t.add_column("Size", justify="right", width=13)
    t.add_column("Name / path", overflow="fold")
    for i, item in enumerate(entries, 1):
        t.add_row(str(i), getattr(item, "kind", "file"), fmt_bytes(int(item.size_bytes)), str(getattr(item, "path", getattr(item, "name", ""))))
    console.print(Panel(t, title=title, border_style="red"))


def _delete_storage_target(path: str, *, label: str) -> bool:
    if CONFIG["ui"].get("safe_mode", True):
        warn("Deletion from Disk Analyzer is locked in Safe Mode. Switch to Advanced Mode first.")
        return False
    safety = _storage_safety()
    decision = safety.evaluate(path, risk=RiskLevel.CAUTION)
    if not decision.allowed:
        warn(decision.reason)
        return False
    warn(f"Selected for deletion: {decision.path}")
    if not Confirm.ask(f"  Permanently delete this {label}?", default=False):
        return False
    result = safety.delete(decision.path, dry_run=CONFIG["ui"].get("dry_run", False), risk=RiskLevel.CAUTION)
    if result.dry_run:
        success(f"Dry run: would delete {decision.path} ({fmt_bytes(result.bytes_estimate)}).")
        add_history("Disk Delete", "dry-run", str(decision.path))
        return True
    if result.deleted:
        success(f"Deleted and verified: {decision.path} ({fmt_bytes(result.bytes_estimate)}).")
        add_history("Disk Delete", "success", str(decision.path))
        return True
    warn(result.reason)
    add_history("Disk Delete", "warning", f"{decision.path}: {result.reason}")
    return False


def disk_analyzer() -> None:
    current = Path.home().absolute()
    while True:
        console.clear(); header("DISK ANALYZER", "Interactive storage explorer. Read-only unless you explicitly delete an item in Advanced Mode.")
        console.print(f"  Current: [bold cyan]{current}[/]\n")
        entries = scan_children(current, limit=40)
        if entries:
            _show_disk_entries(entries, "Largest children")
        else:
            info("No readable entries found in this folder.")
        console.print("\n  Enter a row number to open a folder · [bold white]L[/] large files · [bold white]U[/] up · [bold white]X[/] delete item · [bold white]0[/] Back")
        raw = Prompt.ask("  [bold red]Choose[/]", default="0").strip().upper()
        if raw == "0": return
        if raw == "U":
            if current.parent != current: current = current.parent
            continue
        if raw == "L":
            threshold = int(_storage_cfg().get("large_file_threshold_mb", 500))
            with Progress(SpinnerColumn(style="red"), TextColumn("{task.description}"), console=console) as prog:
                task = prog.add_task(f"Scanning files >= {threshold} MB...", total=None)
                large = find_large_files(current, threshold_bytes=threshold * 1024 * 1024, limit=50)
                prog.update(task, description=f"[green]✓[/] Found {len(large)} large file(s)")
            console.clear(); header("LARGE FILES", f"Files >= {threshold} MB under {current}")
            _show_disk_entries(large, "Large files") if large else info("No matching files found.")
            if large and not CONFIG["ui"].get("safe_mode", True):
                raw_idx = Prompt.ask("  Delete a row number, or press Enter to return", default="").strip()
                if raw_idx.isdigit() and 1 <= int(raw_idx) <= len(large):
                    _delete_storage_target(large[int(raw_idx)-1].path, label="file")
                    pause()
            else:
                pause()
            continue
        if raw == "X":
            idx = Prompt.ask("  Row number to delete", default="").strip()
            if idx.isdigit() and 1 <= int(idx) <= len(entries):
                item = entries[int(idx)-1]
                _delete_storage_target(item.path, label=item.kind)
                pause()
            continue
        if raw.isdigit() and 1 <= int(raw) <= len(entries):
            item = entries[int(raw)-1]
            path = Path(item.path)
            if path.is_dir():
                current = path
            else:
                info("That row is a file. Use X if you intentionally want to delete it in Advanced Mode.")
                pause()


def developer_cleanup() -> None:
    console.clear(); header("DEVELOPER CLEANUP", "Find disposable build/dependency artifacts. Projects active within the recent window are not selected by default.")
    dry_run_notice()
    cfg = _storage_cfg(); safety = _storage_safety()
    roots = expand_paths(cfg.get("dev_scan_roots", []))
    recent_days = int(cfg.get("recent_project_days", 7))
    with Progress(SpinnerColumn(style="red"), TextColumn("{task.description}"), console=console) as prog:
        task = prog.add_task("Scanning developer projects...", total=None)
        artifacts = scan_dev_artifacts(roots, recent_days=recent_days, safety=safety)
        prog.update(task, description=f"[green]✓[/] Found {len(artifacts)} cleanup candidate(s)")
    if not artifacts:
        info("No eligible developer artifacts found in configured scan roots."); pause(); return

    t = Table(box=box.ROUNDED, header_style="bold red")
    t.add_column("#", width=4); t.add_column("Artifact", width=22); t.add_column("Size", width=12, justify="right")
    t.add_column("Age", width=10, justify="right"); t.add_column("Default", width=9); t.add_column("Project", overflow="fold")
    for i, item in enumerate(artifacts, 1):
        t.add_row(str(i), item.kind, fmt_bytes(item.size_bytes), f"{item.age_days:.1f}d", "yes" if item.default_selected else "recent", item.project_root)
    console.print(t)
    console.print(f"\n  [dim]Recent threshold: {recent_days} days. DEFAULT excludes recent projects.[/]")
    raw = Prompt.ask("  Clean rows, DEFAULT, or BACK", default="BACK").strip().upper()
    if raw == "BACK" or not raw: return
    if raw == "DEFAULT":
        selected = [i for i, a in enumerate(artifacts) if a.default_selected]
    else:
        selected = []
        for token in raw.replace(",", " ").split():
            if token.isdigit() and 1 <= int(token) <= len(artifacts): selected.append(int(token)-1)
    selected = sorted(set(selected))
    if not selected:
        warn("No valid artifacts selected."); pause(); return
    if CONFIG["ui"].get("safe_mode", True) and any(artifacts[i].recent for i in selected):
        warn("Recent-project artifacts require Advanced Mode. They were intentionally not removed.")
        selected = [i for i in selected if not artifacts[i].recent]
    if not selected:
        pause(); return
    total = sum(artifacts[i].size_bytes for i in selected)
    if not Confirm.ask(f"  Delete {len(selected)} artifact(s), approximately {fmt_bytes(total)}?", default=False): return

    removed = reclaimed = blocked = 0
    for idx in selected:
        item = artifacts[idx]
        result = safety.delete(item.path, dry_run=CONFIG["ui"].get("dry_run", False), risk=RiskLevel.CAUTION)
        if result.dry_run:
            success(f"Dry run: {item.path} ({fmt_bytes(result.bytes_estimate)})"); removed += 1; reclaimed += result.bytes_estimate
        elif result.deleted:
            success(f"Deleted: {item.path} ({fmt_bytes(result.bytes_estimate)})"); removed += 1; reclaimed += result.bytes_estimate
        else:
            blocked += 1; warn(f"Skipped {item.path}: {result.reason}")
    add_history("Developer Cleanup", "success" if blocked == 0 else "warning", f"{removed} item(s) / {fmt_bytes(reclaimed)} / {blocked} skipped")
    pause()


def installer_cleanup() -> None:
    console.clear(); header("INSTALLER CLEANUP", "Find stale Windows installers and installer-like archives. Nothing is deleted until you select it.")
    dry_run_notice(); cfg = _storage_cfg(); safety = _storage_safety()
    roots = expand_paths(cfg.get("installer_scan_roots", []))
    candidates = find_installers(
        roots,
        min_size_bytes=int(cfg.get("installer_min_size_mb", 20)) * 1024 * 1024,
        min_age_days=int(cfg.get("installer_min_age_days", 14)),
    )
    if not candidates:
        info("No stale installer candidates found."); pause(); return
    t = Table(box=box.ROUNDED, header_style="bold red")
    t.add_column("#", width=4); t.add_column("Size", width=12, justify="right"); t.add_column("Age", width=10, justify="right"); t.add_column("Path", overflow="fold")
    for i, item in enumerate(candidates, 1):
        t.add_row(str(i), fmt_bytes(item.size_bytes), f"{item.age_days:.1f}d", item.path)
    console.print(t)
    raw = Prompt.ask("  Delete rows separated by spaces, or BACK", default="BACK").strip().upper()
    if raw == "BACK": return
    selected = [int(tok)-1 for tok in raw.replace(",", " ").split() if tok.isdigit() and 1 <= int(tok) <= len(candidates)]
    selected = sorted(set(selected))
    if not selected: warn("No valid files selected."); pause(); return
    total = sum(candidates[i].size_bytes for i in selected)
    if not Confirm.ask(f"  Permanently delete {len(selected)} file(s), approximately {fmt_bytes(total)}?", default=False): return
    reclaimed = 0
    for idx in selected:
        item = candidates[idx]
        result = safety.delete(item.path, dry_run=CONFIG["ui"].get("dry_run", False), risk=RiskLevel.CAUTION)
        if result.deleted or result.dry_run:
            reclaimed += result.bytes_estimate; success(("Dry run: " if result.dry_run else "Deleted: ") + item.path)
        else:
            warn(f"Skipped {item.path}: {result.reason}")
    add_history("Installer Cleanup", "success", f"{fmt_bytes(reclaimed)}")
    pause()


def smart_uninstaller() -> None:
    while True:
        console.clear(); header("SMART UNINSTALLER", "Desktop-app inventory plus conservative leftover detection. LOW-confidence fuzzy deletion is intentionally not implemented.")
        apps = list_installed_apps()
        if not apps:
            warn("No desktop uninstall registry entries were returned."); pause(); return
        t = Table(box=box.ROUNDED, header_style="bold red")
        t.add_column("#", width=4); t.add_column("Application", width=34); t.add_column("Version", width=14); t.add_column("Publisher", width=28)
        for i, app in enumerate(apps[:120], 1):
            t.add_row(str(i), app.name[:34], app.version[:14], app.publisher[:28])
        console.print(t)
        raw = Prompt.ask("  Inspect row, or 0 to Back", default="0").strip()
        if raw == "0": return
        if not raw.isdigit() or not (1 <= int(raw) <= min(len(apps),120)): continue
        app = apps[int(raw)-1]
        leftovers = leftover_candidates(app)
        console.clear(); header("UNINSTALL DETAILS", app.name)
        console.print(f"  Publisher : {app.publisher or '—'}\n  Version   : {app.version or '—'}\n  Location  : {app.install_location or '—'}")
        cmd = uninstall_command(app)
        console.print(f"  Uninstall : {'available' if cmd else 'not exposed by registry'}\n")
        lt = Table(box=box.SIMPLE, header_style="bold red")
        lt.add_column("Confidence", width=12); lt.add_column("Candidate leftover", overflow="fold"); lt.add_column("Why", width=44)
        for item in leftovers: lt.add_row(item.confidence, item.path, item.reason)
        console.print(lt) if leftovers else info("No HIGH/MEDIUM leftover candidates detected.")
        console.print("\n  [U] Run registered uninstaller  [0] Back")
        choice = Prompt.ask("  [bold red]Choose[/]", default="0").strip().upper()
        if choice != "U": continue
        if not cmd:
            warn("This app does not expose a usable uninstall command."); pause(); continue
        warn("Voltune will launch the application's registered uninstaller. The vendor UI may ask additional questions.")
        if Confirm.ask(f"  Uninstall {app.name}?", default=False):
            result = run(cmd, timeout=1800, mutating=True)
            if result.ok or result.skipped:
                success("Registered uninstaller completed or was launched successfully.")
                add_history("App Uninstall", "success" if not result.skipped else "dry-run", app.name)
            else:
                warn("The registered uninstaller returned an error. No leftover deletion was attempted.")
                add_history("App Uninstall", "warning", f"{app.name}: {result.stderr[-300:]}")
            pause()


def live_system_monitor() -> None:
    console.clear(); header("LIVE SYSTEM MONITOR", "CPU, RAM, disk, network counters and top memory processes. Ctrl+C returns to the menu.")
    try:
        while True:
            snap = collect_snapshot(process_limit=5)
            console.clear(); header("LIVE SYSTEM MONITOR", "Ctrl+C returns to the menu")
            t = Table(box=box.ROUNDED, show_header=False, padding=(0,2))
            t.add_column(width=18, style="bold red"); t.add_column(width=60)
            t.add_row("CPU", f"{snap.cpu_percent:.1f}%")
            t.add_row("RAM", f"{snap.memory_percent:.1f}% · {fmt_bytes(snap.memory_used)} / {fmt_bytes(snap.memory_total)}")
            t.add_row("Disk", f"{snap.disk_percent:.1f}% · {fmt_bytes(snap.disk_used)} / {fmt_bytes(snap.disk_total)}")
            t.add_row("Network total", f"RX {fmt_bytes(snap.net_bytes_recv)} · TX {fmt_bytes(snap.net_bytes_sent)}")
            if snap.battery_percent is not None:
                t.add_row("Battery", f"{snap.battery_percent:.0f}% · {'Plugged in' if snap.battery_plugged else 'On battery'}")
            console.print(t)
            pt = Table(box=box.SIMPLE, header_style="bold red")
            pt.add_column("PID", justify="right", width=8); pt.add_column("Process", width=34); pt.add_column("RAM %", justify="right", width=10)
            for proc in snap.top_processes: pt.add_row(str(proc['pid']), proc['name'][:34], f"{proc['memory_percent']:.2f}")
            console.print(pt)
            time.sleep(2)
    except KeyboardInterrupt:
        return


def protected_paths_view() -> None:
    while True:
        console.clear(); header("PROTECTED PATHS", "Persistent whitelist used by Voltune's destructive filesystem features.")
        cfg = _storage_cfg(); values = list(cfg.get("protected_paths", []))
        t = Table(box=box.ROUNDED, header_style="bold red")
        t.add_column("#", width=4); t.add_column("Protected path", overflow="fold")
        for i, value in enumerate(values, 1): t.add_row(str(i), value)
        console.print(t)
        console.print("\n  [A] Add path  [R] Remove row  [0] Back")
        raw = Prompt.ask("  [bold red]Choose[/]", default="0").strip().upper()
        if raw == "0": return
        if raw == "A":
            value = Prompt.ask("  Path to protect").strip()
            if value and value not in values:
                values.append(value); cfg["protected_paths"] = values; save_config(); success("Protected path added."); pause()
        elif raw == "R":
            idx = Prompt.ask("  Row number").strip()
            if idx.isdigit() and 1 <= int(idx) <= len(values):
                removed = values.pop(int(idx)-1); cfg["protected_paths"] = values; save_config(); success(f"Removed: {removed}"); pause()


# =============================================================================
# MAIN MENU / MODES
# =============================================================================

MENU: Dict[str, Tuple[str, str, Callable[[], None]]] = {
    "1": ("Gaming Session", "Pause selected background activity for gaming, then restore the saved state when you finish.", start_gaming_session),
    "2": ("Gaming Preflight", "Read-only check of CPU, RAM, background apps, power mode and gateway latency before you play.", gaming_preflight),
    "3": ("Power Plans", "Choose how Windows balances speed, heat and battery; includes verified Ultimate Performance setup.", power_plan_manager),
    "4": ("Performance Settings", "Reduce animations and disable Game DVR recording; supported changes are saved for restore.", performance_settings),
    "5": ("Storage Cleanup", "Shows temp/cache space first, then lets you choose what to delete and reports reclaimed storage.", storage_cleanup),
    "6": ("Startup Manager", "See common apps that start with Windows and turn their startup entries off or back on.", startup_manager),
    "7": ("App Manager", "Detect optional built-in Store apps and remove only the packages you select.", app_manager),
    "8": ("App Updates", "Preview outdated apps with WinGet before deciding whether to install updates.", app_updates),
    "9": ("Component Cleanup", "Run Windows component-store cleanup separately from ordinary cache cleaning.", dism_component_cleanup),
    "10": ("DNS Benchmark & Switch", "Test real DNS lookups, rank providers, apply one, verify it, and restore old DNS when needed.", dns_benchmark_switch),
    "11": ("Network Diagnostics", "Helps identify whether slowness comes from your router, internet connection, DNS or network route.", network_diagnostics),
    "12": ("Latency Monitor", "Continuously measure ping, jitter and packet loss to a target you choose.", latency_monitor),
    "13": ("Network Repair", "Fix common network problems; destructive resets are kept separate and require confirmation.", network_repair),
    "14": ("System Dashboard", "View Windows, CPU, RAM, GPU, disks, network, security and power information in one place.", system_dashboard),
    "15": ("System Health", "Read-only summary of disk, RAM, network, DNS and Defender health without changing Windows.", system_health),
    "16": ("Windows Defender", "Check Microsoft Defender status and run supported signature, scan and threat-history actions.", defender_center),
    "17": ("Process Inspector", "See which apps use CPU, RAM and disk; ending a process is locked behind Advanced Mode.", process_inspector),
    "18": ("Privacy Controls", "Adjust selected Windows privacy settings and save snapshots for supported restoration.", privacy_controls),
    "19": ("Restore & History", "Review previous Voltune changes, recover interrupted Gaming Sessions and restore supported settings.", restore_history),
    "20": ("Experimental Tweaks", "Advanced-only network, fullscreen and BCD overrides; not part of recommended optimization.", experimental_tweaks),
    "21": ("Memory Tools", "Advanced-only working-set tools for troubleshooting memory behavior, not a generic speed boost.", memory_tools),
    "22": ("Disk Analyzer", "Explore folder sizes and large files; deletion is available only through the centralized safety engine.", disk_analyzer),
    "23": ("Developer Cleanup", "Find node_modules, virtualenvs, build outputs and other disposable developer artifacts; recent projects are protected by default.", developer_cleanup),
    "24": ("Installer Cleanup", "Find stale installer packages and installer-like archives in common download locations.", installer_cleanup),
    "25": ("Smart Uninstaller", "Inspect desktop applications, launch their registered uninstaller, and preview conservative leftover candidates.", smart_uninstaller),
    "26": ("Live System Monitor", "Continuously refresh CPU, RAM, disk, network counters and top memory processes.", live_system_monitor),
    "27": ("Protected Paths", "View or edit the persistent whitelist used by destructive filesystem features.", protected_paths_view),
}

MENU_HELP: Dict[str, Tuple[str, str]] = {
    "1": ("Reversible session", "Use before gaming when you want selected background activity paused temporarily. Voltune records service and power state and restores it afterward."),
    "2": ("Read-only", "Use when you only want to check whether the PC looks ready for gaming. It changes nothing."),
    "3": ("System setting", "Use to choose a Windows power scheme. High/Ultimate modes can increase heat and battery use."),
    "4": ("Reversible settings", "Use if Windows animations or Game DVR are unwanted. Voltune snapshots supported registry values first."),
    "5": ("Deletes files", "Use to reclaim temp/cache space. Voltune previews categories before deletion and avoids Prefetch cleaning."),
    "6": ("Reversible startup changes", "Use when too many apps open after sign-in. Registry startup entries managed by Voltune are backed up before disabling."),
    "7": ("Removes apps", "Use to remove optional Appx packages. Removal is more consequential than simply disabling startup."),
    "8": ("Installs updates", "Use to see application updates detected by WinGet. Voltune previews them before installation."),
    "9": ("Windows maintenance", "Use occasionally to let DISM clean superseded component-store content. It is intentionally separate from normal cleanup."),
    "10": ("Network setting", "Use when choosing a DNS resolver. Ranking is based on actual DNS queries, not just ping."),
    "11": ("Read-only", "Use when the internet feels slow or unstable and you want a quick clue whether the issue is local, upstream, DNS, or routing."),
    "12": ("Read-only", "Use for gaming/voice-call troubleshooting. Jitter and packet loss are often more useful than average ping alone."),
    "13": ("Network changes", "Start with Safe Repair. Destructive reset can clear custom TCP/IP or firewall configuration and is intentionally separated."),
    "14": ("Read-only", "Use to collect a hardware, Windows, network and security overview. System data is read through CIM/PowerShell."),
    "15": ("Read-only", "Use for a quick health summary before changing anything. It reports warnings rather than automatically fixing them."),
    "16": ("Security maintenance", "Use to inspect Defender state and run supported maintenance actions. Organization policy or third-party antivirus can restrict this."),
    "17": ("Read-only by default", "Use to find heavy processes before closing anything. Process termination requires Advanced Mode and confirmation."),
    "18": ("Reversible where supported", "Use to reduce selected Windows data-sharing features. Snapshots are kept for supported restores."),
    "19": ("Recovery", "Use to inspect Voltune history, recover an interrupted Gaming Session, or restore supported snapshots."),
    "20": ("Advanced / experimental", "Only use when you understand the specific override. These options are deliberately excluded from the recommended performance path."),
    "21": ("Advanced / troubleshooting", "Use when diagnosing process working-set behavior. Freeing visible RAM does not automatically make Windows faster."),
    "22": ("Read-only by default", "Use to understand what consumes disk space. Deletion is locked in Safe Mode and always passes the filesystem safety engine."),
    "23": ("Selective file deletion", "Use to reclaim space from disposable development artifacts. Projects active within the recent window are never selected by default."),
    "24": ("Selective file deletion", "Use to find old installer packages. Generic ZIP/7z archives are ignored unless their names look installer-related."),
    "25": ("Application removal", "Use for desktop programs registered with Windows. Leftovers are detected conservatively and are not automatically deleted."),
    "26": ("Read-only", "Use when you want a continuously refreshed system view instead of the one-shot dashboard."),
    "27": ("Safety configuration", "Use to protect custom folders from Voltune's filesystem deletion features. Whitelisted paths override cleanup selections."),
}


def feature_help() -> None:
    while True:
        console.clear()
        header("HELP — WHAT DOES EACH TOOL DO?", "Plain-language explanations before you change anything")
        t = Table(box=box.ROUNDED, header_style="bold red", padding=(0, 1))
        t.add_column("#", width=4, style="bold red")
        t.add_column("Feature", width=24, style="bold white")
        t.add_column("Safety", width=24)
        t.add_column("When to use it", width=72, style="dim white")
        for key in [str(i) for i in range(1, 28)]:
            name = MENU[key][0]
            safety, detail = MENU_HELP[key]
            t.add_row(key, name, safety, detail)
        console.print(t)
        console.print("\n  [dim]Safe Mode blocks the most experimental tools. Dry Run simulates supported mutations without executing them.[/]")
        pause()
        return



def draw_main_menu() -> None:
    safe = CONFIG["ui"].get("safe_mode", True)
    dry = CONFIG["ui"].get("dry_run", False)
    mode = "SAFE" if safe else "ADVANCED"
    panel_text = (
        "[bold white]VOLTUNE[/]  [dim]// Windows utility[/]\n"
        f"[dim]Session {SESSION_ID} · Mode:[/] [bold {'green' if safe else 'yellow'}]{mode}[/]"
        f" [dim]· Dry Run:[/] [bold {'yellow' if dry else 'green'}]{'ON' if dry else 'OFF'}[/]"
    )
    console.print(Panel(Align.center(panel_text), border_style="bold red", padding=(0,4)))

    sections = [
        ("PERFORMANCE", ["1","2","3","4"]),
        ("MAINTENANCE", ["5","6","7","8","9","22","23","24","25"]),
        ("NETWORK", ["10","11","12","13"]),
        ("SYSTEM", ["14","15","16","17","26"]),
        ("PRIVACY & RECOVERY", ["18","19","27"]),
        ("ADVANCED", ["20","21"]),
    ]
    t = Table(box=box.SIMPLE, show_header=False, padding=(0,1))
    t.add_column(width=6, style="bold red")
    t.add_column(width=28, style="bold white")
    t.add_column(width=66, style="dim white")
    for section, keys in sections:
        t.add_row("", f"[dim]── {section} ──[/]", "")
        for key in keys:
            name, desc, _ = MENU[key]
            if key in ("20","21") and safe:
                desc = "[yellow]Locked in Safe Mode.[/] " + desc
            t.add_row(f"[{key}]", name, desc)
    t.add_row("", "", "")
    t.add_row("[H]", "Help / What is this?", "plain-language explanation, safety level and when each feature is useful")
    t.add_row("[M]", "Toggle Safe/Advanced", "Safe Mode is recommended; Advanced unlocks experimental and memory tools")
    t.add_row("[D]", "Toggle Dry Run", "simulate supported state-changing commands without executing them")
    t.add_row("[0]", "Exit", "close Voltune")
    console.print(t)
    console.print("  [dim]Tip: every feature returns to a freshly cleared main menu. Results stay visible only until you press Enter.[/]")


def recover_pending_session_prompt() -> None:
    session = STATE.get("gaming_session")
    if session and session.get("active"):
        console.clear(); header("RECOVERY AVAILABLE", "The previous Gaming Session did not reach its normal restore step")
        warn(f"Saved session started at {session.get('started_at','unknown time')}.")
        if Confirm.ask("  Restore its saved service states and power plan now?", default=True):
            restore_gaming_session(); pause()


def main_menu() -> None:
    recover_pending_session_prompt()
    while True:
        # Centralized CLS behavior: EVERY completed/cancelled feature returns here,
        # then the screen is cleared before the menu is redrawn.
        console.clear()
        draw_main_menu()
        raw = Prompt.ask("\n  [bold red]Choose[/]", default="0").strip().upper()
        if raw == "0":
            console.clear(); console.print("\n  [dim]Voltune closed.[/]\n"); return
        if raw == "H": feature_help(); continue
        if raw == "M":
            CONFIG["ui"]["safe_mode"] = not CONFIG["ui"].get("safe_mode", True); save_config(); continue
        if raw == "D":
            CONFIG["ui"]["dry_run"] = not CONFIG["ui"].get("dry_run", False); save_config(); continue
        action = MENU.get(raw)
        if not action: continue
        try:
            action[2]()
        except KeyboardInterrupt:
            console.print("\n  [yellow]Action interrupted.[/]"); log(f"KeyboardInterrupt in {action[0]}","WARNING"); pause()
        except Exception as exc:
            log(f"Unhandled error in {action[0]}: {exc}\n{traceback.format_exc()}","ERROR")
            console.print("\n[bold red]The feature hit an unexpected error.[/]")
            console.print(f"[dim]{exc}[/]")
            console.print(f"[dim]Details were written to {LOG_PATH.name}.[/]")
            pause()


# =============================================================================
# ENTRY POINT
# =============================================================================

def main() -> None:
    if os.name != "nt":
        print("Voltune is Windows-only. Run it on Windows 11 / PowerShell 5.1+.")
        raise SystemExit(1)
    require_admin()
    log("Voltune started")
    try:
        main_menu()
    finally:
        log("Voltune ended")


if __name__ == "__main__":
    main()
