from __future__ import annotations

import time
from dataclasses import asdict, dataclass

import psutil


@dataclass(frozen=True)
class SystemSnapshot:
    timestamp: float
    cpu_percent: float
    memory_percent: float
    memory_used: int
    memory_total: int
    disk_percent: float
    disk_used: int
    disk_total: int
    net_bytes_sent: int
    net_bytes_recv: int
    battery_percent: float | None
    battery_plugged: bool | None
    top_processes: list[dict]

    def to_dict(self) -> dict:
        return asdict(self)


def collect_snapshot(*, process_limit: int = 5) -> SystemSnapshot:
    cpu = psutil.cpu_percent(interval=0.15)
    mem = psutil.virtual_memory()
    try:
        disk = psutil.disk_usage("C:\\" if __import__("os").name == "nt" else "/")
    except OSError:
        disk = psutil.disk_usage("/")
    net = psutil.net_io_counters()
    try:
        battery = psutil.sensors_battery()
    except (OSError, FileNotFoundError):
        battery = None

    processes: list[dict] = []
    for proc in psutil.process_iter(["pid", "name", "memory_percent"]):
        try:
            processes.append({
                "pid": proc.info["pid"],
                "name": proc.info["name"] or "?",
                "memory_percent": round(float(proc.info.get("memory_percent") or 0), 2),
            })
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    processes.sort(key=lambda p: p["memory_percent"], reverse=True)

    return SystemSnapshot(
        timestamp=time.time(),
        cpu_percent=cpu,
        memory_percent=mem.percent,
        memory_used=mem.used,
        memory_total=mem.total,
        disk_percent=disk.percent,
        disk_used=disk.used,
        disk_total=disk.total,
        net_bytes_sent=net.bytes_sent,
        net_bytes_recv=net.bytes_recv,
        battery_percent=float(battery.percent) if battery else None,
        battery_plugged=bool(battery.power_plugged) if battery else None,
        top_processes=processes[:process_limit],
    )
