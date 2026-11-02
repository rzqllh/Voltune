# Changelog

All notable changes to Voltune are documented here.

## [2.0.0-NextGen] - 2026-11-02

### Added
- **Instant Web One-Liner (`voltune.ps1`):** Native standalone PowerShell toolkit executable via `irm ... | iex` with automatic UAC self-elevation.
- **Hardware-Aware Detection Engine:** CIM-based and `nvidia-smi`-based detection of Intel Hybrid P+E / AMD Ryzen CPU, Dual GPU (NVIDIA & AMD/Intel), precise VRAM & TGP wattage, screen resolution & refresh rate, and HAGS status.
- **VoltPlay (Game Auto-Configurator):**
  - Red Dead Redemption 2 `system.xml` tuning: `asyncComputeEnabled`, `transferQueuesEnabled`, `maxTexUpgradesPerFrame = 10`.
  - Honkai: Star Rail registry tuning: `LightQuality` and `ReflectionQuality` balanced to High (4) to eliminate Penacony 45W thermal throttle.
  - Genshin Impact registry tuning: `Crowd Density` balanced to Medium and `Shadow Quality` to High to prevent CPU frame spikes in Fontaine/Natlan.
  - The Witcher 3: Wild Hunt Next-Gen `dx12user.settings` tuning: `AllowDLSSG=true`, `HairWorksLevel=0`, adaptive framerate cap.
- **VoltClean (Safe Disk & Cache Cleaner):** Safe cleanup of `%TEMP%`, `C:\Windows\Temp`, DirectX `D3DSCache`, NVIDIA `DXCache` & `GLCache`, crash dumps, and Recycle Bin with running process guards (Chrome, active games).
- **VoltUndo (1-Click System & Game Rollback):** Automatic registry snapshot export (`.reg`) and game config backups (`.bak` & snapshot copies) in `%LOCALAPPDATA%\Voltune\Backups\` with complete one-click restoration.
- **Advanced Maintenance Tools:** Interactive DNS latency benchmark (Cloudflare, Google, Quad9), Windows Power Plan switcher (Ultimate Performance, High, Balanced), SFC scannow, DISM RestoreHealth, and Appx bloatware inventory.

## [0.2.2] - 2026-08-31

### Fixed
- Fixed Windows filesystem safety policy treating the system drive root (`C:\\`) as a protected ancestor of every user path. This incorrectly blocked Developer Cleanup, Disk Analyzer deletions, and test temp paths on Windows.
- Fixed `FilesystemSafety(protected_paths=[])` semantics so an explicit empty list disables default protected paths instead of silently re-adding them. `None` remains the signal to use Voltune's default Windows protections.
- Added cross-platform regression coverage for explicit protected-path overrides and verified the default policy no longer needs the drive root because filesystem roots are already blocked independently.

## [0.2.1] - 2026-08-31

### Fixed
- Fixed PyInstaller startup failure (`ModuleNotFoundError: No module named `voltune``) caused by the top-level `voltune.py` launcher shadowing the real `src/voltune` package during analysis.
- Replaced the ambiguous launcher with `run_voltune.py` and added a checked-in `Voltune.spec`.
- Added `build.ps1` so Windows builds run tests, compile checks, clean stale output, and build from the canonical spec.
- Added regression tests preventing the shadowing launcher from returning.

## [0.2.0] - 2026-08-31

### Added
- Centralized filesystem safety engine with protected roots, whitelist support, reparse-point blocking, narrow cleanup scopes, dry-run, size estimation, and verification.
- Interactive Disk Analyzer and large-file finder.
- Developer Cleanup with recent-project protection and support for common Node.js, Python, framework, Rust, Gradle, and build artifacts.
- Installer Cleanup with age/size thresholds and conservative archive detection.
- Smart Uninstaller desktop inventory, registered-uninstaller launch, MSI uninstall normalization, and HIGH/MEDIUM leftover preview.
- Live System Monitor.
- Direct CLI commands for status, analyze, dev-clean, installers, apps, and history.
- JSON output and NDJSON streaming for automation/agent use.
- Persistent Protected Paths configuration and interactive manager.
- Modular `core/` and `features/` packages for new functionality.

### Changed
- Source and installed console entry points now route through `voltune.cli` while the no-argument experience remains the interactive menu.
- Existing Storage Cleanup filesystem mutations now pass the centralized safety engine.
- Version bumped to 0.2.0 for the vNext feature set.

### Verification
- Added regression tests for safety roots/whitelists/symlinks, dry-run deletion, recent developer projects, conservative archive classification, MSI uninstall normalization, CLI exposure, and contiguous menu numbering.

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
