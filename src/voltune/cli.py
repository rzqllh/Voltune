from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

from voltune.core.config import default_storage_config, expand_paths
from voltune.core.safety import FilesystemSafety, RiskLevel
from voltune.features.storage_intelligence import find_installers, find_large_files, scan_children, scan_dev_artifacts
from voltune.features.system_monitor import collect_snapshot
from voltune.features.uninstaller import list_installed_apps


def _fmt_bytes(value: int) -> str:
    size = float(value)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{value} B"


def _storage_config() -> dict:
    cfg = default_storage_config()
    home = os.environ.get("VOLTUNE_HOME")
    candidates = [Path(home) / "config.json"] if home else []
    if os.name == "nt":
        candidates.append(Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "Voltune" / "config.json")
    candidates.append(Path.cwd() / "config.json")
    for path in candidates:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        cfg.update(data.get("storage", {}))
        break
    return cfg


def _safety(cfg: dict) -> FilesystemSafety:
    return FilesystemSafety(whitelist=expand_paths(cfg.get("protected_paths", [])))


def _emit(data, *, as_json: bool) -> None:
    if as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2))


def cmd_status(args: argparse.Namespace) -> int:
    if args.watch:
        try:
            while True:
                data = collect_snapshot(process_limit=args.processes).to_dict()
                if args.ndjson or args.json:
                    print(json.dumps(data, ensure_ascii=False), flush=True)
                else:
                    print(
                        f"CPU {data['cpu_percent']:.0f}% | RAM {data['memory_percent']:.0f}% | "
                        f"Disk {data['disk_percent']:.0f}% | RX {_fmt_bytes(data['net_bytes_recv'])} | "
                        f"TX {_fmt_bytes(data['net_bytes_sent'])}",
                        flush=True,
                    )
                time.sleep(max(0.5, args.interval))
        except KeyboardInterrupt:
            return 0
    data = collect_snapshot(process_limit=args.processes).to_dict()
    if args.json:
        _emit(data, as_json=True)
    else:
        print(f"CPU: {data['cpu_percent']:.1f}%")
        print(f"RAM: {data['memory_percent']:.1f}% ({_fmt_bytes(data['memory_used'])}/{_fmt_bytes(data['memory_total'])})")
        print(f"Disk: {data['disk_percent']:.1f}% ({_fmt_bytes(data['disk_used'])}/{_fmt_bytes(data['disk_total'])})")
        if data["battery_percent"] is not None:
            print(f"Battery: {data['battery_percent']:.0f}% ({'plugged' if data['battery_plugged'] else 'battery'})")
        if data["top_processes"]:
            print("Top memory processes:")
            for proc in data["top_processes"]:
                print(f"  {proc['pid']:>6}  {proc['memory_percent']:>6.2f}%  {proc['name']}")
    return 0


def cmd_analyze(args: argparse.Namespace) -> int:
    root = Path(args.path or Path.home()).expanduser().absolute()
    if args.large:
        rows = find_large_files(root, threshold_bytes=int(args.threshold_mb * 1024 * 1024), limit=args.limit)
    else:
        rows = scan_children(root, limit=args.limit)
    data = [row.to_dict() for row in rows]
    if args.json:
        _emit(data, as_json=True)
    else:
        print(root)
        for row in rows:
            print(f"{_fmt_bytes(row.size_bytes):>10}  {row.kind:<4}  {row.path}")
    return 0


def cmd_dev_clean(args: argparse.Namespace) -> int:
    cfg = _storage_config()
    roots = expand_paths(args.path or cfg.get("dev_scan_roots", []))
    safety = _safety(cfg)
    artifacts = scan_dev_artifacts(roots, recent_days=int(cfg.get("recent_project_days", 7)), safety=safety)
    selected = [a for a in artifacts if (args.include_recent or not a.recent)]

    if not args.apply:
        data = {"mode": "dry-run", "candidates": [a.to_dict() for a in selected]}
        if args.json:
            _emit(data, as_json=True)
        else:
            print("Dry run. Use --apply to delete eligible artifacts.")
            for item in selected:
                print(f"{_fmt_bytes(item.size_bytes):>10}  {item.age_days:>6.1f}d  {item.path}")
        return 0

    results = []
    for item in selected:
        result = safety.delete(item.path, dry_run=False, risk=RiskLevel.CAUTION)
        results.append({
            "path": str(result.path), "allowed": result.allowed, "deleted": result.deleted,
            "bytes_estimate": result.bytes_estimate, "reason": result.reason,
        })
    if args.json:
        _emit({"mode": "apply", "results": results}, as_json=True)
    else:
        for result in results:
            status = "DELETED" if result["deleted"] else "SKIPPED"
            print(f"{status:<8} {_fmt_bytes(result['bytes_estimate']):>10}  {result['path']}  {result['reason']}")
    return 0 if all(r["deleted"] or not r["allowed"] for r in results) else 1


