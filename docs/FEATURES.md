# Features

## Performance
- Gaming Session: preflight, temporary cleanup, high-performance plan, and automatic restore.
- Gaming Preflight: read-only readiness check.
- Power Plans: Balanced, High Performance, Power Saver, and Ultimate Performance.
- Performance Settings: conservative visual/Game DVR changes with snapshots.

## Storage and maintenance
- Storage Cleanup: previews reclaimable cache/temp space before deletion and routes filesystem mutation through the safety engine.
- Disk Analyzer: interactive directory sizing, drill-down, and large-file discovery; deletion requires Advanced Mode.
- Developer Cleanup: discovers disposable `node_modules`, virtualenv, framework/build, Rust, Gradle, and cache artifacts. Recent projects are not selected by default.
- Installer Cleanup: finds stale Windows installer formats and conservatively classified installer archives.
- Component Cleanup: explicit DISM component-store maintenance.
- Startup Manager: toggles common Run entries and inspects startup Scheduled Tasks.
- App Manager: detects and removes optional Appx packages.
- App Updates: previews WinGet upgrades before applying them.
- Smart Uninstaller: lists desktop uninstall registry entries, launches registered uninstallers, and previews HIGH/MEDIUM leftover candidates.

## Network
- DNS Benchmark & Switch: real resolver queries, ranking, apply, verification, and restore.
- Network Diagnostics: gateway, internet reachability, DNS, HTTPS, and route checks.
- Latency Monitor: average latency, min/max, jitter, and packet loss.
- Network Repair: routine repair separated from destructive reset.

## System
- System Dashboard: OS, CPU, RAM, storage, GPU, network, power, security, and virtualization details.
- Live System Monitor: continuously refreshed CPU/RAM/disk/network/battery/top-process view.
- System Health: read-only health summary.
- Windows Defender: status, signatures, scans, and threat history.
- Process Inspector: CPU/RAM/disk visibility before terminating anything.

## Privacy and recovery
- Privacy Controls: recommended policy changes with snapshots.
- Restore & History: audit trail and supported restoration actions.
- Protected Paths: persistent deletion whitelist used by filesystem cleanup features.
- Windows Restore Point helper for larger batches.

## Direct CLI
- `voltune status [--json] [--watch --ndjson]`
- `voltune analyze [PATH] [--large] [--json]`
- `voltune dev-clean [PATH ...] [--apply] [--json]`
- `voltune installers [PATH ...] [--json]`
- `voltune apps [--json]`
- `voltune history [--json]`

## Advanced
- Experimental Tweaks: Nagle/fullscreen/BCD controls kept out of the default experience.
- Memory Tools: explicit working-set operations for troubleshooting, not marketed as free performance.
