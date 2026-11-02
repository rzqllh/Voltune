# Changelog

All notable changes to Voltune are documented here.

## [3.1.0-Universal] - 2026-11-02

### Added
- **100% In-GUI Architecture (Zero CLI Prompts):** Overhauled `Show-VoltGUI` so every workflow (tweaks, software installation, debloater, disk cleanup, repair diagnostics, snapshot rollback) operates strictly within the native desktop window. Zero terminal typing or `Read-Host` prompts while GUI is running.
- **Customizable Tweaks with Presets (Chris Titus Style):** 21 granular tweak checkboxes across Gaming, QoL, Privacy, Services, and Updates paired with 1-click presets (`Recommended`, `Laptop Gaming`, `Desktop Max`, `Minimal Privacy`, `Clear All`). Users can toggle any item before clicking `Run Selected Tweaks` or `Undo Selected Tweaks`.
- **WinGet Multi-Select Application Catalog (Chris Titus Style):** 21 popular software packages categorized into 3 columns (Game Runtimes, Gaming & Launchers, Dev Tools, System Utilities, Web Browsers) with preset buttons (`All Runtimes`, `Gaming Bundle`, `Dev Tools`, `Web Browsers`) and 1-click background WinGet installer.
- **Embedded Real-Time Activity Log:** Bottom activity console in GUI streaming live timestamps, execution progress, and status without UI freezing.
- **In-GUI Snapshot Rollback & Debloater:** ComboBox snapshot browser with 1-click restoration confirmation dialog, and integrated UWP Appx debloater.

## [3.0.0-Ultimate] - 2026-11-02

### Added
- **Modern Native WPF Desktop GUI (`Show-VoltGUI`):** Built-in dark mode WPF desktop window launched via `.\voltune.ps1 -GUI` or hotkey `[G]`, featuring real-time hardware telemetry, tabbed categories (Dashboard, Gaming, QoL & Privacy, Software, VoltClean, System Health, VoltUndo) with zero external binary dependencies.
- **TCP/IP Gaming Latency Optimizer (Zero-VPN Harm):** Nagle's Algorithm disabled (`TcpAckFrequency = 1`, `TCPNoDelay = 1`) on active physical Ethernet & Wi-Fi adapters with strict whitelist protection for Palo Alto GlobalProtect (`PanGPS`), VPNs, and virtual adapters; network throttling disabled (`NetworkThrottlingIndex = 0xFFFFFFFF`, `SystemResponsiveness = 0`).
- **Windows Services Optimizer:** Safe gaming profile setting non-essential background services (`DiagTrack`, `dmwappushservice`, `MapsBroker`, `lfsvc`, `RemoteRegistry`, `RetailDemo`, `WerSvc`, `Xbox` services) to Manual/Disabled with explicit preservation of audio, printing, and VPN services.
- **Windows Update Control (Security Updates Only):** 365-day feature update deferral, driver hijack prevention (`ExcludeWUDriversInQualityUpdate = 1`), unexpected restart prevention (`NoAutoRebootWithLoggedOnUsers = 1`), and active hours maximized.
- **Deep Windows 11 Privacy & Anti-Bloat:** System-wide disabling of Windows Recall AI screen capture, Copilot, Cortana, Bing search suggestions in Start, advertising IDs, activity history, and delivery optimization P2P upload.
- **Software Catalog & Game Runtimes Installer (WinGet):** 1-click installer for Visual C++ 2005-2022 AIO, DirectX End-User Runtimes, .NET Desktop Runtime 8, plus curated suites for Gaming (Steam, Epic, Discord, OBS, RTSS), Development (VS Code, Git, Terminal), and System Utilities.
- **Windows Optional Features Manager:** 1-click toggles for DirectPlay (legacy gaming runtime), WSL2, and Windows Sandbox.
- **System Health & Diagnostic Suite:** SFC scannow, DISM Online RestoreHealth, DISM Component Store ResetBase, 1-click Windows Update reset, 1-click Network/Winsock repair, Icon/Thumbnail cache rebuild, and Standby Memory working set trim.
- **System Restore Point Automation:** Automatic creation of Windows System Restore points (`Checkpoint-Computer`) prior to running batch optimizations.

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
