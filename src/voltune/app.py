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


def add_history(action: str, status: str, detail: str = "") -> None:
    STATE.setdefault("history", []).append({
        "ts": datetime.now().isoformat(timespec="seconds"),
        "session": SESSION_ID,
        "action": action,
        "status": status,
        "detail": detail,
    })
    save_state()


def run(cmd: Sequence[str], timeout: int = 30, mutate: bool = False) -> CmdResult:
    display = subprocess.list2cmdline([str(x) for x in cmd])
    if mutate and CONFIG["ui"].get("dry_run", False):
        log(f"DRY-RUN command skipped: {display}")
        return CmdResult(display, 0, stdout="dry-run", skipped=True)
    try:
        cp = subprocess.run(
            [str(x) for x in cmd], capture_output=True, text=True,
            timeout=timeout, errors="replace"
        )
        result = CmdResult(display, cp.returncode, cp.stdout or "", cp.stderr or "")
        log(f"CMD rc={cp.returncode}: {display}")
        if cp.returncode != 0:
            log(f"stderr: {result.stderr.strip()}", "WARNING")
        return result
    except subprocess.TimeoutExpired as exc:
        log(f"TIMEOUT: {display}", "ERROR")
        return CmdResult(display, 124, exc.stdout or "", exc.stderr or "", timed_out=True)
    except Exception as exc:
        log(f"EXCEPTION running {display}: {exc}", "ERROR")
        return CmdResult(display, 1, stderr=str(exc))


