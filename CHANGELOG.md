# Changelog

All notable changes to Voltune are documented here.

## Unreleased

### Documentation
- Expanded manual PyInstaller build instructions, including the short `python -m PyInstaller` form.
- Added a post-deployment checklist covering GitHub setup, first release verification, checksums, screenshots, and unsigned-EXE handling.

### Repository maintenance
- Added Dependabot configuration for Python and GitHub Actions dependencies.
- Added CodeQL analysis for Python.

## [0.1.0] - 2026-08-29

### Added
- State-aware Gaming Session with crash recovery and restore.
- Verified Windows power-plan management, including Ultimate Performance creation.
- Safe performance settings and Advanced experimental controls.
- Storage cleanup with preview and reclaimed-size reporting.
- Safe and destructive network-repair modes.
- DNS benchmark using real DNS queries, provider switching, verification, and restore.
- Network diagnostics, latency/jitter/loss monitoring, and traceroute.
- Startup and Appx management.
- WinGet update preview/install flow.
- CIM-based system dashboard and system-health checks.
- Windows Defender center.
- Privacy controls with snapshots and restore history.
- Process inspector and Advanced memory tools.
- Atomic config/state writes, corrupt-file recovery, and per-session logs.
- Safe Mode and Dry Run Mode.
