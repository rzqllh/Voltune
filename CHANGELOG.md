# Changelog

All notable changes to Voltune are documented here.

## [3.3.0-Universal] - 2026-11-02

### Added
- **Atomic Tweaks Execution Engine:** Replaced coarse, grouped tweak executions with a granular per-item execution engine (`Set-VoltAtomicTweak`). Selecting specific checkboxes now applies or reverts only those exact settings without touching unselected categories.
- **Clean Preset Blueprint Matrix:** Presets (`Recommended`, `Laptop Gaming`, `Desktop Max`, `Minimal Privacy`) now explicitly specify `$true`/`$false` across all 21 tweak items, ensuring choosing a new preset cleanly overwrites previous selections without checkbox accumulation.
- **Dynamic Live OS State Inspection:** On GUI launch, `Get-VoltLiveTweakStates` queries Windows registry and system configurations in real-time, automatically checking only the tweaks that are currently active on the host OS.
- **Clear All Tweaks Toggle:** Added a 1-click `Clear All` button (`btnClearTweaks`) to instantly deselect all checkboxes.
- **Curated Post-Install Software Catalog (Chris Titus Style - 9 Categories):**
  - Expanded WinGet software catalog with essential tools for fresh Windows installations:
    - *Game Runtimes & Libraries:* Visual C++ 2005-2022 AIO (`VisualCppRedist AIO`), DirectX End-User Runtimes, .NET 8 Desktop Runtime.
    - *Utilities & Archive:* NanaZip (modern Win11 context menu), 7-Zip, WinRAR, PowerToys, Everything Search, Process Hacker / System Informer, BleachBit.
    - *Gaming Launchers & Overlays:* Steam, Epic Games, GOG Galaxy, EA App, Ubisoft Connect, Battle.net, Discord, OBS Studio, RivaTuner Statistics Server (RTSS), MSI Afterburner.
    - *Hardware Drivers & Monitoring:* NVIDIA App, HWiNFO64, CPU-Z, GPU-Z.
    - *Developer Tools:* VS Code, Git, PowerShell 7, Windows Terminal, Docker Desktop, Node.js LTS, Python 3.
    - *Browsers:* Brave, Google Chrome, Mozilla Firefox, Microsoft Edge Dev.
    - *Social & Media:* Telegram Desktop, WhatsApp, Spotify, VLC Media Player, HandBrake.
- **Interactive Live App Search (`txtAppSearch`):** Real-time text filter that dynamically searches the software catalog by application name or WinGet ID as the user types.
- **Asynchronous Background App Installer:** WinGet batch installations now execute asynchronously without freezing the WPF window, streaming stdout directly to the in-GUI activity console.
- **Universal Dynamic Game Tuner Cards:**
  - Removed static 4-game hardcoded XAML controls.
  - Dynamically scans and generates interactive WPF card containers for all detected games across Steam (`libraryfolders.vdf`), HoYoPlay, Epic, GOG, Ubisoft, and standalone game directories.
  - Generates per-game toggles for GPU Discrete High Performance, Windows Defender Exclusion (eliminating streaming micro-stutters), and engine-specific config tweaks.
  - Added **Tambah Game Manual (.exe)** button with file browser dialog to register portable/custom games on the fly.
- **Dark Fluent GUI Overhaul:**
  - Modern dark Fluent palette (`#0F172A` background, `#1E293B` cards, `#38BDF8` cyan accents, `#3B82F6` primary buttons).
  - 6 Visual System Telemetry Cards in Dashboard (CPU Hybrid P+E, GPU VRAM & TGP, Power Plan, Display & VRR FPS target, RAM, and Multi-Drive Storage).
  - Sticky bottom action bars on all tabs to prevent controls from scrolling out of view.
- **Zero CLI Prompt Default Mode:** Launching `.\voltune.ps1` defaults to the native WPF GUI without prompting in the console. Interactive CLI is preserved via `.\voltune.ps1 -CLI`.

### Fixed
- **GPU VRAM UInt32 Overflow:** Fixed WMI `AdapterRAM` clamping GPUs with >4GB VRAM to 4GB (4,294,967,295 bytes). Now detects accurate VRAM (e.g., RTX 4060 8.0 GB) via multi-path `nvidia-smi` and registry fallback.
- **NVIDIA SMI Multi-Path Detection:** Added checks for `C:\Windows\System32\nvidia-smi.exe` used by Windows 11 DCH drivers in addition to `Program Files`.
- **Laptop TGP Query Crash:** Fixed `nvidia-smi --query-gpu=power.limit` returning `[N/A]` on laptops by querying `enforced.power.limit`, accurately reporting laptop GPU TGP (e.g., 45W).
- **Preset Checkbox Accumulation:** Selecting a new preset now unchecks items not included in that preset.
- **`Select-Object: Property "Name" cannot be found`:** Fixed pipeline error in `Show-VoltSpecs` when parsing `OrderedDictionary` objects from `$hw.DiscoveredGames.Values`.
- **PowerShell 5.1 UTF-8 BOM Parsing:** Standardized UTF-8 with BOM (`utf-8-sig`) across `.ps1` files to prevent non-ASCII characters from causing ampersand syntax errors in Windows PowerShell 5.1.

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