def run_ps(script: str, timeout: int = 30, mutate: bool = False) -> CmdResult:
    return run(["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script], timeout, mutate)


def ps_json(script: str, timeout: int = 30) -> Any:
    r = run_ps(f"$ProgressPreference='SilentlyContinue'; {script} | ConvertTo-Json -Depth 8 -Compress", timeout)
    if not r.ok or not r.stdout.strip():
        return None
    try:
        return json.loads(r.stdout.strip())
    except Exception:
        return None


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None or run(["where.exe", name], 5).ok


def header(title: str, subtitle: Optional[str] = None) -> None:
    txt = f"[bold white]{title}[/]"
    if subtitle:
        txt += f"\n[dim]{subtitle}[/]"
    console.print()
    console.print(Panel(Align.center(txt), border_style="bold red", padding=(0, 4)))
    console.print()


def info(msg: str) -> None:
    console.print(f"  [bold cyan]→[/] {msg}")


def warn(msg: str) -> None:
    console.print(f"  [bold yellow]⚠[/] {msg}")


def success(msg: str) -> None:
    console.print(f"  [bold green]✓[/] {msg}")


def failure(msg: str) -> None:
    console.print(f"  [bold red]✗[/] {msg}")


def pause() -> None:
    if CONFIG["ui"].get("pause_after_action", True):
        console.input("\n  [dim]Press Enter to return to the main menu...[/]")


def is_admin() -> bool:
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def require_admin() -> None:
    if is_admin():
        return
    console.print("[yellow]Voltune needs Administrator privileges for system changes. Requesting UAC...[/]")
    args = subprocess.list2cmdline(sys.argv)
    if getattr(sys, "frozen", False):
        exe = sys.executable
        params = " ".join(f'"{a}"' for a in sys.argv[1:])
    else:
        exe = sys.executable
        params = args
    rc = ctypes.windll.shell32.ShellExecuteW(None, "runas", exe, params, str(APP_DIR), 1)
    if rc <= 32:
        console.print("[red]UAC elevation was cancelled or failed.[/]")
        raise SystemExit(1)
    raise SystemExit(0)


def bytes_human(n: int) -> str:
    value = float(max(0, n))
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if value < 1024 or unit == "TB":
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024
    return f"{value:.1f} TB"


def percentile(values: List[float], pct: float) -> float:
    if not values:
        return float("nan")
    vals = sorted(values)
    if len(vals) == 1:
        return vals[0]
    k = (len(vals) - 1) * pct
    f = int(k)
    c = min(f + 1, len(vals) - 1)
    return vals[f] + (vals[c] - vals[f]) * (k - f)


# =============================================================================
# REGISTRY / SERVICE / PROCESS HELPERS
# =============================================================================

HIVES = {"HKCU": winreg.HKEY_CURRENT_USER, "HKLM": winreg.HKEY_LOCAL_MACHINE}


def reg_read(hive_name: str, path: str, name: str) -> Dict[str, Any]:
    try:
        key = winreg.OpenKey(HIVES[hive_name], path, 0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY)
        value, kind = winreg.QueryValueEx(key, name)
        winreg.CloseKey(key)
        return {"exists": True, "value": value, "kind": kind}
    except Exception:
        return {"exists": False, "value": None, "kind": None}


def reg_set(hive_name: str, path: str, name: str, kind: int, value: Any) -> bool:
    if CONFIG["ui"].get("dry_run", False):
        log(f"DRY-RUN registry set {hive_name}\\{path}::{name}={value}")
        return True
    try:
        key = winreg.CreateKeyEx(HIVES[hive_name], path, 0, winreg.KEY_SET_VALUE | winreg.KEY_WOW64_64KEY)
        winreg.SetValueEx(key, name, 0, kind, value)
        winreg.CloseKey(key)
        after = reg_read(hive_name, path, name)
        ok_ = after["exists"] and after["value"] == value
        log(f"Registry set verify={ok_} {hive_name}\\{path}::{name}")
        return ok_
    except Exception as exc:
        log(f"Registry set failed {hive_name}\\{path}::{name}: {exc}", "ERROR")
        return False


def reg_delete(hive_name: str, path: str, name: str) -> bool:
    if CONFIG["ui"].get("dry_run", False):
        log(f"DRY-RUN registry delete {hive_name}\\{path}::{name}")
        return True
    try:
        key = winreg.OpenKey(HIVES[hive_name], path, 0, winreg.KEY_SET_VALUE | winreg.KEY_WOW64_64KEY)
        winreg.DeleteValue(key, name)
        winreg.CloseKey(key)
    except FileNotFoundError:
        return True
    except Exception as exc:
        log(f"Registry delete failed {hive_name}\\{path}::{name}: {exc}", "ERROR")
        return False
    return not reg_read(hive_name, path, name)["exists"]


def snapshot_registry(label: str, items: List[Tuple[str, str, str]]) -> str:
    snapshot_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    payload = {
        "type": "registry",
        "label": label,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "items": [
            {"hive": h, "path": p, "name": n, **reg_read(h, p, n)} for h, p, n in items
        ],
    }
    STATE["snapshots"][snapshot_id] = payload
    save_state()
    return snapshot_id


def restore_registry_snapshot(snapshot: Dict[str, Any]) -> Tuple[int, int]:
    good = bad = 0
    for item in snapshot.get("items", []):
        if item.get("exists"):
            ok_ = reg_set(item["hive"], item["path"], item["name"], item["kind"], item["value"])
        else:
            ok_ = reg_delete(item["hive"], item["path"], item["name"])
        good += int(ok_); bad += int(not ok_)
    return good, bad


def service_info(name: str) -> Dict[str, Any]:
    script = (
        f"$s=Get-CimInstance Win32_Service -Filter \"Name='{name.replace(chr(39), chr(39)*2)}'\" -ErrorAction SilentlyContinue; "
        "if($s){[pscustomobject]@{Name=$s.Name;State=$s.State;StartMode=$s.StartMode}}"
    )
    obj = ps_json(script)
    return obj if isinstance(obj, dict) else {"Name": name, "State": "Missing", "StartMode": "Unknown"}


def service_set_start(name: str, mode: str) -> bool:
    sc_mode = {"Auto": "auto", "Automatic": "auto", "Manual": "demand", "Disabled": "disabled"}.get(mode, mode.lower())
    r = run(["sc.exe", "config", name, "start=", sc_mode], 20, mutate=True)
    if not r.ok:
        return False
    if CONFIG["ui"].get("dry_run", False):
        return True
    now = service_info(name).get("StartMode", "").lower()
    expected = "auto" if sc_mode == "auto" else "manual" if sc_mode == "demand" else sc_mode
    return expected in now.lower()


def service_stop(name: str) -> bool:
    before = service_info(name)
    if before.get("State") == "Missing":
        return False
    if str(before.get("State", "")).lower() == "stopped":
        return True
    r = run(["sc.exe", "stop", name], 20, mutate=True)
    if CONFIG["ui"].get("dry_run", False):
        return r.ok
    for _ in range(15):
        if str(service_info(name).get("State", "")).lower() == "stopped":
            return True
        time.sleep(0.25)
    return False


def service_start(name: str) -> bool:
    before = service_info(name)
    if before.get("State") == "Missing":
        return False
    if str(before.get("State", "")).lower() == "running":
        return True
    r = run(["sc.exe", "start", name], 20, mutate=True)
    if CONFIG["ui"].get("dry_run", False):
        return r.ok
    for _ in range(20):
        if str(service_info(name).get("State", "")).lower() == "running":
            return True
        time.sleep(0.25)
    return False


def kill_processes(names: Iterable[str]) -> Dict[str, int]:
    wanted = {x.lower() for x in names}
    result = {x: 0 for x in wanted}
    for proc in psutil.process_iter(["pid", "name"]):
        try:
            name = (proc.info.get("name") or "").lower()
            if name in wanted:
                if CONFIG["ui"].get("dry_run", False):
                    result[name] += 1
                else:
                    proc.terminate()
                    try:
                        proc.wait(2)
                    except psutil.TimeoutExpired:
                        proc.kill()
                    result[name] += 1
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    log(f"Process close result: {result}")
    return result


# =============================================================================
# POWER PLAN HELPERS
# =============================================================================

GUID_RE = re.compile(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})", re.I)


def get_power_plans() -> List[Dict[str, Any]]:
    r = run(["powercfg.exe", "/list"], 15)
    result: List[Dict[str, Any]] = []
    if not r.ok:
        return result
    for line in r.stdout.splitlines():
        m = GUID_RE.search(line)
        if not m:
            continue
        guid = m.group(1).lower()
        name_m = re.search(r"\((.+?)\)", line)
        result.append({"guid": guid, "name": name_m.group(1).strip() if name_m else guid, "active": "*" in line})
    return result


def active_power_plan() -> Optional[Dict[str, str]]:
    r = run(["powercfg.exe", "/getactivescheme"], 10)
    if not r.ok:
        return None
    m = GUID_RE.search(r.stdout)
    if not m:
        return None
    nm = re.search(r"\((.+?)\)", r.stdout)
    return {"guid": m.group(1).lower(), "name": nm.group(1).strip() if nm else m.group(1)}


def activate_power_plan(guid: str) -> bool:
    r = run(["powercfg.exe", "/setactive", guid], 15, mutate=True)
    if not r.ok:
        return False
    if CONFIG["ui"].get("dry_run", False):
        return True
    current = active_power_plan()
    return bool(current and current["guid"].lower() == guid.lower())


def find_plan_by_keyword(keyword: str) -> Optional[Dict[str, Any]]:
    return next((p for p in get_power_plans() if keyword.lower() in p["name"].lower()), None)


def ensure_ultimate_plan() -> Tuple[bool, Optional[str], str]:
    """Create Ultimate Performance once and capture the *new GUID* from powercfg.

    This fixes the classic bug where /duplicatescheme succeeds but code keeps
    trying to activate the template GUID or duplicates the scheme repeatedly.
    """
    existing = find_plan_by_keyword("ultimate")
    if existing:
        STATE["ultimate_guid"] = existing["guid"]
        save_state()
        return True, existing["guid"], "Ultimate Performance already exists"
    saved = STATE.get("ultimate_guid")
    if saved and any(p["guid"].lower() == str(saved).lower() for p in get_power_plans()):
        return True, saved, "Previously created Ultimate Performance found"
    r = run(["powercfg.exe", "/duplicatescheme", ULTIMATE_TEMPLATE_GUID], 20, mutate=True)
    if not r.ok:
        return False, None, (r.stderr or r.stdout or "powercfg failed").strip()
    if CONFIG["ui"].get("dry_run", False):
        return True, ULTIMATE_TEMPLATE_GUID, "Dry-run: would duplicate Ultimate Performance"
    guid_m = GUID_RE.search(r.stdout + "\n" + r.stderr)
    guid = guid_m.group(1).lower() if guid_m else None
    plans = get_power_plans()
    if not guid:
        candidate = next((p for p in plans if "ultimate" in p["name"].lower()), None)
        guid = candidate["guid"] if candidate else None
    if not guid or not any(p["guid"] == guid for p in plans):
        return False, None, "powercfg returned success but the new scheme could not be verified"
    STATE["ultimate_guid"] = guid
    save_state()
    add_history("Install Ultimate Performance", "success", guid)
    return True, guid, "Ultimate Performance installed and verified"


# =============================================================================
# NETWORK / ADAPTER HELPERS
# =============================================================================


def active_network_adapter() -> Optional[Dict[str, Any]]:
    script = r'''
$cfg = Get-NetIPConfiguration | Where-Object {
  $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up'
} | Sort-Object -Property @{Expression={$_.NetIPv4Interface.RouteMetric}} | Select-Object -First 1
if($cfg){
 [pscustomobject]@{
   InterfaceAlias=$cfg.InterfaceAlias
   InterfaceIndex=$cfg.InterfaceIndex
   IPv4=($cfg.IPv4Address | Select-Object -First 1 -ExpandProperty IPAddress)
   Gateway=$cfg.IPv4DefaultGateway.NextHop
   DNS=@($cfg.DNSServer.ServerAddresses)
   Dhcp=$cfg.NetIPv4Interface.Dhcp
   Description=$cfg.NetAdapter.InterfaceDescription
 }
}
'''
    obj = ps_json(script)
    return obj if isinstance(obj, dict) else None


def set_dns_servers(index: int, servers: List[str]) -> bool:
    quoted = ",".join(f"'{s}'" for s in servers)
    r = run_ps(
        f"Set-DnsClientServerAddress -InterfaceIndex {index} -ServerAddresses @({quoted}) -ErrorAction Stop",
        20, mutate=True
    )
    if not r.ok:
        return False
    if CONFIG["ui"].get("dry_run", False):
        return True
    time.sleep(0.4)
    a = active_network_adapter()
    actual = {str(x) for x in (a or {}).get("DNS", [])}
    return all(s in actual for s in servers)


def reset_dns_servers(index: int) -> bool:
    r = run_ps(f"Set-DnsClientServerAddress -InterfaceIndex {index} -ResetServerAddresses -ErrorAction Stop", 20, mutate=True)
    return r.ok


def restore_dns_snapshot(snapshot: Dict[str, Any]) -> bool:
    index = int(snapshot["interface_index"])
    mode = snapshot.get("mode", "servers")
    if mode == "dhcp":
        return reset_dns_servers(index)
    return set_dns_servers(index, list(snapshot.get("servers", [])))


# =============================================================================
# [1] GAMING SESSION
# =============================================================================


def gaming_preflight(render_header: bool = True) -> Dict[str, Any]:
    if render_header:
        console.clear(); header("GAMING PREFLIGHT", "Read-only check — nothing is changed")
    power = active_power_plan() or {"name": "Unknown", "guid": ""}
    ram = psutil.virtual_memory()
    cpu = psutil.cpu_percent(interval=0.6)
    adapter = active_network_adapter()
    gm = CONFIG["gaming_mode"]
    running_names = {p.info["name"].lower() for p in psutil.process_iter(["name"]) if p.info.get("name")}
    candidates = [x for group in (gm["kill_browsers_comm"], gm["kill_cloud_sync"], gm["kill_vendor_optional"]) for x in group]
    active_bg = [x for x in candidates if x.lower() in running_names]
    data = {
        "power": power["name"],
        "cpu": cpu,
        "ram_available_gb": ram.available / (1024**3),
        "adapter": adapter.get("InterfaceAlias") if adapter else "No default-route adapter detected",
        "background_count": len(active_bg),
        "background": active_bg,
    }
    if render_header:
        t = Table(box=box.ROUNDED, show_header=False)
        t.add_column(style="bold red", width=20); t.add_column(style="bold white", width=60)
        t.add_row("Power plan", data["power"])
        t.add_row("CPU load", f"{cpu:.1f}%")
        t.add_row("Available RAM", f"{data['ram_available_gb']:.1f} GB")
        t.add_row("Active network", str(data["adapter"]))
        t.add_row("Closable background", f"{len(active_bg)} detected")
        console.print(t)
        if active_bg:
            console.print("\n  [dim]Gaming Session can close:[/] " + ", ".join(active_bg))
        pause()
    return data


def snapshot_gaming_session() -> Dict[str, Any]:
    gm = CONFIG["gaming_mode"]
    services = {name: service_info(name) for name in gm["services_stop"]}
    power = active_power_plan()
    return {
        "active": True,
        "started_at": datetime.now().isoformat(timespec="seconds"),
        "power_before": power,
        "services_before": services,
        "closed_processes": [],
    }


def restore_gaming_session() -> bool:
    session = STATE.get("gaming_session")
    if not session:
        return True
    console.print()
    success_count = fail_count = 0
    for name, before in session.get("services_before", {}).items():
        wanted = str(before.get("State", "")).lower()
        if wanted == "running":
            ok_ = service_start(name)
        elif wanted == "stopped":
            ok_ = service_stop(name)
        else:
            ok_ = True
        success_count += int(ok_); fail_count += int(not ok_)
    power = session.get("power_before")
    if power and power.get("guid"):
        ok_ = activate_power_plan(power["guid"])
        success_count += int(ok_); fail_count += int(not ok_)
    STATE["gaming_session"] = None
    save_state()
    add_history("Gaming Session Restore", "success" if fail_count == 0 else "partial", f"ok={success_count}, failed={fail_count}")
    return fail_count == 0


def gaming_session() -> None:
    console.clear(); header("GAMING SESSION", "Temporary background cleanup with saved restore state")
    if STATE.get("gaming_session"):
        warn("A previous Gaming Session is still recorded.")
        if Confirm.ask("  Restore the previous session before starting a new one?", default=True):
            restore_gaming_session()
        else:
            pause(); return
    gaming_preflight(render_header=False)
    console.print("  [dim]Voltune will save service + power state, then stop only configured optional items.[/]\n")
    if not Confirm.ask("  Start Gaming Session?", default=True):
        return
    STATE["gaming_session"] = snapshot_gaming_session()
    save_state()
    gm = CONFIG["gaming_mode"]
    all_names = gm["kill_browsers_comm"] + gm["kill_cloud_sync"] + gm["kill_vendor_optional"]
    closed = kill_processes(all_names)
    STATE["gaming_session"]["closed_processes"] = [k for k,v in closed.items() if v]
    save_state()
    for svc in gm["services_stop"]:
        if str(STATE["gaming_session"]["services_before"].get(svc, {}).get("State", "")).lower() == "running":
            service_stop(svc)
    if gm.get("set_high_performance", True):
        plan = find_plan_by_keyword("high performance")
        if plan:
            activate_power_plan(plan["guid"])
    add_history("Gaming Session", "started", f"closed={sum(closed.values())}")
    success("Gaming Session active. Your original service and power states are saved.")
    console.print("  [dim]Leave this window open. Press Enter when you are finished gaming.[/]")
    console.input()
    header("RESTORING GAMING SESSION")
    if restore_gaming_session():
        success("Saved service states and power plan restored.")
    else:
        warn("Restore completed with one or more failures. Check the session log and Restore & History.")
    pause()


# =============================================================================
# [2] POWER PLANS
# =============================================================================


def power_plans() -> None:
    while True:
        console.clear(); header("POWER PLANS", "Choose a Windows power profile — changes are verified")
        current = active_power_plan()
        console.print(f"  Current: [bold cyan]{current['name'] if current else 'Unknown'}[/]\n")
        t = Table(box=box.SIMPLE, show_header=False)
        for row in [
            ("[1]", "Balanced", "Recommended default"),
            ("[2]", "High Performance", "More aggressive power use"),
            ("[3]", "Ultimate Performance", "Install once if needed, then activate"),
            ("[4]", "Power Saver", "Lower power use / battery"),
            ("[0]", "Back", ""),
        ]: t.add_row(*row)
        console.print(t)
        ch = Prompt.ask("  Choose", choices=["0","1","2","3","4"], show_choices=False)
        if ch == "0": return
        target: Optional[str] = None
        if ch == "1":
            plan = find_plan_by_keyword("balanced"); target = plan["guid"] if plan else BALANCED_GUID
        elif ch == "2":
            plan = find_plan_by_keyword("high performance"); target = plan["guid"] if plan else None
        elif ch == "4":
            plan = find_plan_by_keyword("power saver"); target = plan["guid"] if plan else None
        elif ch == "3":
            ok_, guid, msg = ensure_ultimate_plan()
            (success if ok_ else failure)(msg)
            target = guid if ok_ else None
        if not target:
            failure("That power plan is not available on this device.")
        elif activate_power_plan(target):
            success(f"Power plan activated: {(active_power_plan() or {}).get('name', target)}")
            add_history("Power Plan", "success", target)
        else:
            failure("Windows did not confirm the requested power-plan change.")
        pause()


# =============================================================================
# [3] PERFORMANCE SETTINGS
# =============================================================================

PERF_REG = {
    "visual": [
        ("HKCU", r"Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects", "VisualFXSetting"),
        ("HKCU", r"Control Panel\Desktop", "MenuShowDelay"),
        ("HKCU", r"Control Panel\Desktop\WindowMetrics", "MinAnimate"),
        ("HKCU", r"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "TaskbarAnimations"),
        ("HKCU", r"Software\Microsoft\Windows\DWM", "EnableAeroPeek"),
    ],
    "gamedvr": [
        ("HKCU", r"System\GameConfigStore", "GameDVR_Enabled"),
        ("HKCU", r"SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR", "AppCaptureEnabled"),
        ("HKLM", r"SOFTWARE\Policies\Microsoft\Windows\GameDVR", "AllowGameDVR"),
    ]
}


def apply_visual_performance() -> bool:
    snapshot_registry("Visual performance", PERF_REG["visual"])
    changes = [
        ("HKCU", PERF_REG["visual"][0][1], "VisualFXSetting", winreg.REG_DWORD, 2),
        ("HKCU", r"Control Panel\Desktop", "MenuShowDelay", winreg.REG_SZ, "0"),
        ("HKCU", r"Control Panel\Desktop\WindowMetrics", "MinAnimate", winreg.REG_SZ, "0"),
        ("HKCU", r"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "TaskbarAnimations", winreg.REG_DWORD, 0),
        ("HKCU", r"Software\Microsoft\Windows\DWM", "EnableAeroPeek", winreg.REG_DWORD, 0),
    ]
    return all(reg_set(*x) for x in changes)


def disable_game_dvr() -> bool:
    snapshot_registry("Game DVR", PERF_REG["gamedvr"])
    changes = [
        ("HKCU", r"System\GameConfigStore", "GameDVR_Enabled", winreg.REG_DWORD, 0),
        ("HKCU", r"SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR", "AppCaptureEnabled", winreg.REG_DWORD, 0),
        ("HKLM", r"SOFTWARE\Policies\Microsoft\Windows\GameDVR", "AllowGameDVR", winreg.REG_DWORD, 0),
    ]
    return all(reg_set(*x) for x in changes)


def apply_recommended_performance() -> bool:
    """Intentionally separate function calls; avoids the old 'Apply ALL' elif bug."""
    results = [apply_visual_performance(), disable_game_dvr()]
    return all(results)


def performance_settings() -> None:
    while True:
        console.clear(); header("PERFORMANCE SETTINGS", "Conservative tweaks only — experimental timer/network overrides live elsewhere")
        t = Table(box=box.SIMPLE, show_header=False)
        for r in [
            ("[1]", "Reduce visual effects", "Snapshot current values, then reduce animation/eye candy"),
            ("[2]", "Disable Game DVR", "Disable Windows game capture background features"),
            ("[3]", "Apply recommended", "Runs BOTH actions above and verifies each"),
            ("[R]", "Restore snapshot", "Open Restore & History"),
            ("[0]", "Back", ""),
        ]: t.add_row(*r)
        console.print(t)
        ch = Prompt.ask("  Choose", default="0").upper()
        if ch == "0": return
        if ch == "R": restore_history(); continue
        ok_ = apply_visual_performance() if ch == "1" else disable_game_dvr() if ch == "2" else apply_recommended_performance() if ch == "3" else None
        if ok_ is not None:
            (success if ok_ else failure)("Settings applied and verified." if ok_ else "One or more settings could not be verified.")
            add_history("Performance Settings", "success" if ok_ else "partial", f"selection={ch}")
            pause()


# =============================================================================
# [4] MEMORY TOOLS
# =============================================================================


def trim_working_sets() -> Tuple[int, int]:
    PROCESS_SET_QUOTA = 0x0100
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_bool, ctypes.c_uint32]
    kernel32.OpenProcess.restype = ctypes.c_void_p
    kernel32.SetProcessWorkingSetSize.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_size_t]
    kernel32.SetProcessWorkingSetSize.restype = ctypes.c_bool
    kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
    kernel32.CloseHandle.restype = ctypes.c_bool
    success_n = fail_n = 0
    protected = {0, 4, os.getpid()}
    for proc in psutil.process_iter(["pid", "name"]):
        pid = proc.info["pid"]
        if pid in protected:
            continue
        h = kernel32.OpenProcess(PROCESS_SET_QUOTA | PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not h:
            fail_n += 1; continue
        try:
            if kernel32.SetProcessWorkingSetSize(h, ctypes.c_size_t(-1), ctypes.c_size_t(-1)):
                success_n += 1
            else:
                fail_n += 1
        finally:
            kernel32.CloseHandle(h)
    return success_n, fail_n


def memory_tools() -> None:
    console.clear(); header("ADVANCED MEMORY TOOLS", "Troubleshooting only — more 'free RAM' does not automatically mean faster Windows")
    if CONFIG["ui"].get("safe_mode", True):
        warn("Memory Tools are locked in Safe Mode. Toggle Advanced Mode from the main menu first."); pause(); return
    before = psutil.virtual_memory()
    console.print(f"  Available now: [bold]{bytes_human(before.available)}[/]\n")
    t = Table(box=box.SIMPLE, show_header=False)
    t.add_row("[1]", "Trim process working sets", "Can cause pages to be faulted back in later")
    t.add_row("[2]", "EmptyStandbyList.exe", "Only if the optional external utility is next to Voltune")
    t.add_row("[0]", "Back", "")
    console.print(t)
    ch = Prompt.ask("  Choose", choices=["0","1","2"], show_choices=False)
    if ch == "0": return
    if not Confirm.ask("  Continue with this advanced memory operation?", default=False): return
    if ch == "1":
        a,b = trim_working_sets(); info(f"Working-set request succeeded for {a} processes; {b} denied/failed.")
    else:
        exe = APP_DIR / "EmptyStandbyList.exe"
        if not exe.exists():
            warn("EmptyStandbyList.exe is not present. This optional tool was not run."); pause(); return
        for arg in ["workingsets", "modifiedpagelist", "standbylist"]:
            r = run([str(exe), arg], 30, mutate=True)
            if not r.ok: warn(f"{arg} returned an error.")
    time.sleep(0.5)
    after = psutil.virtual_memory()
    delta = after.available - before.available
    info(f"Available RAM changed by {bytes_human(abs(delta))} ({'increase' if delta >= 0 else 'decrease'}).")
    console.print("  [dim]This number alone is not a performance score.[/]")
    pause()


# =============================================================================
# [5] STORAGE CLEANUP
# =============================================================================


def dir_stats(path: Path) -> Tuple[int, int]:
    files = size = 0
    if not path.exists(): return files, size
    try:
        for root, dirs, names in os.walk(path):
            for name in names:
                try:
                    p = Path(root) / name
                    size += p.stat().st_size; files += 1
                except Exception: pass
    except Exception: pass
    return files, size


def delete_dir_contents(path: Path) -> Tuple[int, int]:
    deleted = bytes_removed = 0
    if not path.exists(): return deleted, bytes_removed
    for root, dirs, names in os.walk(path, topdown=False):
        for name in names:
            p = Path(root) / name
            try:
                sz = p.stat().st_size
                p.unlink(); deleted += 1; bytes_removed += sz
            except Exception: pass
        for name in dirs:
            try: (Path(root) / name).rmdir()
            except Exception: pass
    return deleted, bytes_removed


def chromium_cache_paths(base: Path) -> List[Path]:
    out: List[Path] = []
    if not base.exists(): return out
    for profile in base.iterdir():
        if profile.is_dir() and (profile.name == "Default" or profile.name.startswith("Profile ")):
            for rel in [Path("Cache"), Path("Code Cache"), Path("GPUCache")]:
                out.append(profile / rel)
    return out


def cleanup_categories() -> Dict[str, List[Path]]:
    env = lambda s: Path(os.path.expandvars(s))
    cats = {
        "User Temp": [env(r"%TEMP%")],
        "Windows Temp": [env(r"%WINDIR%\Temp")],
        "WER Reports": [env(r"%LOCALAPPDATA%\Microsoft\Windows\WER"), env(r"%ProgramData%\Microsoft\Windows\WER")],
        "Chrome Cache": chromium_cache_paths(env(r"%LOCALAPPDATA%\Google\Chrome\User Data")),
        "Edge Cache": chromium_cache_paths(env(r"%LOCALAPPDATA%\Microsoft\Edge\User Data")),
    }
    ff = env(r"%LOCALAPPDATA%\Mozilla\Firefox\Profiles")
    cats["Firefox Cache"] = [p / "cache2" for p in ff.iterdir()] if ff.exists() else []
    return cats


def storage_cleanup() -> None:
    console.clear(); header("STORAGE CLEANUP", "Preview first — Prefetch is intentionally not deleted")
    cats = cleanup_categories()
    stats: Dict[str, Tuple[int,int]] = {}
    t = Table(box=box.ROUNDED, header_style="bold red")
    t.add_column("#", width=4); t.add_column("Category", width=22); t.add_column("Files", justify="right"); t.add_column("Size", justify="right")
    for i,(name,paths) in enumerate(cats.items(),1):
        f=s=0
        for p in paths:
            ff,ss=dir_stats(p); f+=ff; s+=ss
        stats[name]=(f,s); t.add_row(str(i),name,f"{f:,}",bytes_human(s))
    console.print(t)
    console.print("\n  [dim]Enter numbers separated by spaces, ALL, or 0 to go back.[/]")
    raw = Prompt.ask("  Choose", default="0").strip().upper()
    if raw == "0": return
    names=list(cats)
    selected = names if raw == "ALL" else [names[int(x)-1] for x in raw.split() if x.isdigit() and 1<=int(x)<=len(names)]
    if not selected: warn("Nothing selected."); pause(); return
    running = {p.info["name"].lower() for p in psutil.process_iter(["name"]) if p.info.get("name")}
    browser_map={"Chrome Cache":"chrome.exe","Edge Cache":"msedge.exe","Firefox Cache":"firefox.exe"}
    for cat, exe in browser_map.items():
        if cat in selected and exe in running:
            warn(f"{cat}: {exe} is running. Locked files may be skipped.")
    if not Confirm.ask(f"  Delete selected cache/temp data from {len(selected)} categories?", default=False): return
    total_f=total_b=0
    for name in selected:
        for p in cats[name]:
            f,b=delete_dir_contents(p); total_f+=f; total_b+=b
    success(f"Removed {total_f:,} files and reclaimed approximately {bytes_human(total_b)}.")
    add_history("Storage Cleanup","success",f"files={total_f}, bytes={total_b}")
    pause()


def component_cleanup() -> None:
    console.clear(); header("WINDOWS COMPONENT CLEANUP", "Runs DISM StartComponentCleanup separately from normal cache cleaning")
    if not Confirm.ask("  Run DISM component-store cleanup? This can take several minutes.", default=False): return
    r=run(["dism.exe","/online","/cleanup-image","/startcomponentcleanup"],900,mutate=True)
    (success if r.ok else failure)("DISM component cleanup completed." if r.ok else "DISM reported an error.")
    add_history("DISM Cleanup","success" if r.ok else "failed",str(r.returncode)); pause()


# =============================================================================
# [6] STARTUP MANAGER
# =============================================================================


def startup_manager() -> None:
    while True:
        console.clear(); header("STARTUP MANAGER", "Toggle common Run entries; disabled entries are backed up")
        items=list(CONFIG["startup_apps"].items())
        t=Table(box=box.ROUNDED,header_style="bold red")
        t.add_column("#",width=4); t.add_column("App",width=18); t.add_column("State",width=20); t.add_column("Command",width=60)
        for i,(label,(h,p,n)) in enumerate(items,1):
            val=reg_read(h,p,n)
            backup=STATE["startup_backup"].get(label)
            status="[green]Enabled[/]" if val["exists"] else "[yellow]Disabled (restorable)[/]" if backup else "[dim]Disabled[/]"
            cmd=str(val["value"] if val["exists"] else backup.get("value") if backup else "—")
            t.add_row(str(i),label,status,cmd[:58])
        console.print(t)
        console.print("\n  [dim]Number = toggle · TASKS = view startup Scheduled Tasks · 0 = Back[/]")
        raw=Prompt.ask("  Choose",default="0").strip()
        if raw=="0": return
        if raw.upper()=="TASKS":
            obj=ps_json("Get-ScheduledTask | Where-Object {$_.State -ne 'Disabled' -and $_.Triggers.CimClass.CimClassName -contains 'MSFT_TaskLogonTrigger'} | Select-Object TaskName,TaskPath,State")
            console.print_json(data=obj if obj is not None else []); pause(); continue
        if not raw.isdigit() or not (1<=int(raw)<=len(items)): continue
        label,(h,p,n)=items[int(raw)-1]; cur=reg_read(h,p,n)
        if cur["exists"]:
            STATE["startup_backup"][label]={"hive":h,"path":p,"name":n,"value":cur["value"],"kind":cur["kind"]}
            save_state(); ok_=reg_delete(h,p,n)
            (success if ok_ else failure)(f"{label} disabled." if ok_ else f"Could not disable {label}.")
        else:
            b=STATE["startup_backup"].get(label)
            if not b: warn("No Voltune backup exists for this entry.")
            else:
                ok_=reg_set(b["hive"],b["path"],b["name"],b["kind"],b["value"])
                if ok_: del STATE["startup_backup"][label]; save_state(); success(f"{label} restored.")
                else: failure(f"Could not restore {label}.")
        pause()


# =============================================================================
# [7] APP MANAGER / DEBLOAT
# =============================================================================


def appx_matches(pattern: str, all_users: bool=False) -> List[Dict[str,Any]]:
    au=" -AllUsers" if all_users else ""
    return_data=ps_json(f"Get-AppxPackage{au} '{pattern}' | Select-Object Name,PackageFullName,Publisher")
    if isinstance(return_data,dict): return [return_data]
    return return_data if isinstance(return_data,list) else []


def app_manager() -> None:
    console.clear(); header("APP MANAGER", "Detect before removal — system-critical packages are not included in the curated list")
    installed=[]
    with Progress(SpinnerColumn(style="red"),TextColumn("{task.description}"),console=console) as prog:
        for label,pattern,category in CONFIG["bloat_apps"]:
            task=prog.add_task(f"Checking {label}...",total=None)
            matches=appx_matches(pattern)
            if matches: installed.append((label,pattern,category,len(matches)))
            prog.update(task,description=f"[green]✓[/] checked {label}")
    if not installed: info("None of the curated optional packages were detected for the current user."); pause(); return
    t=Table(box=box.ROUNDED,header_style="bold red")
    t.add_column("#",width=4);t.add_column("App",width=24);t.add_column("Category",width=24);t.add_column("Packages",justify="right")
    for i,x in enumerate(installed,1):t.add_row(str(i),x[0],x[2],str(x[3]))
    console.print(t)
    raw=Prompt.ask("\n  Choose package numbers, or 0",default="0")
    if raw.strip()=="0":return
    sel=[installed[int(x)-1] for x in raw.split() if x.isdigit() and 1<=int(x)<=len(installed)]
    if not sel:return
    console.print("\n  Scope: [1] current user  [2] all users  [3] all users + remove provisioning  [0] cancel")
    scope=Prompt.ask("  Scope",choices=["0","1","2","3"],show_choices=False,default="1")
    if scope=="0":return
    if scope!="1" and CONFIG["ui"].get("safe_mode",True): warn("All-user/provisioning removal requires Advanced Mode.");pause();return
    if not Confirm.ask("  Remove the selected optional packages?",default=False):return
    for label,pattern,_,_ in sel:
        if scope=="1": script=f"Get-AppxPackage '{pattern}' | Remove-AppxPackage -ErrorAction Stop"
        else:
            script=f"Get-AppxPackage -AllUsers '{pattern}' | ForEach-Object {{ Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Continue }}"
            if scope=="3": script += f"; Get-AppxProvisionedPackage -Online | Where-Object {{$_.DisplayName -like '{pattern}'}} | Remove-AppxProvisionedPackage -Online -AllUsers -ErrorAction Continue"
        r=run_ps(script,120,mutate=True)
        remain=appx_matches(pattern,all_users=(scope!="1")) if not CONFIG["ui"].get("dry_run",False) else []
        ok_=r.ok and not remain
        (success if ok_ else failure)(f"{label}: {'removed/verified' if ok_ else 'could not be fully verified'}")
        add_history("App Removal","success" if ok_ else "partial",label)
    pause()


# =============================================================================
# [8] APP UPDATES
# =============================================================================


def app_updates() -> None:
    console.clear();header("APP UPDATES", "WinGet preview first — no blind upgrade-all")
    if not command_exists("winget.exe"):
        warn("WinGet was not found on this PC.");pause();return
    r=run(["winget.exe","upgrade","--accept-source-agreements"],120)
    console.print(Panel(r.stdout[-10000:] if r.stdout else r.stderr,title="Available updates",border_style="red"))
    if not r.ok:failure("WinGet could not enumerate updates.");pause();return
    console.print("  [dim]Enter an exact package ID to upgrade, ALL for every available update, or 0 to cancel.[/]")
    raw=Prompt.ask("  Package ID",default="0").strip()
    if raw=="0":return
    if raw.upper()=="ALL":
        if not Confirm.ask("  Upgrade every package currently offered by WinGet?",default=False):return
        cmd=["winget.exe","upgrade","--all","--accept-package-agreements","--accept-source-agreements"]
    else:
        cmd=["winget.exe","upgrade","--id",raw,"--exact","--accept-package-agreements","--accept-source-agreements"]
    rr=run(cmd,1800,mutate=True)
    (success if rr.ok else failure)("WinGet upgrade command completed." if rr.ok else "WinGet upgrade returned an error.")
    add_history("App Updates","success" if rr.ok else "failed",raw);pause()


# =============================================================================
# [9] DNS BENCHMARK & SWITCH
# =============================================================================


def dns_query_once(server: str, domain: str, timeout: float=2.0) -> Optional[float]:
    resolver=dns.resolver.Resolver(configure=False)
    resolver.nameservers=[server];resolver.timeout=timeout;resolver.lifetime=timeout
    t0=time.perf_counter()
    try:
        resolver.resolve(domain,"A",search=False)
        return (time.perf_counter()-t0)*1000
    except Exception:
        return None


def benchmark_provider(provider: Dict[str,str], repeats:int=3) -> Dict[str,Any]:
    samples:List[float]=[]; attempts=0
    for domain in CONFIG["dns_test_domains"]:
        for _ in range(repeats):
            attempts+=1; ms=dns_query_once(provider["primary"],domain)
            if ms is not None:samples.append(ms)
    return {
        **provider,
        "samples":samples,
        "attempts":attempts,
        "success_rate":(len(samples)/attempts*100) if attempts else 0,
        "median":statistics.median(samples) if samples else float("inf"),
        "p95":percentile(samples,.95) if samples else float("inf"),
    }


def dns_benchmark_switch() -> None:
    console.clear();header("DNS BENCHMARK & SWITCH", "Actual DNS queries — median, P95, success rate, then apply + verify")
    adapter=active_network_adapter()
    if not adapter:failure("Could not find an active adapter with a default IPv4 route.");pause();return
    info(f"Adapter: [bold]{adapter['InterfaceAlias']}[/] · IPv4 {adapter.get('IPv4','?')}")
    info("Current DNS: " + ", ".join(adapter.get("DNS",[]) or ["automatic / not reported"]))
    results=[]
    with Progress(SpinnerColumn(style="red"),TextColumn("{task.description}"),console=console) as prog:
        for provider in CONFIG["dns_providers"]:
            task=prog.add_task(f"Querying {provider['name']}...",total=None)
            res=benchmark_provider(provider);results.append(res)
            prog.update(task,description=f"[green]✓[/] {provider['name']} benchmarked")
    results.sort(key=lambda x:(-x["success_rate"],x["median"],x["p95"]))
    t=Table(box=box.ROUNDED,header_style="bold red")
    t.add_column("#",width=4);t.add_column("Provider",width=18);t.add_column("Primary",width=16);t.add_column("Median",justify="right");t.add_column("P95",justify="right");t.add_column("Success",justify="right")
    for i,r in enumerate(results,1):
        med="timeout" if r["median"]==float("inf") else f"{r['median']:.1f} ms"
        p95="timeout" if r["p95"]==float("inf") else f"{r['p95']:.1f} ms"
        t.add_row(str(i),("★ " if i==1 else "")+r["name"],r["primary"],med,p95,f"{r['success_rate']:.0f}%")
    console.print(t)
    console.print("\n  [A] Apply best  [1..N] Choose provider  [R] Restore automatic/DHCP  [0] Back")
    raw=Prompt.ask("  Choose",default="0").strip().upper()
    if raw=="0":return
    previous={
        "type":"dns","label":"DNS settings", "created_at":datetime.now().isoformat(timespec="seconds"),
        "interface_index":adapter["InterfaceIndex"],
        "interface_alias":adapter["InterfaceAlias"],
        "mode":"dhcp" if str(adapter.get("Dhcp","")).lower()=="enabled" else "servers",
        "servers":adapter.get("DNS",[]),
    }
    sid=f"{int(time.time())}-{uuid.uuid4().hex[:6]}";STATE["snapshots"][sid]=previous;save_state()
    if raw=="R":
        ok_=reset_dns_servers(int(adapter["InterfaceIndex"]));label="automatic/DHCP"
    else:
        chosen=results[0] if raw=="A" else results[int(raw)-1] if raw.isdigit() and 1<=int(raw)<=len(results) else None
        if not chosen:return
        ok_=set_dns_servers(int(adapter["InterfaceIndex"]),[chosen["primary"],chosen["secondary"]]);label=chosen["name"]
    if ok_:
        run(["ipconfig.exe","/flushdns"],15,mutate=True)
        test=dns_query_once((active_network_adapter() or {}).get("DNS",["1.1.1.1"])[0],"microsoft.com") if not CONFIG["ui"].get("dry_run",False) else 0
        success(f"DNS set to {label}; post-change query {'OK' if test is not None else 'failed'}.")
        add_history("DNS Change","success",f"{label}; snapshot={sid}")
    else:
        failure("Windows did not verify the requested DNS change. The previous-state snapshot was kept.")
    pause()


# =============================================================================
# [10/11] NETWORK DIAGNOSTICS & LATENCY
# =============================================================================


def dotnet_ping(host:str,timeout_ms:int=1800) -> Optional[float]:
    # Works with Windows PowerShell 5.1; no dependence on modern Test-Connection parameters.
    script=(
        "$p=New-Object System.Net.NetworkInformation.Ping; "
        f"$r=$p.Send('{host}',{timeout_ms}); "
        "if($r.Status -eq 'Success'){[double]$r.RoundtripTime}else{exit 2}"
    )
    r=run_ps(script,5)
    if not r.ok:return None
    try:return float(r.stdout.strip().splitlines()[-1])
    except Exception:return None


def ping_samples(host:str,count:int=5,interval:float=.25) -> List[Optional[float]]:
    out=[]
    for _ in range(count):
        out.append(dotnet_ping(host));time.sleep(interval)
    return out


def latency_stats(samples:List[Optional[float]]) -> Dict[str,float]:
    valid=[float(x) for x in samples if x is not None]
    loss=(1-len(valid)/len(samples))*100 if samples else 100
    if not valid:return {"avg":float("inf"),"min":float("inf"),"max":float("inf"),"jitter":float("inf"),"loss":loss}
    diffs=[abs(valid[i]-valid[i-1]) for i in range(1,len(valid))]
    return {"avg":statistics.mean(valid),"min":min(valid),"max":max(valid),"jitter":statistics.mean(diffs) if diffs else 0,"loss":loss}


def network_diagnostics() -> None:
    console.clear();header("NETWORK DIAGNOSTICS", "Read-only checks to separate LAN, ISP, DNS and route problems")
    a=active_network_adapter()
    if not a:failure("No active default-route adapter found.");pause();return
    gateway=str(a.get("Gateway") or "")
    gw=latency_stats(ping_samples(gateway,4)) if gateway else None
    internet=latency_stats(ping_samples("1.1.1.1",4))
    dns_ms=dns_query_once((a.get("DNS") or ["1.1.1.1"])[0],"github.com")
    t=Table(box=box.ROUNDED,header_style="bold red");t.add_column("Check",width=20);t.add_column("Result",width=20);t.add_column("Interpretation",width=48)
    if gw:t.add_row("Gateway",f"{gw['avg']:.1f} ms / {gw['loss']:.0f}% loss","Local Wi-Fi/Ethernet path")
    t.add_row("Internet",("timeout" if internet["avg"]==float("inf") else f"{internet['avg']:.1f} ms / {internet['loss']:.0f}% loss"),"Upstream reachability")
    t.add_row("DNS query",("failed" if dns_ms is None else f"{dns_ms:.1f} ms"),"Resolver responsiveness")
    t.add_row("Adapter",str(a["InterfaceAlias"]),str(a.get("Description","")))
    console.print(t)
    if Confirm.ask("\n  Run traceroute to 1.1.1.1 too?",default=False):
        r=run(["tracert.exe","-d","-w","800","1.1.1.1"],45);console.print(Panel(r.stdout[-12000:],title="Traceroute",border_style="red"))
    pause()


def latency_monitor() -> None:
    console.clear();header("LATENCY MONITOR", "Average + jitter + packet loss; Ctrl+C to stop")
    t=Table(box=box.SIMPLE,show_header=False)
    for i,(host,label) in enumerate(CONFIG["latency_targets"],1):t.add_row(f"[{i}]",host,label)
    t.add_row("[C]","Custom","hostname or IP");t.add_row("[0]","Back","");console.print(t)
    raw=Prompt.ask("  Choose",default="0").upper()
    if raw=="0":return
    if raw=="C":host=Prompt.ask("  Host").strip()
    elif raw.isdigit() and 1<=int(raw)<=len(CONFIG["latency_targets"]):host=CONFIG["latency_targets"][int(raw)-1][0]
    else:return
    samples:List[Optional[float]]=[];seq=0
    try:
        while True:
            seq+=1;ms=dotnet_ping(host);samples.append(ms);stats=latency_stats(samples[-50:])
            state="[green]●[/]" if ms is not None else "[red]●[/]"
            cur="timeout" if ms is None else f"{ms:.0f} ms"
            console.print(f"  {state} #{seq:04d} {cur:>10}  [dim]avg {stats['avg']:.1f}  jitter {stats['jitter']:.1f}  loss {stats['loss']:.1f}%[/]")
            time.sleep(.75)
    except KeyboardInterrupt:
        stats=latency_stats(samples)
        console.print(f"\n  Avg {stats['avg']:.1f}ms · Min {stats['min']:.1f} · Max {stats['max']:.1f} · Jitter {stats['jitter']:.1f} · Loss {stats['loss']:.1f}%")
        pause()


# =============================================================================
# [12] NETWORK REPAIR
# =============================================================================


def firewall_backup() -> Optional[Path]:
    path=APP_DIR/f"firewall-backup-{datetime.now():%Y%m%d_%H%M%S}.wfw"
    r=run(["netsh.exe","advfirewall","export",str(path)],30,mutate=True)
    return path if r.ok else None


def network_repair() -> None:
    console.clear();header("NETWORK REPAIR", "Safe repair is separate from destructive reset")
    a=active_network_adapter()
    t=Table(box=box.SIMPLE,show_header=False)
    t.add_row("[1]","Safe repair","flush DNS, clear ARP, renew DHCP when the active adapter uses DHCP")
    t.add_row("[2]","Destructive reset","Winsock + TCP/IP + IPv6 + firewall reset; backs up firewall first")
    t.add_row("[0]","Back","");console.print(t)
    ch=Prompt.ask("  Choose",choices=["0","1","2"],show_choices=False)
    if ch=="0":return
    if ch=="1":
        run(["ipconfig.exe","/flushdns"],15,mutate=True);run(["netsh.exe","interface","ip","delete","arpcache"],15,mutate=True)
        if a and str(a.get("Dhcp","")).lower()=="enabled":
            # Do not claim success until renew exits successfully; no forced eight-second terminate.
            r=run(["ipconfig.exe","/renew",str(a["InterfaceAlias"])],60,mutate=True)
            (success if r.ok else warn)("DHCP renewal completed." if r.ok else "DHCP renewal did not complete successfully; current lease was not reported as renewed.")
        else:info("Active adapter does not report DHCP enabled; release/renew was skipped.")
        add_history("Network Safe Repair","success","completed");pause();return
    if CONFIG["ui"].get("safe_mode",True):warn("Destructive reset is locked in Safe Mode.");pause();return
    warn("This resets custom Winsock/TCP/IP/IPv6 and Windows Firewall rules. VPN or managed-network settings can be affected.")
    if not Confirm.ask("  Continue with destructive network reset?",default=False):return
    fw=firewall_backup();info(f"Firewall backup: {fw if fw else 'FAILED — firewall reset will not run'}")
    cmds=[
        ["netsh.exe","winsock","reset"],
        ["netsh.exe","int","ip","reset"],
        ["netsh.exe","int","ipv6","reset"],
    ]
    results=[run(c,30,mutate=True).ok for c in cmds]
    if fw:results.append(run(["netsh.exe","advfirewall","reset"],30,mutate=True).ok)
    (success if all(results) else warn)("Network reset commands completed; restart Windows." if all(results) else "Some network reset operations failed. Review the log.")
    add_history("Network Destructive Reset","success" if all(results) else "partial",f"firewall_backup={fw}");pause()


# =============================================================================
# [13] SYSTEM DASHBOARD / HEALTH
# =============================================================================


def cim_one(class_name:str,props:List[str]) -> Dict[str,Any]:
    selection=",".join(props)
    obj=ps_json(f"Get-CimInstance {class_name} | Select-Object -First 1 {selection}")
    return obj if isinstance(obj,dict) else {}


def system_snapshot() -> Dict[str,Any]:
    osinfo=cim_one("Win32_OperatingSystem",["Caption","Version","BuildNumber","OSArchitecture","LastBootUpTime"])
    cpu=cim_one("Win32_Processor",["Name","NumberOfCores","NumberOfLogicalProcessors","MaxClockSpeed","VirtualizationFirmwareEnabled"])
    gpu=cim_one("Win32_VideoController",["Name","DriverVersion"])
    board=cim_one("Win32_BaseBoard",["Manufacturer","Product"])
    bios=cim_one("Win32_BIOS",["SMBIOSBIOSVersion","ReleaseDate"])
    a=active_network_adapter();mem=psutil.virtual_memory();disk=psutil.disk_usage(str(Path(os.environ.get("SystemDrive","C:")) / "\\"))
    defender=ps_json("Get-MpComputerStatus -ErrorAction SilentlyContinue | Select-Object AntivirusEnabled,RealTimeProtectionEnabled,AntivirusSignatureLastUpdated,QuickScanAge,FullScanAge") or {}
    secure=run_ps("try{Confirm-SecureBootUEFI}catch{$false}",10)
    tpm=ps_json("Get-Tpm -ErrorAction SilentlyContinue | Select-Object TpmPresent,TpmReady") or {}
    return {"os":osinfo,"cpu":cpu,"gpu":gpu,"board":board,"bios":bios,"adapter":a,"memory":mem,"disk":disk,"defender":defender,"secure_boot":secure.stdout.strip(),"tpm":tpm,"power":active_power_plan()}


def system_dashboard() -> None:
    console.clear();header("SYSTEM DASHBOARD", "CIM-based — no WMIC dependency")
    s=system_snapshot()
    def panel(title,rows):
        t=Table(box=box.SIMPLE,show_header=False,expand=True);t.add_column(style="bold red",width=20);t.add_column(style="bold white")
        for k,v in rows:t.add_row(k,str(v if v not in (None,"") else "N/A"))
        console.print(Panel(t,title=f"[bold red]{title}[/]",border_style="red"))
    panel("WINDOWS",[("OS",s["os"].get("Caption")),("Version",f"{s['os'].get('Version','')} build {s['os'].get('BuildNumber','')}"),("Architecture",s["os"].get("OSArchitecture")),("Power",(s["power"] or {}).get("name"))])
    panel("CPU / MEMORY",[("CPU",s["cpu"].get("Name")),("Cores / Threads",f"{s['cpu'].get('NumberOfCores','?')} / {s['cpu'].get('NumberOfLogicalProcessors','?')}"),("RAM",f"{bytes_human(s['memory'].used)} used / {bytes_human(s['memory'].total)}")])
    panel("GPU / BOARD",[("GPU",s["gpu"].get("Name")),("GPU Driver",s["gpu"].get("DriverVersion")),("Motherboard",f"{s['board'].get('Manufacturer','')} {s['board'].get('Product','')}"),("BIOS",s["bios"].get("SMBIOSBIOSVersion"))])
    a=s["adapter"] or {};panel("NETWORK / SECURITY",[("Adapter",a.get("InterfaceAlias")),("IPv4",a.get("IPv4")),("Gateway",a.get("Gateway")),("DNS",", ".join(a.get("DNS",[]) or [])),("Secure Boot",s["secure_boot"]),("TPM ready",s["tpm"].get("TpmReady")),("Defender realtime",s["defender"].get("RealTimeProtectionEnabled"))])
    pause()


def system_health() -> None:
    console.clear();header("SYSTEM HEALTH", "Read-only summary — diagnose before changing things")
    s=system_snapshot();checks=[]
    checks.append(("System disk free",100-s["disk"].percent,"OK" if s["disk"].percent<90 else "LOW SPACE"))
    checks.append(("RAM load",s["memory"].percent,"OK" if s["memory"].percent<90 else "HIGH"))
    a=s["adapter"];checks.append(("Default network",str((a or {}).get("InterfaceAlias","missing")),"OK" if a else "CHECK"))
    d=s["defender"];checks.append(("Defender realtime",d.get("RealTimeProtectionEnabled","unknown"),"OK" if d.get("RealTimeProtectionEnabled") else "CHECK"))
    dns_ms=dns_query_once(((a or {}).get("DNS") or ["1.1.1.1"])[0],"microsoft.com") if a else None
    checks.append(("DNS query",f"{dns_ms:.1f} ms" if dns_ms else "failed","OK" if dns_ms and dns_ms<100 else "CHECK"))
    t=Table(box=box.ROUNDED,header_style="bold red");t.add_column("Check");t.add_column("Value");t.add_column("Status")
    for x in checks:t.add_row(str(x[0]),str(x[1]),str(x[2]))
    console.print(t);pause()


# =============================================================================
# [14] DEFENDER
# =============================================================================


def defender_center() -> None:
    while True:
        console.clear();header("WINDOWS DEFENDER", "Status, signature update, scans and threat history")
        status=ps_json("Get-MpComputerStatus -ErrorAction SilentlyContinue | Select-Object AntivirusEnabled,RealTimeProtectionEnabled,AntivirusSignatureVersion,AntivirusSignatureLastUpdated,QuickScanAge,FullScanAge")
        if not isinstance(status,dict):warn("Microsoft Defender cmdlets are unavailable or controlled by another security product/policy.");pause();return
        t=Table(box=box.ROUNDED,show_header=False)
        for k,v in status.items():t.add_row(str(k),str(v))
        console.print(t)
        console.print("\n  [1] Update signatures  [2] Quick scan  [3] Threat history  [0] Back")
        ch=Prompt.ask("  Choose",choices=["0","1","2","3"],show_choices=False)
        if ch=="0":return
        if ch=="1":r=run_ps("Update-MpSignature -ErrorAction Stop",300,mutate=True)
        elif ch=="2":r=run_ps("Start-MpScan -ScanType QuickScan -ErrorAction Stop",1800,mutate=True)
        else:
            obj=ps_json("Get-MpThreatDetection -ErrorAction SilentlyContinue | Select-Object InitialDetectionTime,ThreatID,ActionSuccess,Resources",60);console.print_json(data=obj if obj else []);pause();continue
        (success if r.ok else failure)("Defender command accepted." if r.ok else "Defender command failed or was blocked by policy.");pause()


# =============================================================================
# [15] PRIVACY CONTROLS
# =============================================================================

PRIVACY_ITEMS={
    "Telemetry policy":("HKLM",r"SOFTWARE\Policies\Microsoft\Windows\DataCollection","AllowTelemetry",winreg.REG_DWORD,0),
    "Activity feed":("HKLM",r"SOFTWARE\Policies\Microsoft\Windows\System","EnableActivityFeed",winreg.REG_DWORD,0),
    "Advertising ID":("HKCU",r"Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo","Enabled",winreg.REG_DWORD,0),
    "Bing suggestions":("HKCU",r"SOFTWARE\Policies\Microsoft\Windows\Explorer","DisableSearchBoxSuggestions",winreg.REG_DWORD,1),
    "Clipboard history":("HKLM",r"SOFTWARE\Policies\Microsoft\Windows\System","AllowClipboardHistory",winreg.REG_DWORD,0),
}


def privacy_controls() -> None:
    console.clear();header("PRIVACY CONTROLS", "Recommended changes are snapshotted before application")
    t=Table(box=box.ROUNDED,header_style="bold red");t.add_column("#");t.add_column("Setting");t.add_column("Current")
    items=list(PRIVACY_ITEMS.items())
    for i,(label,(h,p,n,_,_)) in enumerate(items,1):
        cur=reg_read(h,p,n);t.add_row(str(i),label,str(cur["value"] if cur["exists"] else "Windows/default"))
    console.print(t);console.print("\n  Enter numbers, ALL, RESTORE, or 0")
    raw=Prompt.ask("  Choose",default="0").strip().upper()
    if raw=="0":return
    if raw=="RESTORE":restore_history();return
    selected=items if raw=="ALL" else [items[int(x)-1] for x in raw.split() if x.isdigit() and 1<=int(x)<=len(items)]
    if not selected:return
    regitems=[(v[0],v[1],v[2]) for _,v in selected];sid=snapshot_registry("Privacy Controls",regitems)
    oks=[]
    for label,(h,p,n,k,v) in selected:oks.append(reg_set(h,p,n,k,v))
    (success if all(oks) else warn)("Privacy settings applied and verified." if all(oks) else "Some settings could not be verified.")
    add_history("Privacy Controls","success" if all(oks) else "partial",f"snapshot={sid}");pause()


# =============================================================================
# [16] RESTORE / HISTORY
# =============================================================================


def restore_snapshot(snapshot_id:str) -> bool:
    snap=STATE.get("snapshots",{}).get(snapshot_id)
    if not snap:return False
    typ=snap.get("type")
    if typ=="registry":
        good,bad=restore_registry_snapshot(snap);ok_=bad==0;detail=f"registry ok={good}, bad={bad}"
    elif typ=="dns":
        ok_=restore_dns_snapshot(snap);detail="dns"
    else:
        return False
    add_history("Restore Snapshot","success" if ok_ else "partial",f"{snapshot_id} {detail}")
    if ok_:
        STATE["snapshots"].pop(snapshot_id,None);save_state()
    return ok_


def restore_history() -> None:
    while True:
        console.clear();header("RESTORE & HISTORY", "Snapshots are kept until a restore succeeds")
        session=STATE.get("gaming_session")
        if session:warn(f"Interrupted/active Gaming Session saved from {session.get('started_at','?')}.")
        snaps=list(STATE.get("snapshots",{}).items())
        t=Table(box=box.ROUNDED,header_style="bold red");t.add_column("#");t.add_column("Created");t.add_column("Type");t.add_column("Label")
        for i,(sid,s) in enumerate(snaps,1):t.add_row(str(i),s.get("created_at",""),s.get("type",""),s.get("label",sid))
        console.print(t)
        history=STATE.get("history",[])[-10:]
        if history:
            console.print("\n  [bold]Recent history[/]")
            for h in reversed(history):console.print(f"  [dim]{h['ts']}[/] {h['action']} · {h['status']} · {h['detail']}")
        console.print("\n  [G] Restore Gaming Session  [1..N] Restore snapshot  [P] Create Windows restore point  [0] Back")
        raw=Prompt.ask("  Choose",default="0").upper()
        if raw=="0":return
        if raw=="G":
            if session:
                (success if restore_gaming_session() else warn)("Gaming state restored." if not STATE.get("gaming_session") else "Restore completed with failures.")
            else:info("No Gaming Session restore is pending.")
            pause();continue
        if raw=="P":
            if Confirm.ask("  Ask Windows to create a system restore point?",default=True):
                r=run_ps("Checkpoint-Computer -Description 'Voltune manual checkpoint' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop",120,mutate=True)
                (success if r.ok else warn)("Windows restore point requested." if r.ok else "Windows could not create a restore point (System Protection may be disabled or rate-limited).")
            pause();continue
        if raw.isdigit() and 1<=int(raw)<=len(snaps):
            sid=snaps[int(raw)-1][0]
            if Confirm.ask(f"  Restore snapshot {sid}?",default=True):
                (success if restore_snapshot(sid) else failure)("Snapshot restored." if sid not in STATE.get("snapshots",{}) else "Snapshot restore failed; it was kept for retry.")
            pause()


# =============================================================================
# [17] EXPERIMENTAL TWEAKS
# =============================================================================


def active_ipv4_interface_guid() -> Optional[str]:
    a=active_network_adapter()
    if not a:return None
    script=f"(Get-NetAdapter -InterfaceIndex {int(a['InterfaceIndex'])}).InterfaceGuid.Guid"
    r=run_ps(script,10);return r.stdout.strip().strip("{}") if r.ok else None


def experimental_tweaks() -> None:
    console.clear();header("EXPERIMENTAL TWEAKS", "Not included in recommended optimization")
    if CONFIG["ui"].get("safe_mode",True):warn("Locked in Safe Mode. Toggle Advanced Mode from the main menu first.");pause();return
    t=Table(box=box.SIMPLE,show_header=False)
    t.add_row("[1]","Disable Nagle on active adapter","TCPAckFrequency=1 + TCPNoDelay=1; application benefit is workload-dependent")
    t.add_row("[2]","Restore Nagle override","Delete Voltune's active-adapter override values")
    t.add_row("[3]","Clear BCD timer overrides","Delete useplatformclock and disabledynamictick overrides; return control to Windows")
    t.add_row("[4]","Disable Game fullscreen behavior override","Compatibility tweak; not a universal latency win")
    t.add_row("[0]","Back","");console.print(t)
    ch=Prompt.ask("  Choose",choices=["0","1","2","3","4"],show_choices=False)
    if ch=="0":return
    if not Confirm.ask("  Apply this Advanced change?",default=False):return
    if ch in ("1","2"):
        guid=active_ipv4_interface_guid()
        if not guid:failure("Could not resolve the active adapter registry GUID.");pause();return
        path=rf"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{{{guid}}}"
        snapshot_registry("Nagle active adapter",[("HKLM",path,"TcpAckFrequency"),("HKLM",path,"TCPNoDelay")])
        if ch=="1":ok_=reg_set("HKLM",path,"TcpAckFrequency",winreg.REG_DWORD,1) and reg_set("HKLM",path,"TCPNoDelay",winreg.REG_DWORD,1)
        else:ok_=reg_delete("HKLM",path,"TcpAckFrequency") and reg_delete("HKLM",path,"TCPNoDelay")
    elif ch=="3":
        # Deliberately no 'HPET off = faster' promise. This only clears overrides.
        a=run(["bcdedit.exe","/deletevalue","useplatformclock"],15,mutate=True)
        b=run(["bcdedit.exe","/deletevalue","disabledynamictick"],15,mutate=True)
        ok_=a.ok or b.ok
    else:
        path=r"System\GameConfigStore";snapshot_registry("Fullscreen behavior",[("HKCU",path,"GameDVR_FSEBehaviorMode"),("HKCU",path,"GameDVR_HonorUserFSEBehaviorMode")])
        ok_=reg_set("HKCU",path,"GameDVR_FSEBehaviorMode",winreg.REG_DWORD,2) and reg_set("HKCU",path,"GameDVR_HonorUserFSEBehaviorMode",winreg.REG_DWORD,0)
    (success if ok_ else failure)("Advanced change completed." if ok_ else "Advanced change could not be verified.");pause()


# =============================================================================
# [18] PROCESS INSPECTOR
# =============================================================================


def process_inspector() -> None:
    while True:
        console.clear();header("PROCESS INSPECTOR", "Read-only in Safe Mode — inspect before killing anything")
        # First sample primes CPU counters.
        for p in psutil.process_iter():
            try:p.cpu_percent(None)
            except Exception:pass
        time.sleep(.45)
        rows=[]
        for p in psutil.process_iter(["pid","name","memory_info","io_counters"]):
            try:
                cpu=p.cpu_percent(None);mem=p.info["memory_info"].rss if p.info.get("memory_info") else 0
                io=p.info.get("io_counters");io_total=(io.read_bytes+io.write_bytes) if io else 0
                rows.append((cpu,mem,io_total,p.info["pid"],p.info["name"] or "?"))
            except (psutil.AccessDenied,psutil.NoSuchProcess):pass
        rows.sort(reverse=True,key=lambda x:(x[0],x[1]))
        t=Table(box=box.ROUNDED,header_style="bold red");t.add_column("PID",justify="right");t.add_column("Process",width=34);t.add_column("CPU",justify="right");t.add_column("RAM",justify="right");t.add_column("I/O total",justify="right")
        for cpu,mem,io,pid,name in rows[:20]:t.add_row(str(pid),name,f"{cpu:.1f}%",bytes_human(mem),bytes_human(io))
        console.print(t)
        console.print("\n  [R] Refresh  [K] End process (Advanced only)  [0] Back")
        raw=Prompt.ask("  Choose",default="0").upper()
        if raw=="0":return
        if raw=="R":continue
        if raw=="K":
            if CONFIG["ui"].get("safe_mode",True):warn("Process termination is locked in Safe Mode.");pause();continue
            try:pid=int(Prompt.ask("  PID"))
            except ValueError:continue
            if pid in (0,4,os.getpid()):warn("Voltune refuses to terminate that protected PID.");pause();continue
            try:
                p=psutil.Process(pid);name=p.name()
                if Confirm.ask(f"  End {name} (PID {pid})?",default=False):p.terminate();p.wait(4);success("Process terminated.")
            except Exception as exc:failure(str(exc))
            pause()


# =============================================================================
# [19] SELF DIAGNOSTICS
# =============================================================================


def self_diagnostics() -> None:
    console.clear();header("SELF DIAGNOSTICS", "Check Voltune dependencies and Windows capabilities")
    checks=[]
    checks.append(("Administrator",is_admin(),"Required for privileged changes"))
    checks.append(("PowerShell",command_exists("powershell.exe"),"PowerShell 5.1+ expected"))
    checks.append(("PowerCFG",command_exists("powercfg.exe"),"Power plan manager"))
    checks.append(("WinGet",command_exists("winget.exe"),"Optional: app updates"))
    checks.append(("CIM",run_ps("Get-CimInstance Win32_OperatingSystem | Out-Null",10).ok,"System dashboard"))
    checks.append(("NetTCPIP",run_ps("Get-Command Get-NetIPConfiguration -ErrorAction Stop | Out-Null",10).ok,"Network/DNS tools"))
    try:
        probe=APP_DIR/".voltune-write-test";probe.write_text("ok");probe.unlink();writable=True
    except Exception:writable=False
    checks.append(("Data directory writable",writable,str(APP_DIR)))
    t=Table(box=box.ROUNDED,header_style="bold red");t.add_column("Check");t.add_column("Status");t.add_column("Why")
    for name,ok_,why in checks:t.add_row(name,"[green]OK[/]" if ok_ else "[red]MISSING[/]",why)
    console.print(t);pause()


# =============================================================================
# MAIN MENU / HELP
# =============================================================================

MENU: Dict[str, Tuple[str, str, Callable[[], None]]] = {
    "1": ("Gaming Session", "temporary gaming cleanup; remembers service + power state and restores it", gaming_session),
    "2": ("Gaming Preflight", "read-only check of CPU, RAM, power, network and closable background apps", lambda: gaming_preflight(True)),
    "3": ("Power Plans", "switch Balanced / High / Ultimate / Power Saver with verification", power_plans),
    "4": ("Performance Settings", "conservative visual + Game DVR settings; snapshots supported values first", performance_settings),
    "5": ("Storage Cleanup", "preview temp/browser cache size before deleting selected categories", storage_cleanup),
    "6": ("Startup Manager", "toggle common sign-in apps and inspect startup Scheduled Tasks", startup_manager),
    "7": ("App Manager", "detect and remove selected optional Windows Appx packages", app_manager),
    "8": ("App Updates", "preview available WinGet updates before choosing what to install", app_updates),
    "9": ("Component Cleanup", "run Windows DISM component-store cleanup separately from cache cleaning", component_cleanup),
    "10": ("DNS Benchmark & Switch", "test real DNS lookups, rank providers, apply one, verify it, and restore old DNS when needed", dns_benchmark_switch),
    "11": ("Network Diagnostics", "helps identify whether slowness comes from your router, internet connection, DNS or network route", network_diagnostics),
    "12": ("Latency Monitor", "continuously measure ping, jitter and packet loss to a target you choose", latency_monitor),
    "13": ("Network Repair", "fix common network problems; destructive resets are kept separate and require confirmation", network_repair),
    "14": ("System Dashboard", "view Windows, CPU, RAM, GPU, disks, network, security and power information in one place", system_dashboard),
    "15": ("System Health", "read-only summary of disk, RAM, network, DNS and Defender health without changing Windows", system_health),
    "16": ("Windows Defender", "check Microsoft Defender status and run supported signature, scan and threat-history actions", defender_center),
    "17": ("Process Inspector", "see which apps use CPU, RAM and disk; ending a process is locked behind Advanced Mode", process_inspector),
    "18": ("Privacy Controls", "adjust selected Windows privacy settings and save snapshots for supported restoration", privacy_controls),
    "19": ("Restore & History", "review previous Voltune changes, recover interrupted Gaming Sessions and restore supported settings", restore_history),
    "20": ("Experimental Tweaks", "advanced-only network, fullscreen and BCD overrides; not part of recommended optimization", experimental_tweaks),
    "21": ("Memory Tools", "advanced-only working-set tools for troubleshooting memory behavior, not a generic speed boost", memory_tools),
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
        for key in [str(i) for i in range(1, 22)]:
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
        ("MAINTENANCE", ["5","6","7","8","9"]),
        ("NETWORK", ["10","11","12","13"]),
        ("SYSTEM", ["14","15","16","17"]),
        ("PRIVACY & RECOVERY", ["18","19"]),
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