def cmd_installers(args: argparse.Namespace) -> int:
    cfg = _storage_config()
    roots = expand_paths(args.path or cfg.get("installer_scan_roots", []))
    rows = find_installers(
        roots,
        min_size_bytes=int(args.min_size_mb * 1024 * 1024),
        min_age_days=args.min_age_days,
        max_depth=args.max_depth,
    )
    if args.json:
        _emit([row.to_dict() for row in rows], as_json=True)
    else:
        for row in rows:
            print(f"{_fmt_bytes(row.size_bytes):>10}  {row.age_days:>6.1f}d  {row.path}")
    return 0


def cmd_apps(args: argparse.Namespace) -> int:
    apps = list_installed_apps()
    data = [app.to_dict() for app in apps]
    if args.json:
        _emit(data, as_json=True)
    else:
        for app in apps:
            version = f" {app.version}" if app.version else ""
            publisher = f" [{app.publisher}]" if app.publisher else ""
            print(f"{app.name}{version}{publisher}")
    return 0


def cmd_history(args: argparse.Namespace) -> int:
    paths = []
    if os.environ.get("VOLTUNE_HOME"):
        paths.append(Path(os.environ["VOLTUNE_HOME"]) / "state.json")
    paths.extend([
        Path.cwd() / "state.json",
        Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "Voltune" / "state.json",
    ])
    data = {"history": []}
    for path in paths:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            break
        except (OSError, json.JSONDecodeError):
            continue
    history = list(reversed(data.get("history", [])))[: args.limit]
    if args.json:
        _emit(history, as_json=True)
    else:
        for item in history:
            print(f"{item.get('time',''):19}  {item.get('status',''):8}  {item.get('action','')}  {item.get('detail','')}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="voltune", description="State-aware Windows utility")
    sub = parser.add_subparsers(dest="command")

    status = sub.add_parser("status", help="System snapshot or live monitor")
    status.add_argument("--json", action="store_true")
    status.add_argument("--watch", action="store_true")
    status.add_argument("--ndjson", action="store_true", help="Stream one JSON object per line; implies watch-friendly output")
    status.add_argument("--interval", type=float, default=2.0)
    status.add_argument("--processes", type=int, default=5)
    status.set_defaults(func=cmd_status)

    analyze = sub.add_parser("analyze", help="Inspect disk usage")
    analyze.add_argument("path", nargs="?")
    analyze.add_argument("--large", action="store_true", help="Find large files recursively")
    analyze.add_argument("--threshold-mb", type=float, default=500)
    analyze.add_argument("--limit", type=int, default=50)
    analyze.add_argument("--json", action="store_true")
    analyze.set_defaults(func=cmd_analyze)

    dev = sub.add_parser("dev-clean", help="Find disposable developer artifacts; dry-run by default")
    dev.add_argument("path", nargs="*")
    dev.add_argument("--include-recent", action="store_true")
    dev.add_argument("--apply", action="store_true")
    dev.add_argument("--json", action="store_true")
    dev.set_defaults(func=cmd_dev_clean)

    installers = sub.add_parser("installers", help="Find stale installer/archive candidates")
    installers.add_argument("path", nargs="*")
    installers.add_argument("--min-size-mb", type=float, default=20)
    installers.add_argument("--min-age-days", type=int, default=14)
    installers.add_argument("--max-depth", type=int, default=5)
    installers.add_argument("--json", action="store_true")
    installers.set_defaults(func=cmd_installers)

    apps = sub.add_parser("apps", help="List installed desktop applications from uninstall registry keys")
    apps.add_argument("--json", action="store_true")
    apps.set_defaults(func=cmd_apps)

    history = sub.add_parser("history", help="Read recent Voltune audit history")
    history.add_argument("--limit", type=int, default=20)
    history.add_argument("--json", action="store_true")
    history.set_defaults(func=cmd_history)

    sub.add_parser("menu", help="Open the interactive Voltune UI")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command in (None, "menu"):
        from voltune.app import main as interactive_main
        interactive_main()
        return 0
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
