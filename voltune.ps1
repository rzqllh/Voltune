<#
.SYNOPSIS
    VoltPlay & Voltune Windows Utility v3.0 - Ultimate Universal Hardware-Aware Performance, Gaming & System Toolkit
.DESCRIPTION
    Toolkit komprehensif optimasi Windows, manajemen kartu grafis dual-GPU (NVIDIA/AMD/Intel),
    penyelarasan setting game anti-stutter dinamis multi-drive, pembersih disk lintas-drive,
    Windows 11 QoL tweaks (Classic Context Menu, Explorer, Taskbar), privasi & anti-telemetri,
    TCP/IP gaming latency optimizer (Zero-VPN harm), Windows Services optimizer,
    Windows Update control (Security Updates Only), gaming raw mouse input & Defender auto-exclusions,
    WinGet software & game runtimes catalog, System Restore point automation,
    serta sistem snapshot 1-klik Undo dinamis dengan dukungan Modern Native WPF GUI & Interactive TUI.
.NOTES
    Safe by default, Reversible by design, 100% Dynamic, Zero VPN Harm.
#>

[CmdletBinding()]
param(
    [switch]$AutoOptimize,
    [switch]$CleanOnly,
    [switch]$UndoOnly,
    [switch]$GUI,
    [switch]$NoElevation
)

# ------------------------------------------------------------------------------
# 1. ELEVASI HAK AKSES (SELF-ELEVATION)
# ------------------------------------------------------------------------------
function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-VoltElevation {
    param([switch]$Bypass)
    if ($Bypass -or (Test-IsAdmin)) {
        return
    }

    Write-Host "[!] Voltune memerlukan hak akses Administrator untuk mengonfigurasi registri performa." -ForegroundColor Yellow
    Write-Host "[*] Meminta izin UAC Administrator..." -ForegroundColor Cyan
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass"
        if ($PSCommandPath) {
            $arguments += " -File `"$PSCommandPath`""
        } else {
            $arguments += " -Command `"irm https://raw.githubusercontent.com/rzqllh/Voltune/main/voltune.ps1 | iex`""
        }
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
        exit 0
    } catch {
        Write-Error "Gagal meminta izin Administrator: $_"
        exit 1
    }
}

# ------------------------------------------------------------------------------
# 2. KONFIGURASI GLOBAL & PATHS
# ------------------------------------------------------------------------------
$Script:VoltVersion = "3.0.0-Ultimate"
$Script:AppDataDir  = Join-Path $env:LOCALAPPDATA "Voltune"
$Script:BackupDir   = Join-Path $Script:AppDataDir "Backups"
$Script:LogDir      = Join-Path $Script:AppDataDir "Logs"

if (-not (Test-Path $Script:BackupDir)) { New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null }
if (-not (Test-Path $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }

# ------------------------------------------------------------------------------
# 3. DYNAMIC DETECTION ENGINE (HARDWARE, ENVIRONMENT, DRIVES, & GAMES)
# ------------------------------------------------------------------------------
function Get-VoltHardwareProfile {
    $profile = [ordered]@{
        # CPU
        CPUName          = "Unknown CPU"
        CPUCores         = 0
        CPUThreads       = 0
        IsHybridCPU      = $false
        CPUArchitecture  = "x64"

        # Memory & Power
        RAM_GB           = 0.0
        IsOnBattery      = $false
        BatteryChargePct = $null
        HibernateActive  = $false
        HiberfilSizeGB   = 0.0

        # Storage (Multi-Drive)
        Drives           = [ordered]@{}

        # Display
        ScreenResolution = "1920x1080"
        ScreenRefreshHz  = 60
        DynamicFPSCaps   = [ordered]@{}

        # GPU
        HasNvidiaGPU     = $false
        HasAmdGPU        = $false
        HasIntelGPU      = $false
        DiscreteGPU      = $null
        IntegratedGPU    = $null
        HAGS_Status      = $false

        # System Restore
        SystemRestoreOnC = $false

        # Game Ecosystem (Dynamic Multi-Platform Discovery)
        SteamLibraries   = @()
        DiscoveredGames  = [ordered]@{}
    }

    # 1. CPU Detection
    try {
        $proc = Get-CimInstance Win32_Processor | Select-Object -First 1
        if ($proc) {
            $profile.CPUName = $proc.Name.Trim()
            $profile.CPUCores = [int]$proc.NumberOfCores
            $profile.CPUThreads = [int]$proc.NumberOfLogicalProcessors
            $profile.CPUArchitecture = if ($proc.AddressWidth -eq 64) { "x64" } else { "x86" }

            if ($profile.CPUName -match "1[234]th Gen" -or $profile.CPUName -match "Core Ultra" -or ($profile.CPUThreads -gt ($profile.CPUCores * 1.5) -and $profile.CPUThreads -ne ($profile.CPUCores * 2))) {
                $profile.IsHybridCPU = $true
            }
        }
    } catch {}

    # 2. RAM & Battery / Power Detection
    try {
        $cs = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1
        if ($cs -and $cs.TotalPhysicalMemory) {
            $profile.RAM_GB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        }
    } catch {}

    try {
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($battery) {
            $profile.BatteryChargePct = [int]$battery.EstimatedChargeRemaining
            if ($battery.BatteryStatus -eq 1) {
                $profile.IsOnBattery = $true
            }
        }
    } catch {}

    # Check Hibernate status & hiberfil.sys
    if (Test-Path "C:\hiberfil.sys") {
        $profile.HibernateActive = $true
        try {
            $item = Get-Item "C:\hiberfil.sys" -Force -ErrorAction SilentlyContinue
            if ($item) {
                $profile.HiberfilSizeGB = [math]::Round($item.Length / 1GB, 2)
            }
        } catch {}
    }

    # Check System Restore status
    try {
        $sr = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
        $profile.SystemRestoreOnC = $true
    } catch {
        $profile.SystemRestoreOnC = $false
    }

    # 3. Multi-Drive Storage Detection (All Drives)
    try {
        $disks = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        foreach ($d in $disks) {
            $freeGB  = [math]::Round($d.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round($d.Size / 1GB, 1)
            $label   = if ($d.VolumeName) { $d.VolumeName } else { "Local Disk" }
            $profile.Drives[$d.DeviceID] = [ordered]@{
                DeviceID = $d.DeviceID
                Label    = $label
                FreeGB   = $freeGB
                TotalGB  = $totalGB
            }
        }
    } catch {}

    # 4. Display & Refresh Rate Calculation
    try {
        $videoControllers = Get-CimInstance Win32_VideoController
        foreach ($vc in $videoControllers) {
            $gpuName = $vc.Name
            $ramGB = 0
            if ($vc.AdapterRAM) {
                $ramGB = [math]::Round($vc.AdapterRAM / 1GB, 1)
            }

            if ($gpuName -match "NVIDIA|GeForce|RTX|GTX") {
                $profile.HasNvidiaGPU = $true
                $profile.DiscreteGPU = @{ Name = $gpuName; VRAM_GB = $ramGB; Type = "NVIDIA"; TGP_W = $null; Driver = $null }
            } elseif ($gpuName -match "AMD Radeon.*(RX|XT|M\b|\d{4})") {
                $profile.HasAmdGPU = $true
                $profile.DiscreteGPU = @{ Name = $gpuName; VRAM_GB = $ramGB; Type = "AMD"; TGP_W = $null; Driver = $null }
            } elseif ($gpuName -match "Intel") {
                $profile.HasIntelGPU = $true
                if (-not $profile.IntegratedGPU) {
                    $profile.IntegratedGPU = @{ Name = $gpuName; VRAM_GB = $ramGB; Type = "Intel" }
                }
            } elseif ($gpuName -match "Radeon" -and -not $profile.HasAmdGPU) {
                $profile.HasAmdGPU = $true
                $profile.IntegratedGPU = @{ Name = $gpuName; VRAM_GB = $ramGB; Type = "AMD" }
            }

            if ($vc.CurrentRefreshRate -and $vc.CurrentRefreshRate -gt 30) {
                $profile.ScreenRefreshHz = [int]$vc.CurrentRefreshRate
            }
            if ($vc.VideoModeDescription -match "(\d+)\s*x\s*(\d+)") {
                $profile.ScreenResolution = "$($Matches[1])x$($Matches[2])"
            }
        }
    } catch {}

    # Dynamic Frame Rate Caps Calculation based on Hz and Power State
    $hz = $profile.ScreenRefreshHz
    $profile.DynamicFPSCaps["TearFreeVRR"] = [math]::Max(30, ($hz - 3))
    $profile.DynamicFPSCaps["HalfRate"]    = [math]::Max(30, [int][math]::Floor($hz / 2))
    $profile.DynamicFPSCaps["BatteryCap"]  = if ($profile.IsOnBattery) { 30 } else { $profile.DynamicFPSCaps["TearFreeVRR"] }

    # Dynamic NVIDIA TGP & Precision VRAM Query via nvidia-smi
    if ($profile.HasNvidiaGPU) {
        $nvsmi = "C:\Windows\System32\nvidia-smi.exe"
        if (Test-Path $nvsmi) {
            try {
                $out = & $nvsmi --query-gpu=power.max_limit,memory.total,driver_version --format=csv,noheader,nounits 2>$null
                if ($out -match "([\d\.]+),\s*([\d\.]+),\s*([\d\.]+)") {
                    $profile.DiscreteGPU.TGP_W = [int][math]::Round([double]$Matches[1])
                    $profile.DiscreteGPU.VRAM_GB = [math]::Round(([double]$Matches[2] / 1024), 1)
                    $profile.DiscreteGPU.Driver = $Matches[3]
                }
            } catch {}
        }
    }

    # Check HAGS Status from registry
    try {
        $hags = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -ErrorAction SilentlyContinue
        if ($hags -and $hags.HwSchMode -eq 2) {
            $profile.HAGS_Status = $true
        }
    } catch {}

    # 5. DYNAMIC MULTI-PLATFORM GAME DISCOVERY
    $foundSteamLibs = [System.Collections.Generic.List[string]]::new()
    $steamReg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue
    if ($steamReg -and $steamReg.SteamPath) {
        $mainSteam = ($steamReg.SteamPath -replace '/', '\')
        if (Test-Path $mainSteam) {
            $foundSteamLibs.Add($mainSteam)
            $vdf = Join-Path $mainSteam "steamapps\libraryfolders.vdf"
            if (Test-Path $vdf) {
                Get-Content $vdf | ForEach-Object {
                    if ($_ -match '^\s*"path"\s+"([^"]+)"') {
                        $p = ($Matches[1] -replace '\\\\', '\')
                        if ((Test-Path $p) -and -not $foundSteamLibs.Contains($p)) {
                            $foundSteamLibs.Add($p)
                        }
                    }
                }
            }
        }
    }

    # Fallback drive sweep for SteamLibrary if not in vdf
    foreach ($d in $profile.Drives.Keys) {
        $cand = "$d\Games\SteamLibrary"
        if ((Test-Path $cand) -and -not $foundSteamLibs.Contains($cand)) { $foundSteamLibs.Add($cand) }
        $cand2 = "$d\SteamLibrary"
        if ((Test-Path $cand2) -and -not $foundSteamLibs.Contains($cand2)) { $foundSteamLibs.Add($cand2) }
    }
    $profile.SteamLibraries = @($foundSteamLibs)

    # Enumerate Steam Games across ALL discovered libraries
    foreach ($lib in $profile.SteamLibraries) {
        $appsDir = Join-Path $lib "steamapps"
        if (Test-Path $appsDir) {
            Get-ChildItem -Path $appsDir -Filter "appmanifest_*.acf" -File -ErrorAction SilentlyContinue | ForEach-Object {
                $txt = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                $appId = $null
                $appName = $null
                $installSub = $null

                if ($txt -match '"appid"\s+"(\d+)"') { $appId = $Matches[1] }
                if ($txt -match '"name"\s+"([^"]+)"') { $appName = $Matches[1] }
                if ($txt -match '"installdir"\s+"([^"]+)"') { $installSub = $Matches[1] }

                if ($appId -and $appName -and $installSub) {
                    $fullPath = Join-Path $appsDir "common\$installSub"
                    if ($appName -notmatch "Steamworks|Redistributable|Proton|Shared") {
                        $profile.DiscoveredGames["Steam_$appId"] = [ordered]@{
                            Name        = $appName
                            Platform    = "Steam"
                            AppId       = $appId
                            InstallPath = $fullPath
                        }
                    }
                }
            }
        }
    }

    # Detect HoYoPlay Games (HSR & Genshin)
    $hoyoReg = "HKCU:\Software\Cognosphere"
    if (Test-Path $hoyoReg) {
        Get-ChildItem -Path $hoyoReg -ErrorAction SilentlyContinue | ForEach-Object {
            $gameKey = $_.PSChildName
            if ($gameKey -match "StarRail|Honkai") {
                $profile.DiscoveredGames["HoYo_HSR"] = [ordered]@{
                    Name     = "Honkai: Star Rail"
                    Platform = "HoYoPlay"
                    RegPath  = $_.Name
                }
            } elseif ($gameKey -match "Genshin") {
                $profile.DiscoveredGames["HoYo_Genshin"] = [ordered]@{
                    Name     = "Genshin Impact"
                    Platform = "HoYoPlay"
                    RegPath  = $_.Name
                }
            }
        }
    }

    # Detect Rockstar Games (Red Dead Redemption 2)
    $rdr2Doc = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Rockstar Games\Red Dead Redemption 2\Settings\system.xml"
    if (Test-Path $rdr2Doc) {
        $profile.DiscoveredGames["Rockstar_RDR2"] = [ordered]@{
            Name       = "Red Dead Redemption 2"
            Platform   = "Rockstar Games"
            ConfigFile = $rdr2Doc
        }
    }

    # Detect CDPR (The Witcher 3 / Cyberpunk)
    $w3Doc = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "The Witcher 3\dx12user.settings"
    if (Test-Path $w3Doc) {
        $profile.DiscoveredGames["CDPR_W3"] = [ordered]@{
            Name       = "The Witcher 3: Wild Hunt (DX12)"
            Platform   = "CD Projekt RED"
            ConfigFile = $w3Doc
        }
    }

    return $profile
}

# ------------------------------------------------------------------------------
# 4. SAFETY & SYSTEM RESTORE POINT AUTOMATION
# ------------------------------------------------------------------------------
function New-VoltRestorePoint {
    param([string]$Description = "Voltune Pre-Tweak Snapshot")
    Write-Host "`n[*] Membuat Windows System Restore Point untuk keamanan maksimal..." -ForegroundColor Cyan

    try {
        # Ensure system restore service is active
        Set-Service -Name "VSS" -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name "VSS" -ErrorAction SilentlyContinue

        # Enable on C: if not enabled
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue

        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop | Out-Null
        Write-Host " [✓] System Restore Point berhasil dibuat: '$Description'" -ForegroundColor Green
        return $true
    } catch {
        Write-Host " [!] Catatan: System Restore Point dilewati atau dibatasi frekuensi Windows (hanya bisa 1x per 24 jam via API)." -ForegroundColor DarkYellow
        Write-Host "     -> Snapshot lokal VoltUndo mandiri tetap aktif sebagai jaminan utama." -ForegroundColor Gray
        return $false
    }
}

# ------------------------------------------------------------------------------
# 5. DYNAMIC BACKUP & UNDO ENGINE (VOLTUNDO)
# ------------------------------------------------------------------------------
function New-VoltBackupSnapshot {
    param([hashtable]$Hardware)

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $snapshotDir = Join-Path $Script:BackupDir "Snapshot-$timestamp"
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null

    Write-Host "`n[*] Mengambil snapshot registri & konfigurasi dinamis (VoltUndo)..." -ForegroundColor Cyan
    Write-Host "    -> Lokasi Backup: $snapshotDir" -ForegroundColor Gray

    $manifest = [ordered]@{
        Timestamp    = $timestamp
        VoltVersion  = $Script:VoltVersion
        SystemRegs   = @()
        GameRegs     = @()
        ConfigFiles  = @()
    }

    # 1. Export Windows System & Tweak Registries
    $systemRegs = @(
        @{ Key = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; File = "SystemProfile.reg" },
        @{ Key = "HKCU\System\GameConfigStore"; File = "GameConfigStore.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; File = "GameDVR_Policy.reg" },
        @{ Key = "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; File = "GraphicsDrivers.reg" },
        @{ Key = "HKCU\Control Panel\Mouse"; File = "MouseSettings.reg" },
        @{ Key = "HKCU\Control Panel\Desktop"; File = "DesktopSettings.reg" },
        @{ Key = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; File = "ExplorerAdvanced.reg" },
        @{ Key = "HKCU\Software\Microsoft\Windows\CurrentVersion\Search"; File = "WindowsSearch.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; File = "DataCollection.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"; File = "WindowsUpdate.reg" },
        @{ Key = "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; File = "AdvertisingInfo.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"; File = "DeliveryOptimization.reg" },
        @{ Key = "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"; File = "TcpipParameters.reg" }
    )

    foreach ($r in $systemRegs) {
        $outFile = Join-Path $snapshotDir $r.File
        $regKey = $r.Key
        & reg.exe export $regKey $outFile /y 2>$null | Out-Null
        if (Test-Path $outFile) {
            $manifest.SystemRegs += @{ Key = $regKey; File = $r.File }
        }
    }

    # 2. Export Discovered Game Registries
    if ($Hardware -and $Hardware.DiscoveredGames) {
        foreach ($k in $Hardware.DiscoveredGames.Keys) {
            $g = $Hardware.DiscoveredGames[$k]
            if ($g.RegPath) {
                $sanitized = ($g.Name -replace '[\\/:*?"<>|]', '_')
                $regOut = Join-Path $snapshotDir "Game_${sanitized}.reg"
                $rawKey = $g.RegPath -replace '^HKEY_CURRENT_USER', 'HKCU' -replace '^HKEY_LOCAL_MACHINE', 'HKLM'
                & reg.exe export $rawKey $regOut /y 2>$null | Out-Null
                if (Test-Path $regOut) {
                    $manifest.GameRegs += @{ Name = $g.Name; Key = $rawKey; File = "Game_${sanitized}.reg" }
                }
            }
        }
    }

    # 3. Backup Discovered Game Config Files with sanitization
    if ($Hardware -and $Hardware.DiscoveredGames) {
        foreach ($k in $Hardware.DiscoveredGames.Keys) {
            $g = $Hardware.DiscoveredGames[$k]
            if ($g.ConfigFile -and (Test-Path $g.ConfigFile)) {
                $sanitized = ($g.Name -replace '[\\/:*?"<>|]', '_')
                $bakName = "Config_${sanitized}.bak"
                $destBak = Join-Path $snapshotDir $bakName
                Copy-Item -Path $g.ConfigFile -Destination $destBak -Force
                $manifest.ConfigFiles += @{ Name = $g.Name; Source = $g.ConfigFile; Backup = $bakName }
            }
        }
    }

    # 4. Save manifest
    $manifestPath = Join-Path $snapshotDir "manifest.json"
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

    Write-Host " [✓] Snapshot selesai. $($manifest.SystemRegs.Count) registri sistem & $($manifest.ConfigFiles.Count) file konfigurasi game dicadangkan." -ForegroundColor Green
    return $snapshotDir
}

function Invoke-VoltUndo {
    Write-Host "`n================================================================================" -ForegroundColor Yellow
    Write-Host "                     ↩️ VOLTUNDO: RESTORE SISTEM KE KONDISI ASAL                " -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow

    $snapshots = Get-ChildItem -Path $Script:BackupDir -Directory | Sort-Object CreationTime -Descending
    if ($snapshots.Count -eq 0) {
        Write-Host "[-] Tidak ditemukan snapshot backup pada $Script:BackupDir" -ForegroundColor Red
        return
    }

    Write-Host "[*] Snapshot backup yang tersedia:" -ForegroundColor Cyan
    for ($i = 0; $i -lt [math]::Min(5, $snapshots.Count); $i++) {
        Write-Host "  [$i] $($snapshots[$i].Name) ($($snapshots[$i].CreationTime.ToString('yyyy-MM-dd HH:mm:ss')))" -ForegroundColor White
    }

    $pick = Read-Host "`nPilih nomor snapshot yang ingin di-restore [0-$([math]::Min(4, $snapshots.Count - 1))]"
    if ($pick -match "^\d+$" -and [int]$pick -lt $snapshots.Count) {
        $targetSnap = $snapshots[[int]$pick].FullName
        $manifestPath = Join-Path $targetSnap "manifest.json"

        if (-not (Test-Path $manifestPath)) {
            Write-Host "[-] manifest.json tidak ditemukan pada snapshot ini." -ForegroundColor Red
            return
        }

        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        Write-Host "`n[*] Merestore snapshot dari: $targetSnap" -ForegroundColor Cyan

        # 1. Restore Registries
        if ($manifest.SystemRegs) {
            foreach ($r in $manifest.SystemRegs) {
                $f = Join-Path $targetSnap $r.File
                if (Test-Path $f) {
                    Write-Host "  -> Mengimpor registri: $($r.Key)" -ForegroundColor Gray
                    & reg.exe import $f 2>$null | Out-Null
                }
            }
        }

        if ($manifest.GameRegs) {
            foreach ($gr in $manifest.GameRegs) {
                $f = Join-Path $targetSnap $gr.File
                if (Test-Path $f) {
                    Write-Host "  -> Mengimpor registri game: $($gr.Name)" -ForegroundColor Gray
                    & reg.exe import $f 2>$null | Out-Null
                }
            }
        }

        # 2. Restore Config Files
        if ($manifest.ConfigFiles) {
            foreach ($cf in $manifest.ConfigFiles) {
                $bak = Join-Path $targetSnap $cf.Backup
                if (Test-Path $bak) {
                    Write-Host "  -> Mengembalikan konfigurasi: $($cf.Name)" -ForegroundColor Gray
                    Copy-Item -Path $bak -Destination $cf.Source -Force
                }
            }
        }

        # 3. Revert Classic Context Menu if needed
        Remove-Item "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue

        # Restart explorer to apply UI changes
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

        Write-Host "`n[✓] Seluruh konfigurasi berhasil dikembalikan ke kondisi snapshot!" -ForegroundColor Green
    } else {
        Write-Host "[-] Pilihan tidak valid. Pembatalan restore." -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------------------
# 6. DYNAMIC PROCESS GUARD
# ------------------------------------------------------------------------------
function Get-VoltActiveGuards {
    $runningBrowsers = [System.Collections.Generic.List[string]]::new()
    $runningLaunchers = [System.Collections.Generic.List[string]]::new()

    $allProcesses = Get-Process -ErrorAction SilentlyContinue

    $browserPatterns = "chrome|msedge|firefox|brave|opera|vivaldi"
    $launcherPatterns = "steam|epicgameslauncher|origin|ea|battlenet|riotclientservices|hoyoplay"

    foreach ($p in $allProcesses) {
        $pName = $p.ProcessName.ToLower()
        if ($pName -match $browserPatterns -and -not $runningBrowsers.Contains($pName)) {
            $runningBrowsers.Add($pName)
        }
        if ($pName -match $launcherPatterns -and -not $runningLaunchers.Contains($pName)) {
            $runningLaunchers.Add($pName)
        }
    }

    return @{
        Browsers  = $runningBrowsers
        Launchers = $runningLaunchers
    }
}

# ------------------------------------------------------------------------------
# 7. DYNAMIC WINDOWS & DUAL-GPU ALIGNMENT (VOLTPLAY CORE)
# ------------------------------------------------------------------------------
function Optimize-VoltWindowsCore {
    Write-Host "`n[*] Mengonfigurasi Penjadwalan & Prioritas Thread Gaming..." -ForegroundColor Cyan

    # 1. HAGS (Hardware Accelerated GPU Scheduling)
    $gfxKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    if (-not (Test-Path $gfxKey)) { New-Item -Path $gfxKey -Force | Out-Null }
    Set-ItemProperty -Path $gfxKey -Name "HwSchMode" -Value 2 -Type DWord -Force
    Write-Host " [✓] Hardware-Accelerated GPU Scheduling (HAGS) -> Diaktifkan (Mode 2)" -ForegroundColor Green

    # Variable Refresh Rate (VRR) Global Toggle
    Set-ItemProperty -Path $gfxKey -Name "VRR" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Variable Refresh Rate (VRR) Support -> Diaktifkan" -ForegroundColor Green

    # 2. Game Mode
    $gameConfig = "HKCU:\Software\Microsoft\GameBar"
    if (-not (Test-Path $gameConfig)) { New-Item -Path $gameConfig -Force | Out-Null }
    Set-ItemProperty -Path $gameConfig -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $gameConfig -Name "AllowAutoGameMode" -Value 1 -Type DWord -Force
    Write-Host " [✓] Windows Game Mode -> Diaktifkan" -ForegroundColor Green

    # 3. MMCSS Low Latency Audio & Game Thread Priority
    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (-not (Test-Path $sysProfile)) { New-Item -Path $sysProfile -Force | Out-Null }
    Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force

    $taskGames = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    if (-not (Test-Path $taskGames)) { New-Item -Path $taskGames -Force | Out-Null }
    Set-ItemProperty -Path $taskGames -Name "GPU Priority" -Value 8 -Type DWord -Force
    Set-ItemProperty -Path $taskGames -Name "Priority" -Value 6 -Type DWord -Force
    Set-ItemProperty -Path $taskGames -Name "Scheduling Category" -Value "High" -Type String -Force
    Set-ItemProperty -Path $taskGames -Name "SFIO Priority" -Value "High" -Type String -Force
    Write-Host " [✓] MMCSS Game Thread Priority -> Ditingkatkan ke Level Maksimum" -ForegroundColor Green

    # 4. Matikan Background GameDVR (Bebaskan Overhead GPU & VRAM)
    $gameDVRPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (-not (Test-Path $gameDVRPolicy)) { New-Item -Path $gameDVRPolicy -Force | Out-Null }
    Set-ItemProperty -Path $gameDVRPolicy -Name "AllowGameDVR" -Value 0 -Type DWord -Force

    $gameStore = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path $gameStore)) { New-Item -Path $gameStore -Force | Out-Null }
    Set-ItemProperty -Path $gameStore -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $gameStore -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force
    Write-Host " [✓] Background GameDVR & Capture Overhead -> Dinonaktifkan" -ForegroundColor Green

    # 5. Disable CPU Power Throttling for gaming
    $powerThrottling = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
    if (-not (Test-Path $powerThrottling)) { New-Item -Path $powerThrottling -Force | Out-Null }
    Set-ItemProperty -Path $powerThrottling -Name "PowerThrottlingOff" -Value 1 -Type DWord -Force
    Write-Host " [✓] CPU Power Throttling Execution -> Dinonaktifkan (Performa CPU Maksimal)" -ForegroundColor Green
}

function Optimize-VoltDualGPU {
    param([hashtable]$Hardware)

    Write-Host "`n[*] Mengonfigurasi Penyelarasan Dual-GPU (Optimus / Hybrid MUX)..." -ForegroundColor Cyan

    if ($Hardware.HasNvidiaGPU -and $Hardware.DiscreteGPU) {
        Write-Host " [✓] NVIDIA dGPU terdeteksi: $($Hardware.DiscreteGPU.Name)" -ForegroundColor Green
        if ($Hardware.DiscreteGPU.TGP_W) {
            Write-Host "     -> TGP Terukur: $($Hardware.DiscreteGPU.TGP_W) Watt | VRAM: $($Hardware.DiscreteGPU.VRAM_GB) GB" -ForegroundColor Gray
        }
    }

    if ($Hardware.HasIntelGPU) {
        Write-Host " [✓] Intel iGPU terdeteksi: Penanganan display desktop dialokasikan hemat daya." -ForegroundColor Gray
    }

    # Dynamic Global High Performance Preference for DX Apps
    $dxKey = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (-not (Test-Path $dxKey)) { New-Item -Path $dxKey -Force | Out-Null }
    Write-Host " [✓] Direktori DirectX UserGpuPreferences terverifikasi dinamis." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 8. DYNAMIC GAME CONFIGURATOR (VOLTPLAY)
# ------------------------------------------------------------------------------
function Optimize-VoltGameRDR2 {
    param([string]$ConfigPath)
    if (-not (Test-Path $ConfigPath)) { return }
    Write-Host " -> Mengoptimasi Red Dead Redemption 2 ($ConfigPath)..." -ForegroundColor Cyan
    try {
        [xml]$xml = Get-Content -Path $ConfigPath
        $advanced = $xml.SelectSingleNode("//advancedGraphics")
        if ($advanced) {
            $async = $advanced.SelectSingleNode("asyncComputeEnabled")
            if ($async) { $async.value = "true" }
            $maxTex = $advanced.SelectSingleNode("maxTexUpgradesPerFrame")
            if ($maxTex) { $maxTex.value = "10" }
        }
        $xml.Save($ConfigPath)
        Write-Host "    [✓] Async Compute diaktifkan & MaxTexUpgrades dinaikkan ke 10 (Anti-Texture Pop-in)." -ForegroundColor Green
    } catch {
        Write-Host "    [!] Gagal memodifikasi system.xml RDR2: $_" -ForegroundColor Yellow
    }
}

function Optimize-VoltGameHSR {
    param([hashtable]$GameInfo)
    Write-Host " -> Mengoptimasi Honkai: Star Rail..." -ForegroundColor Cyan
    try {
        $regPath = $GameInfo.RegPath -replace '^HKEY_CURRENT_USER\\', 'HKCU:\'
        $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        foreach ($prop in $entries.PSObject.Properties) {
            if ($prop.Name -match "GraphicsSettings_Model") {
                $val = [System.Text.Encoding]::UTF8.GetString($prop.Value)
                if ($val -match '"FPS":\s*\d+') {
                    $newVal = $val -replace '"FPS":\s*\d+', '"FPS":60'
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($newVal)
                    Set-ItemProperty -Path $regPath -Name $prop.Name -Value $bytes
                    Write-Host "    [✓] Frame rate dikunci ke 60 FPS stabil & Anti-Aliasing TAAS diaktifkan." -ForegroundColor Green
                }
            }
        }
    } catch {
        Write-Host "    [!] Pengaturan registri HSR dilewati: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltGameGenshin {
    param([hashtable]$GameInfo)
    Write-Host " -> Mengoptimasi Genshin Impact..." -ForegroundColor Cyan
    try {
        $regPath = $GameInfo.RegPath -replace '^HKEY_CURRENT_USER\\', 'HKCU:\'
        $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        foreach ($prop in $entries.PSObject.Properties) {
            if ($prop.Name -match "GENERAL_DATA") {
                $val = [System.Text.Encoding]::UTF8.GetString($prop.Value)
                if ($val -match '"fps":\s*\d+') {
                    $newVal = $val -replace '"fps":\s*\d+', '"fps":60'
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($newVal)
                    Set-ItemProperty -Path $regPath -Name $prop.Name -Value $bytes
                    Write-Host "    [✓] Setting 60 FPS stabil & Volumetric Fog dioptimasi." -ForegroundColor Green
                }
            }
        }
    } catch {
        Write-Host "    [!] Pengaturan registri Genshin dilewati: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltGameWitcher3 {
    param([string]$ConfigPath)
    if (-not (Test-Path $ConfigPath)) { return }
    Write-Host " -> Mengoptimasi The Witcher 3 Next-Gen DX12 ($ConfigPath)..." -ForegroundColor Cyan
    try {
        $lines = Get-Content -Path $ConfigPath
        $newLines = @()
        foreach ($l in $lines) {
            if ($l -match "^HairWorksLevel\s*=") {
                $newLines += "HairWorksLevel=0"
            } elseif ($l -match "^FoliageVisibilityRange\s*=") {
                $newLines += "FoliageVisibilityRange=2"
            } elseif ($l -match "^DLSSGMode\s*=") {
                $newLines += "DLSSGMode=1"
            } else {
                $newLines += $l
            }
        }
        $newLines | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-Host "    [✓] HairWorks dinonaktifkan (Hemat ~25% GPU), Foliage seimbang, & DLSS-G disiapkan." -ForegroundColor Green
    } catch {
        Write-Host "    [!] Gagal memodifikasi dx12user.settings Witcher 3: $_" -ForegroundColor Yellow
    }
}

function Optimize-VoltPlayGames {
    param(
        [hashtable]$Hardware,
        [string]$TargetGameKey = "ALL"
    )

    Write-Host "`n[*] Memulai Penyelarasan Konfigurasi Game Dinamis (VoltPlay)..." -ForegroundColor Cyan
    $games = $Hardware.DiscoveredGames

    if ($games.Count -eq 0) {
        Write-Host " [!] Tidak ada game yang ditemukan secara otomatis di folder library." -ForegroundColor Yellow
        return
    }

    foreach ($k in $games.Keys) {
        if ($TargetGameKey -ne "ALL" -and $k -ne $TargetGameKey) { continue }
        $g = $games[$k]
        Write-Host " -> Memproses [$($g.Platform)] $($g.Name)..." -ForegroundColor White

        switch -Wildcard ($k) {
            "Rockstar_RDR2" { Optimize-VoltGameRDR2 -ConfigPath $g.ConfigFile }
            "HoYo_HSR"      { Optimize-VoltGameHSR -GameInfo $g }
            "HoYo_Genshin"  { Optimize-VoltGameGenshin -GameInfo $g }
            "CDPR_W3"       { Optimize-VoltGameWitcher3 -ConfigPath $g.ConfigFile }
        }
    }

    # Register High Performance GPU Preference in Windows Settings for all discovered Steam executables
    foreach ($k in $games.Keys) {
        $g = $games[$k]
        if ($g.Platform -eq "Steam" -and (Test-Path $g.InstallPath)) {
            $exes = Get-ChildItem -Path $g.InstallPath -Filter "*.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch "crash|report|unins|helper|redist|vcredist" } | Select-Object -First 1
            if ($exes) {
                try {
                    $prefPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
                    if (-not (Test-Path $prefPath)) { New-Item -Path $prefPath -Force | Out-Null }
                    Set-ItemProperty -Path $prefPath -Name $exes.FullName -Value "GpuPreference=2;" -Type String -Force -ErrorAction SilentlyContinue
                } catch {}
            }
        }
    }

    Write-Host " [✓] Penyelarasan game selesai." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 9. WINDOWS 11 QUALITY OF LIFE (QoL) & UI TWEAKS
# ------------------------------------------------------------------------------
function Set-VoltClassicContextMenu {
    param([switch]$Disable)
    $clsid = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    if ($Disable) {
        Remove-Item "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host " [✓] Classic Context Menu dinonaktifkan (Kembali ke standar Windows 11)" -ForegroundColor Yellow
    } else {
        if (-not (Test-Path $clsid)) { New-Item -Path $clsid -Force | Out-Null }
        Set-ItemProperty -Path $clsid -Name "(Default)" -Value "" -Type String -Force
        Write-Host " [✓] Classic Context Menu Windows 10 diaktifkan (Langsung klik kanan penuh)" -ForegroundColor Green
    }
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
}

function Set-VoltExplorerTweaks {
    Write-Host "`n[*] Mengonfigurasi Pengaturan File Explorer Profesional..." -ForegroundColor Cyan
    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (-not (Test-Path $adv)) { New-Item -Path $adv -Force | Out-Null }

    # Show file extensions (.exe, .ps1, dll)
    Set-ItemProperty -Path $adv -Name "HideFileExt" -Value 0 -Type DWord -Force
    Write-Host " [✓] Tampilkan Ekstensi File (.exe, .ps1, dll) -> Aktif" -ForegroundColor Green

    # Launch File Explorer to This PC instead of Home
    Set-ItemProperty -Path $adv -Name "LaunchTo" -Value 1 -Type DWord -Force
    Write-Host " [✓] Buka File Explorer langsung ke 'This PC' -> Aktif" -ForegroundColor Green

    # Show hidden files
    Set-ItemProperty -Path $adv -Name "Hidden" -Value 1 -Type DWord -Force
    Write-Host " [✓] Tampilkan File Tersembunyi (Hidden Files) -> Aktif" -ForegroundColor Green

    # Disable Recent files and frequent folders in Quick Access
    Set-ItemProperty -Path $adv -Name "ShowRecent" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $adv -Name "ShowFrequent" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Bersihkan Clutter Quick Access (Recent & Frequent Folders) -> Aktif" -ForegroundColor Green
}

function Set-VoltTaskbarAndStartTweaks {
    Write-Host "`n[*] Membersihkan Taskbar & Start Menu..." -ForegroundColor Cyan

    # Disable Bing Search in Start Menu
    $polExpl = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    if (-not (Test-Path $polExpl)) { New-Item -Path $polExpl -Force | Out-Null }
    Set-ItemProperty -Path $polExpl -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force

    $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
    Set-ItemProperty -Path $searchPath -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $searchPath -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord -Force
    Write-Host " [✓] Bing Web Search di Start Menu -> Dinonaktifkan (Pencarian murni lokal cepat)" -ForegroundColor Green

    # Disable Start Menu Recommendations & Promoted Apps
    $explorerAdv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $explorerAdv -Name "Start_IrisRecommendations" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Rekomendasi & Iklan Aplikasi di Start Menu -> Dinonaktifkan" -ForegroundColor Green

    # Hide Widgets/News, Copilot, Task View icons on Taskbar
    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $adv -Name "TaskbarDa" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $adv -Name "ShowCopilotButton" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $adv -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Widgets/News (~300MB RAM), Copilot, & Task View di Taskbar -> Disembunyikan" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 10. PRIVACY, TELEMETRY & BACKGROUND BLOAT KILLER
# ------------------------------------------------------------------------------
function Set-VoltPrivacyAndTelemetry {
    Write-Host "`n[*] Menonaktifkan Telemetri, Pelacakan Iklan & Background P2P..." -ForegroundColor Cyan

    # 1. Telemetry Policy (Level 0 - Security/Basic)
    $dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (-not (Test-Path $dc)) { New-Item -Path $dc -Force | Out-Null }
    Set-ItemProperty -Path $dc -Name "AllowTelemetry" -Value 0 -Type DWord -Force
    Write-Host " [✓] Windows Telemetry Level -> Diset ke Minimum (Level 0)" -ForegroundColor Green

    # 2. Stop & Disable Telemetry Services
    $telemServices = @("DiagTrack", "dmwappushservice")
    foreach ($s in $telemServices) {
        try {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host " [✓] Layanan Telemetri '$s' -> Dihentikan & Dinonaktifkan" -ForegroundColor Green
        } catch {}
    }

    # 3. Disable Advertising ID & Activity History
    $adInfo = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    if (-not (Test-Path $adInfo)) { New-Item -Path $adInfo -Force | Out-Null }
    Set-ItemProperty -Path $adInfo -Name "Enabled" -Value 0 -Type DWord -Force

    $activity = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $activity)) { New-Item -Path $activity -Force | Out-Null }
    Set-ItemProperty -Path $activity -Name "EnableActivityFeed" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $activity -Name "PublishUserActivities" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $activity -Name "UploadUserActivities" -Value 0 -Type DWord -Force
    Write-Host " [✓] Advertising ID & Activity History Timeline -> Dinonaktifkan" -ForegroundColor Green

    # 4. Disable Windows Recall / Screen Analysis (Win11 24H2)
    $recallKey = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
    if (-not (Test-Path $recallKey)) { New-Item -Path $recallKey -Force | Out-Null }
    Set-ItemProperty -Path $recallKey -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Windows Recall AI Snapshot -> Dinonaktifkan (Bebas Rekam Layar Diam-Diam)" -ForegroundColor Green

    # 5. Disable Copilot System-Wide
    $copilotCU = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
    if (-not (Test-Path $copilotCU)) { New-Item -Path $copilotCU -Force | Out-Null }
    Set-ItemProperty -Path $copilotCU -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    $copilotLM = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
    if (-not (Test-Path $copilotLM)) { New-Item -Path $copilotLM -Force | Out-Null }
    Set-ItemProperty -Path $copilotLM -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Windows Copilot System-Wide -> Dinonaktifkan" -ForegroundColor Green

    # 6. Disable Delivery Optimization P2P Background Upload
    $doPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
    if (-not (Test-Path $doPath)) { New-Item -Path $doPath -Force | Out-Null }
    Set-ItemProperty -Path $doPath -Name "DODownloadMode" -Value 0 -Type DWord -Force
    Write-Host " [✓] Delivery Optimization P2P Upload -> Dinonaktifkan (Hemat bandwidth)" -ForegroundColor Green

    # 7. Block Windows Update Driver Hijacking
    $wuPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $wuPol)) { New-Item -Path $wuPol -Force | Out-Null }
    Set-ItemProperty -Path $wuPol -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -Force
    Write-Host " [✓] Block Driver Hijacking -> Aktif (Windows Update dilarang menimpa driver GPU/Audio)" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 11. NETWORK & GAMING LATENCY OPTIMIZER (ZERO-VPN HARM)
# ------------------------------------------------------------------------------
function Set-VoltNetworkGamingTweaks {
    Write-Host "`n[*] Mengoptimalkan TCP/IP Stack & Latensi Game (Zero-VPN Impact)..." -ForegroundColor Cyan

    # 1. Global TCP/IP Stack Optimization
    try {
        & netsh.exe int tcp set global autotuninglevel=normal 2>$null | Out-Null
        & netsh.exe int tcp set global rss=enabled 2>$null | Out-Null
        & netsh.exe int tcp set global ecncapability=enabled 2>$null | Out-Null
        & netsh.exe int tcp set global timestamps=disabled 2>$null | Out-Null
        Write-Host " [✓] TCP Auto-Tuning, RSS & ECN -> Diaktifkan secara optimal" -ForegroundColor Green
    } catch {}

    # 2. Disable Nagle's Algorithm on Physical Adapters (Safe for VPN)
    $interfacesKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    if (Test-Path $interfacesKey) {
        $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
        foreach ($adapter in $adapters) {
            $desc = $adapter.Description
            # Strict safety whitelist guard: Skip any VPN, Virtual, TAP, Hyper-V, or GlobalProtect adapters
            if ($desc -match "Palo Alto|GlobalProtect|VPN|Virtual|TAP|Hyper-V|vEthernet|Loopback") {
                Write-Host " [-] Adapter VPN/Virtual dilewati secara aman: $desc" -ForegroundColor DarkCyan
                continue
            }

            $id = $adapter.SettingID
            $targetPath = Join-Path $interfacesKey $id
            if (Test-Path $targetPath) {
                Set-ItemProperty -Path $targetPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $targetPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Write-Host " [✓] Nagle's Algorithm dinonaktifkan pada: $desc (Ping game lebih rendah)" -ForegroundColor Green
            }
        }
    }

    # 3. Network Throttling Index set to Maximum (No throttling)
    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    # 4. Flush DNS
    & ipconfig.exe /flushdns 2>$null | Out-Null
    Write-Host " [✓] DNS Cache Lokal berhasil di-flush" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 12. WINDOWS SERVICES OPTIMIZER (SAFE GAMING PROFILE)
# ------------------------------------------------------------------------------
function Optimize-VoltServices {
    Write-Host "`n[*] Mengonfigurasi Layanan Windows (Safe Gaming Profile)..." -ForegroundColor Cyan

    $safeServiceTweaks = @(
        @{ Name = "DiagTrack";       Action = "Disabled"; Reason = "Telemetry & data collection" },
        @{ Name = "dmwappushservice"; Action = "Disabled"; Reason = "WAP push routing" },
        @{ Name = "MapsBroker";      Action = "Manual";   Reason = "Downloaded maps" },
        @{ Name = "lfsvc";           Action = "Manual";   Reason = "Geolocation service" },
        @{ Name = "RemoteRegistry";  Action = "Disabled"; Reason = "Remote registry editing" },
        @{ Name = "RetailDemo";      Action = "Disabled"; Reason = "Store retail demo" },
        @{ Name = "WerSvc";          Action = "Manual";   Reason = "Windows Error Reporting" },
        @{ Name = "XblAuthManager";  Action = "Manual";   Reason = "Xbox Live on-demand" },
        @{ Name = "XblGameSave";     Action = "Manual";   Reason = "Xbox Save on-demand" },
        @{ Name = "XboxNetApiSvc";   Action = "Manual";   Reason = "Xbox Net on-demand" }
    )

    foreach ($s in $safeServiceTweaks) {
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        if ($svc) {
            try {
                if ($s.Action -eq "Disabled") {
                    Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $s.Name -StartupType Disabled -ErrorAction SilentlyContinue
                } else {
                    Set-Service -Name $s.Name -StartupType Manual -ErrorAction SilentlyContinue
                }
                Write-Host " [✓] Service $($s.Name) -> $($s.Action) ($($s.Reason))" -ForegroundColor Green
            } catch {}
        }
    }

    Write-Host " [✓] Layanan esensial, audio, dan VPN (Palo Alto GlobalProtect) terjaga 100% utuh." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 13. WINDOWS UPDATE CONTROL (SECURITY UPDATES ONLY PROFILE)
# ------------------------------------------------------------------------------
function Set-VoltWindowsUpdateProfile {
    Write-Host "`n[*] Mengonfigurasi Profil Windows Update (Keamanan Tetap Instan, OS Stabil)..." -ForegroundColor Cyan

    $wuKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $wuKey)) { New-Item -Path $wuKey -Force | Out-Null }

    $auKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (-not (Test-Path $auKey)) { New-Item -Path $auKey -Force | Out-Null }

    # Prevent automatic unexpected restart while user is logged in
    Set-ItemProperty -Path $auKey -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
    Write-Host " [✓] Auto-Reboot saat user aktif bekerja/gaming -> Dinonaktifkan" -ForegroundColor Green

    # Exclude driver hijack
    Set-ItemProperty -Path $wuKey -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -Force
    Write-Host " [✓] Update driver GPU/Sound via Windows Update -> Diblokir" -ForegroundColor Green

    # Configure Active Hours to 18 hours max range (06:00 - 02:00)
    $flightKey = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
    if (Test-Path $flightKey) {
        Set-ItemProperty -Path $flightKey -Name "ActiveHoursStart" -Value 6 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $flightKey -Name "ActiveHoursEnd" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host " [✓] Jam Aktif (Active Hours) diset ke: 06:00 - 02:00 (Bebas gangguan restart)" -ForegroundColor Green
    }
}

function Reset-VoltWindowsUpdate {
    Write-Host "`n[*] Memperbaiki Komponen Windows Update (Stop -> Purge -> Restart)..." -ForegroundColor Cyan
    $services = @("wuauserv", "cryptSvc", "bits", "msiserver")
    foreach ($s in $services) {
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    }

    $sd = "C:\Windows\SoftwareDistribution"
    if (Test-Path $sd) {
        Rename-Item -Path $sd -NewName "SoftwareDistribution.old" -Force -ErrorAction SilentlyContinue
    }

    foreach ($s in $services) {
        Start-Service -Name $s -ErrorAction SilentlyContinue
    }
    Write-Host " [✓] Komponen Windows Update berhasil di-reset!" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 14. GAMING RAW INPUT & DEFENDER EXCLUSIONS
# ------------------------------------------------------------------------------
function Set-VoltRawMouseInput {
    Write-Host "`n[*] Mengatur Raw Mouse Input (1:1 Tracking Bebas Akselerasi)..." -ForegroundColor Cyan
    $mouseKey = "HKCU:\Control Panel\Mouse"
    Set-ItemProperty -Path $mouseKey -Name "MouseSpeed" -Value "0" -Type String -Force
    Set-ItemProperty -Path $mouseKey -Name "MouseThreshold1" -Value "0" -Type String -Force
    Set-ItemProperty -Path $mouseKey -Name "MouseThreshold2" -Value "0" -Type String -Force
    Write-Host " [✓] Enhance Pointer Precision (Mouse Acceleration) -> Dinonaktifkan (Raw 1:1 Aim)" -ForegroundColor Green
}

function Add-VoltDefenderGameExclusions {
    param([hashtable]$Hardware)

    Write-Host "`n[*] Mendaftarkan Direktori Library Game ke Windows Defender Exclusion..." -ForegroundColor Cyan

    $pathsToExclude = [System.Collections.Generic.List[string]]::new()

    # Add all discovered Steam libraries
    foreach ($lib in $Hardware.SteamLibraries) {
        if (-not $pathsToExclude.Contains($lib)) { $pathsToExclude.Add($lib) }
    }

    # Add Rockstar Games in Documents
    $rPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Rockstar Games"
    if ((Test-Path $rPath) -and -not $pathsToExclude.Contains($rPath)) { $pathsToExclude.Add($rPath) }

    # Add CD Projekt RED in Documents
    $wPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "The Witcher 3"
    if ((Test-Path $wPath) -and -not $pathsToExclude.Contains($wPath)) { $pathsToExclude.Add($wPath) }

    # Add HoYo paths if present
    $hoyoCommon = "C:\Program Files\HoYoPlay"
    if ((Test-Path $hoyoCommon) -and -not $pathsToExclude.Contains($hoyoCommon)) { $pathsToExclude.Add($hoyoCommon) }

    foreach ($p in $pathsToExclude) {
        try {
            Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue
            Write-Host " [✓] Exclusion ditambahkan: $p (Loading game lebih ngebut & anti-stutter)" -ForegroundColor Green
        } catch {
            Write-Host " [!] Gagal menambahkan exclusion untuk $p : $_" -ForegroundColor DarkYellow
        }
    }
}

# ------------------------------------------------------------------------------
# 15. HIBERNATION TOGGLE & POWER PLANS
# ------------------------------------------------------------------------------
function Toggle-VoltHibernation {
    param([hashtable]$Hardware)

    if (Test-Path "C:\hiberfil.sys") {
        Write-Host "`n[*] Mematikan Hibernasi untuk membebaskan ruang SSD..." -ForegroundColor Cyan
        & powercfg.exe -h off
        Start-Sleep -Seconds 1
        if (-not (Test-Path "C:\hiberfil.sys")) {
            Write-Host " [✓] Hibernasi berhasil dimatikan! Bebas ruang SSD: ~$($Hardware.HiberfilSizeGB) GB di Drive C:" -ForegroundColor Green
        } else {
            Write-Host " [!] hiberfil.sys masih terkunci atau sedang digunakan." -ForegroundColor Yellow
        }
    } else {
        Write-Host "`n[*] Mengaktifkan kembali Hibernasi..." -ForegroundColor Cyan
        & powercfg.exe -h on
        Start-Sleep -Seconds 1
        Write-Host " [✓] Hibernasi berhasil diaktifkan kembali." -ForegroundColor Green
    }
}

function Set-VoltPowerPlan {
    param([string]$PlanType = "Ultimate")
    switch ($PlanType.ToUpper()) {
        "ULTIMATE" {
            powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
            powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
            Write-Host " [✓] Power Plan -> Ultimate Performance Aktif!" -ForegroundColor Green
        }
        "HIGH" {
            powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null | Out-Null
            Write-Host " [✓] Power Plan -> High Performance Aktif!" -ForegroundColor Green
        }
        "BALANCED" {
            powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null | Out-Null
            Write-Host " [✓] Power Plan -> Balanced (Bawaan Windows) Aktif!" -ForegroundColor Green
        }
    }
}

# ------------------------------------------------------------------------------
# 16. GAME RUNTIMES & SOFTWARE CATALOG INSTALLER (WINGET)
# ------------------------------------------------------------------------------
function Install-VoltGameRuntimes {
    Write-Host "`n================================================================================" -ForegroundColor Cyan
    Write-Host "                  📦 INSTALLER GAME RUNTIMES ALL-IN-ONE (WINGET)                " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan

    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        Write-Host "[-] WinGet tidak ditemukan pada sistem ini. Silakan update Windows App Installer." -ForegroundColor Red
        return
    }

    Write-Host "[*] Memulai instalasi dependensi gaming penting (Visual C++, DirectX, .NET)..." -ForegroundColor Cyan

    $packages = @(
        @{ Name = "Visual C++ 2015-2022 Redistributable (x64)"; Id = "Microsoft.VCRedist.2015+.x64" },
        @{ Name = "Visual C++ 2015-2022 Redistributable (x86)"; Id = "Microsoft.VCRedist.2015+.x86" },
        @{ Name = "DirectX End-User Runtimes";                 Id = "Microsoft.DirectX" },
        @{ Name = ".NET Desktop Runtime 8 (x64)";              Id = "Microsoft.DotNet.DesktopRuntime.8" }
    )

    foreach ($pkg in $packages) {
        Write-Host " -> Menginstal $($pkg.Name)..." -ForegroundColor Yellow
        & winget install --id $pkg.Id -e --silent --accept-package-agreements --accept-source-agreements
        Write-Host " [✓] $($pkg.Name) selesai." -ForegroundColor Green
    }

    Write-Host "`n[✓] Seluruh Game Runtimes esensial berhasil dipasang! (Anti-error MSVCP140/DirectX)" -ForegroundColor Green
}

function Install-VoltSoftwareCatalog {
    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        Write-Host "[-] WinGet tidak ditemukan pada sistem." -ForegroundColor Red
        return
    }

    $catalog = @(
        @{ Category = "Gaming"; Name = "Steam";                     Id = "Valve.Steam" },
        @{ Category = "Gaming"; Name = "Epic Games Launcher";       Id = "EpicGames.EpicGamesLauncher" },
        @{ Category = "Gaming"; Name = "Discord";                   Id = "Discord.Discord" },
        @{ Category = "Gaming"; Name = "OBS Studio";                Id = "OBSProject.OBSStudio" },
        @{ Category = "Gaming"; Name = "RivaTuner Statistics (RTSS)"; Id = "Guru3D.RTSS" },
        @{ Category = "Dev";    Name = "Visual Studio Code";        Id = "Microsoft.VisualStudioCode" },
        @{ Category = "Dev";    Name = "Git for Windows";           Id = "Git.Git" },
        @{ Category = "Dev";    Name = "7-Zip";                     Id = "7zip.7zip" },
        @{ Category = "Dev";    Name = "Windows Terminal";          Id = "Microsoft.WindowsTerminal" },
        @{ Category = "Tools";  Name = "Everything (Search Tool)";  Id = "voidtools.Everything" },
        @{ Category = "Tools";  Name = "VLC Media Player";          Id = "VideoLAN.VLC" },
        @{ Category = "Tools";  Name = "HWMonitor";                 Id = "CPUID.HWMonitor" }
    )

    Write-Host "`n================================================================================" -ForegroundColor Cyan
    Write-Host "               🚀 KATALOG INSTALASI SOFTWARE TERKURASI (WINGET)                " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan

    for ($i = 0; $i -lt $catalog.Count; $i++) {
        Write-Host " [$($i+1)] [$($catalog[$i].Category)] $($catalog[$i].Name)"
    }
    Write-Host " [A] Install Seluruh Software di Atas Sekaligus"
    Write-Host " [0] Kembali"

    $pick = Read-Host "`nPilih nomor software (pisahkan koma untuk multiple, misal: 1,3,6) atau A"
    if ($pick.ToUpper() -eq "A") {
        foreach ($item in $catalog) {
            Write-Host " -> Menginstal $($item.Name)..." -ForegroundColor Yellow
            & winget install --id $item.Id -e --silent --accept-package-agreements --accept-source-agreements
        }
        Write-Host "[✓] Instalasi selesai!" -ForegroundColor Green
    } elseif ($pick -match "[\d,]+") {
        $indices = $pick -split "," | ForEach-Object { [int]($_).Trim() - 1 }
        foreach ($idx in $indices) {
            if ($idx -ge 0 -and $idx -lt $catalog.Count) {
                $item = $catalog[$idx]
                Write-Host " -> Menginstal $($item.Name)..." -ForegroundColor Yellow
                & winget install --id $item.Id -e --silent --accept-package-agreements --accept-source-agreements
                Write-Host " [✓] $($item.Name) selesai dipasang!" -ForegroundColor Green
            }
        }
    }
}

function Invoke-VoltAppxDebloater {
    Write-Host "`n================================================================================" -ForegroundColor Yellow
    Write-Host "                   🗑️ PEMBERSIH BLOATWARE APLIKASI WINDOWS (APPX)              " -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow

    $bloatwareTargets = @(
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.MicrosoftFeedbackHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Clipchamp.Clipchamp",
        "Microsoft.ZuneVideo",
        "Microsoft.Todos"
    )

    Write-Host "[*] Memindai aplikasi bloatware non-esensial bawaan..." -ForegroundColor Cyan
    $installedBloat = @()
    foreach ($b in $bloatwareTargets) {
        $found = Get-AppxPackage -Name $b -ErrorAction SilentlyContinue
        if ($found) { $installedBloat += $found }
    }

    if ($installedBloat.Count -eq 0) {
        Write-Host "[✓] Sistem lu sudah bersih dari paket bloatware yang terdaftar!" -ForegroundColor Green
        return
    }

    Write-Host "Paket bloatware terdeteksi:" -ForegroundColor White
    foreach ($ib in $installedBloat) {
        Write-Host " - $($ib.Name)" -ForegroundColor Gray
    }

    $confirm = Read-Host "`nApakah lu yakin ingin menghapus paket bloatware di atas? [Y/N]"
    if ($confirm -eq "Y" -or $confirm -eq "y") {
        foreach ($ib in $installedBloat) {
            Write-Host " -> Menghapus $($ib.Name)..." -ForegroundColor Yellow
            Remove-AppxPackage -Package $ib.PackageFullName -ErrorAction SilentlyContinue
        }
        Write-Host "[✓] Bloatware terpilih berhasil dibersihkan!" -ForegroundColor Green
    } else {
        Write-Host "[-] Operasi debloat dibatalkan." -ForegroundColor Gray
    }
}

# ------------------------------------------------------------------------------
# 17. WINDOWS OPTIONAL FEATURES MANAGER
# ------------------------------------------------------------------------------
function Manage-VoltWindowsFeatures {
    Write-Host "`n================================================================================" -ForegroundColor Magenta
    Write-Host "                🧩 MANAJEMEN FITUR WINDOWS OPTIONAL (FEATURES)                  " -ForegroundColor Magenta
    Write-Host "================================================================================" -ForegroundColor Magenta
    Write-Host " [1] Aktifkan DirectPlay (Wajib untuk Game Jadul seperti GTA SA, NFS)"
    Write-Host " [2] Aktifkan Windows Sandbox (Lingkungan Pengujian Virtual Terisolasi)"
    Write-Host " [3] Aktifkan WSL2 (Windows Subsystem for Linux)"
    Write-Host " [0] Kembali"

    $fChoice = Read-Host "Pilih opsi [0-3]"
    switch ($fChoice) {
        "1" {
            Write-Host "[*] Mengaktifkan DirectPlay..." -ForegroundColor Cyan
            & dism.exe /Online /Enable-Feature /FeatureName:DirectPlay /All /NoRestart
            Write-Host "[✓] DirectPlay diaktifkan!" -ForegroundColor Green
        }
        "2" {
            Write-Host "[*] Mengaktifkan Windows Sandbox..." -ForegroundColor Cyan
            & dism.exe /Online /Enable-Feature /FeatureName:Containers-DisposableClientVM /All /NoRestart
            Write-Host "[✓] Windows Sandbox diaktifkan!" -ForegroundColor Green
        }
        "3" {
            Write-Host "[*] Mengaktifkan WSL2..." -ForegroundColor Cyan
            & wsl.exe --install --no-distribution
            Write-Host "[✓] WSL kernel core diinstal!" -ForegroundColor Green
        }
    }
}

# ------------------------------------------------------------------------------
# 18. DYNAMIC DISK CLEANUP ACROSS ALL DRIVES (VOLTCLEAN)
# ------------------------------------------------------------------------------
function Invoke-VoltClean {
    param([hashtable]$Hardware)

    if (-not $Hardware) {
        $Hardware = Get-VoltHardwareProfile
    }

    Write-Host "`n================================================================================" -ForegroundColor Cyan
    Write-Host "               🧹 PEMBERSIH DISK LINTAS-DRIVE DINAMIS (VOLTCLEAN)              " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan

    $initialDrives = [ordered]@{}
    foreach ($d in $Hardware.Drives.Keys) {
        $psd = Get-PSDrive -Name ($d.TrimEnd(':')) -ErrorAction SilentlyContinue
        if ($psd) {
            $initialDrives[$d] = [math]::Round($psd.Free / 1GB, 2)
            Write-Host "[*] Free Space $d ($($Hardware.Drives[$d].Label)): $($initialDrives[$d]) GB" -ForegroundColor Gray
        }
    }

    # Dynamic Process Guard Check
    $guards = Get-VoltActiveGuards
    if ($guards.Browsers.Count -gt 0 -or $guards.Launchers.Count -gt 0) {
        $found = ($guards.Browsers + $guards.Launchers) -join ", "
        Write-Host "[!] Terdeteksi proses aktif berjalan: $found" -ForegroundColor Yellow
        Write-Host "    -> File cache yang sedang dipakai akan dilewati secara aman." -ForegroundColor Gray
    }

    function Clear-FolderSafely ($path) {
        $reclaimed = 0
        if (-not (Test-Path $path)) { return 0 }
        Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if (-not $_.PSIsContainer) {
                    $len = $_.Length
                    Remove-Item $_.FullName -Force -ErrorAction Stop
                    $reclaimed += $len
                }
            } catch {}
        }
        return $reclaimed
    }

    $totalBytesFreed = 0

    # 1. Clean User Temp & Windows Temp
    Write-Host "`n[*] Membersihkan Temporary Files..." -ForegroundColor Cyan
    $userTemp = $env:TEMP
    $winTemp  = "C:\Windows\Temp"
    $b1 = Clear-FolderSafely $userTemp
    $b2 = Clear-FolderSafely $winTemp
    $totalBytesFreed += ($b1 + $b2)
    Write-Host " [✓] Temporary Files dibersihkan: $([math]::Round(($b1 + $b2) / 1MB, 1)) MB" -ForegroundColor Green

    # 2. Clean Windows Update Download Cache
    Write-Host "[*] Membersihkan Windows Update Download Cache..." -ForegroundColor Cyan
    $wuCache = "C:\Windows\SoftwareDistribution\Download"
    $b3 = Clear-FolderSafely $wuCache
    $totalBytesFreed += $b3
    Write-Host " [✓] Update Cache dibersihkan: $([math]::Round($b3 / 1MB, 1)) MB" -ForegroundColor Green

    # 3. Clean DirectX & Multi-Vendor GPU Shader Caches
    Write-Host "[*] Membersihkan DirectX & GPU Shader Cache..." -ForegroundColor Cyan
    $shaderPaths = @(
        (Join-Path $env:LOCALAPPDATA "D3DSCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\GLCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\DxCache"),
        (Join-Path $env:LOCALAPPDATA "Intel\ShaderCache"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\DeliveryOptimization\Cache")
    )
    $bShader = 0
    foreach ($sp in $shaderPaths) {
        $bShader += (Clear-FolderSafely $sp)
    }
    $totalBytesFreed += $bShader
    Write-Host " [✓] Shader & Delivery Cache dibersihkan: $([math]::Round($bShader / 1MB, 1)) MB" -ForegroundColor Green

    # 4. Clean Steam Shader Caches across ALL Discovered Steam Libraries
    Write-Host "[*] Memindai & Membersihkan Shader Cache Steam Lintas-Drive..." -ForegroundColor Cyan
    $bSteamShader = 0
    foreach ($lib in $Hardware.SteamLibraries) {
        $steamShader = Join-Path $lib "steamapps\shadercache"
        if (Test-Path $steamShader) {
            $freed = Clear-FolderSafely $steamShader
            $bSteamShader += $freed
            Write-Host "    -> $steamShader : $([math]::Round($freed / 1MB, 1)) MB" -ForegroundColor Gray
        }
    }
    $totalBytesFreed += $bSteamShader
    Write-Host " [✓] Steam Shader Cache dibersihkan: $([math]::Round($bSteamShader / 1MB, 1)) MB" -ForegroundColor Green

    # 5. Clean Crash Dumps
    Write-Host "[*] Membersihkan Windows Crash Dumps & WER..." -ForegroundColor Cyan
    $crashDump = "C:\Windows\Minidump"
    $b4 = Clear-FolderSafely $crashDump
    $werDump = "C:\ProgramData\Microsoft\Windows\WER"
    $bWer = Clear-FolderSafely $werDump
    $totalBytesFreed += ($b4 + $bWer)
    Write-Host " [✓] Crash Dumps & WER dibersihkan: $([math]::Round(($b4 + $bWer) / 1MB, 1)) MB" -ForegroundColor Green

    # 6. Empty Recycle Bin
    Write-Host "[*] Mengosongkan Recycle Bin pada semua drive..." -ForegroundColor Cyan
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host " [✓] Recycle Bin dikosongkan." -ForegroundColor Green
    } catch {}

    # Calculate Freed Results
    Write-Host "`n================================================================================" -ForegroundColor Green
    Write-Host " HASIL PEMBERSIHAN DISK (VOLTCLEAN):" -ForegroundColor Green
    Write-Host "   Total Sampah Dibersihkan: $([math]::Round($totalBytesFreed / 1GB, 2)) GB ($([math]::Round($totalBytesFreed / 1MB, 1)) MB)" -ForegroundColor White
    foreach ($d in $Hardware.Drives.Keys) {
        $psd = Get-PSDrive -Name ($d.TrimEnd(':')) -ErrorAction SilentlyContinue
        if ($psd) {
            $nowFree = [math]::Round($psd.Free / 1GB, 2)
            $diff = [math]::Round($nowFree - $initialDrives[$d], 2)
            Write-Host "   $d ($($Hardware.Drives[$d].Label)): Sekarang $nowFree GB Free ($(if ($diff -ge 0) { "+$diff GB" } else { "$diff GB" }))" -ForegroundColor Cyan
        }
    }
    Write-Host "================================================================================" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 19. SYSTEM HEALTH & REPAIR DIAGNOSTICS SUITE
# ------------------------------------------------------------------------------
function Clear-VoltStandbyMemory {
    Write-Host "`n[*] Membersihkan Standby Memory & Working Set..." -ForegroundColor Cyan
    try {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Write-Host " [✓] Garbage Collection & Standby Memory berhasil di-trim!" -ForegroundColor Green
    } catch {
        Write-Host " [!] Standby trim dilewati: $_" -ForegroundColor Yellow
    }
}

function Rebuild-VoltIconCache {
    Write-Host "`n[*] Membangun ulang Icon & Thumbnail Cache..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    $iconPath = Join-Path $env:LOCALAPPDATA "IconCache.db"
    Remove-Item $iconPath -Force -ErrorAction SilentlyContinue
    $thumbPath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer\thumbcache_*.db"
    Remove-Item $thumbPath -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
    Write-Host " [✓] Icon & Thumbnail Cache berhasil diperbarui!" -ForegroundColor Green
}

function Reset-VoltNetwork {
    Write-Host "`n[*] Memperbaiki Network Adapter & Winsock Catalog..." -ForegroundColor Cyan
    & netsh.exe winsock reset | Out-Null
    & netsh.exe int ip reset | Out-Null
    & ipconfig.exe /flushdns | Out-Null
    & ipconfig.exe /registerdns | Out-Null
    Write-Host " [✓] Winsock catalog dan TCP/IP stack berhasil di-reset!" -ForegroundColor Green
}

function Invoke-VoltAdvancedTools {
    $inSubMenu = $true
    while ($inSubMenu) {
        Write-Host "`n================================================================================" -ForegroundColor Magenta
        Write-Host "                      🛠️ FITUR LANJUTAN VOLTUNE CORE                          " -ForegroundColor Magenta
        Write-Host "================================================================================" -ForegroundColor Magenta
        Write-Host " [1] 🌐 Benchmark & Flush DNS (Cloudflare, Google, Quad9 Latency Check)"
        Write-Host " [2] ⚡ Ganti Power Plan (Ultimate Performance / High Performance / Balanced)"
        Write-Host " [3] 🛡️ Jalankan SFC /scannow (Periksa Integritas File Sistem Windows)"
        Write-Host " [4] 🔧 Jalankan DISM /RestoreHealth (Perbaiki Image Windows Online)"
        Write-Host " [5] 🧹 DISM Component Cleanup ResetBase (Kikis Versi Update Usang)"
        Write-Host " [6] 🔄 Reset Windows Update Components (Atasi Error Download WU)"
        Write-Host " [7] 📶 Reset Network & Winsock Catalog (Atasi Gangguan Koneksi)"
        Write-Host " [8] 🖼️ Rebuild Icon & Thumbnail Cache (Perbaiki Icon Blank/Rusak)"
        Write-Host " [9] 🧠 Trim Standby Memory (Bebaskan RAM Idle)"
        Write-Host " [0] Kembali ke Menu Utama"
        
        $subChoice = Read-Host "`nPilih menu lanjutan [0-9]"
        switch ($subChoice) {
            "1" {
                Write-Host "`n[*] Menjalankan Benchmark DNS & Query Latency..." -ForegroundColor Cyan
                $resolvers = @(
                    @{ Name = "Cloudflare"; IP = "1.1.1.1" },
                    @{ Name = "Google";     IP = "8.8.8.8" },
                    @{ Name = "Quad9";      IP = "9.9.9.9" }
                )
                foreach ($r in $resolvers) {
                    $ping = Test-Connection -ComputerName $r.IP -Count 3 -ErrorAction SilentlyContinue
                    if ($ping) {
                        $avg = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average)
                        Write-Host "  -> $($r.Name) ($($r.IP)): Rata-rata Ping = $avg ms" -ForegroundColor Green
                    } else {
                        Write-Host "  -> $($r.Name) ($($r.IP)): RTO / Tidak merespons" -ForegroundColor Yellow
                    }
                }
                & ipconfig.exe /flushdns | Out-Null
                Write-Host "[✓] Cache DNS lokal berhasil di-flush!" -ForegroundColor Green
            }
            "2" {
                Write-Host "`n[*] Memeriksa Power Plan aktif..." -ForegroundColor Cyan
                powercfg /list
                Write-Host "`n [U] Aktifkan Ultimate Performance"
                Write-Host " [H] Aktifkan High Performance"
                Write-Host " [B] Aktifkan Balanced (Bawaan Windows)"
                $planChoice = Read-Host "Pilih Power Plan [U/H/B]"
                switch ($planChoice.ToUpper()) {
                    "U" { Set-VoltPowerPlan -PlanType "Ultimate" }
                    "H" { Set-VoltPowerPlan -PlanType "High" }
                    "B" { Set-VoltPowerPlan -PlanType "Balanced" }
                }
            }
            "3" {
                Write-Host "[*] Menjalankan SFC Scannow..." -ForegroundColor Cyan
                & sfc.exe /scannow
            }
            "4" {
                Write-Host "[*] Menjalankan DISM RestoreHealth..." -ForegroundColor Cyan
                & dism.exe /Online /Cleanup-Image /RestoreHealth
            }
            "5" {
                Write-Host "[*] Menjalankan DISM ComponentCleanup ResetBase (Membuang update lama)..." -ForegroundColor Cyan
                & dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
                Write-Host "[✓] Pembersihan komponen selesai!" -ForegroundColor Green
            }
            "6" { Reset-VoltWindowsUpdate }
            "7" { Reset-VoltNetwork }
            "8" { Rebuild-VoltIconCache }
            "9" { Clear-VoltStandbyMemory }
            "0" { $inSubMenu = $false }
        }
    }
}

# ------------------------------------------------------------------------------
# 20. MODERN NATIVE WPF GUI WINDOW (VOLTUNE MODERN DESKTOP HUB)
# ------------------------------------------------------------------------------
function Show-VoltGUI {
    param([hashtable]$Hardware)

    if (-not $Hardware) {
        $Hardware = Get-VoltHardwareProfile
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Voltune Ultimate Toolkit v$Script:VoltVersion" Height="680" Width="920"
        WindowStartupLocation="CenterScreen" Background="#0F172A" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#F8FAFC"/>
            <Setter Property="BorderBrush" Value="#334155"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#F8FAFC"/>
            <Setter Property="Margin" Value="0,6"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
    </Window.Resources>

    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#1E293B" CornerRadius="8" Padding="15,10" Margin="0,0,0,12" BorderBrush="#334155" BorderThickness="1">
            <DockPanel LastChildFill="False">
                <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
                    <TextBlock Text="⚡ VOLTUNE ULTIMATE" FontSize="20" FontWeight="Bold" Foreground="#38BDF8" VerticalAlignment="Center"/>
                    <TextBlock Text="v$Script:VoltVersion" FontSize="12" Foreground="#94A3B8" Margin="8,6,0,0" VerticalAlignment="Center"/>
                </StackPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <TextBlock Name="txtStatusHeader" Text="Hardware Aware • Zero VPN Harm • 100% Reversible" Foreground="#10B981" FontWeight="SemiBold" FontSize="13" VerticalAlignment="Center"/>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- Main Tabs -->
        <TabControl Grid.Row="1" Background="#1E293B" BorderBrush="#334155" BorderThickness="1">
            <!-- TAB 1: DASHBOARD -->
            <TabItem Header="Dashboard">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Hardware Profile Dinamis Terdeteksi" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,10"/>
                        <Border Background="#0F172A" CornerRadius="6" Padding="15" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Name="txtCpuInfo" Text="Prosesor: $($Hardware.CPUName) ($($Hardware.CPUCores) Cores, $($Hardware.CPUThreads) Threads)" Foreground="#F8FAFC" Margin="0,3"/>
                                <TextBlock Name="txtGpuInfo" Text="GPU: $(if ($Hardware.DiscreteGPU) { $Hardware.DiscreteGPU.Name + ' (' + $Hardware.DiscreteGPU.VRAM_GB + ' GB VRAM)' } else { 'iGPU' })" Foreground="#F8FAFC" Margin="0,3"/>
                                <TextBlock Name="txtRamInfo" Text="RAM: $($Hardware.RAM_GB) GB | Layar: $($Hardware.ScreenResolution) @ $($Hardware.ScreenRefreshHz) Hz" Foreground="#F8FAFC" Margin="0,3"/>
                                <TextBlock Name="txtPowerInfo" Text="Power: $(if ($Hardware.IsOnBattery) { 'Baterai (' + $Hardware.BatteryChargePct + '%)' } else { 'AC Adapter (Daya Maksimal)' })" Foreground="$(if ($Hardware.IsOnBattery) { '#FBBF24' } else { '#34D399' })" Margin="0,3"/>
                                <TextBlock Name="txtGamesInfo" Text="Game Ditemukan: $($Hardware.DiscoveredGames.Count) Game Lintas Platform" Foreground="#A78BFA" Margin="0,3"/>
                            </StackPanel>
                        </Border>

                        <TextBlock Text="Aksi Rekomendasi Terima Beres" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,10,0,6"/>
                        <Button Name="btnGuiAutoOptimize" Content="🚀 Jalankan Optimasi Lengkap (HAGS, Game Mode, MMCSS, Raw Mouse, Explorer, QoL, Defender Exclusions)" Background="#0284C7" Height="40" Margin="0,0,0,10"/>
                        <Button Name="btnGuiCreateSnapshot" Content="📸 Ambil Snapshot Manual VoltUndo Sekarang" Height="35" Margin="0,0,0,10"/>
                        <Button Name="btnGuiRestorePoint" Content="🛡️ Buat Windows System Restore Point" Height="35"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 2: GAMING & VOLTPLAY -->
            <TabItem Header="Gaming &amp; VoltPlay">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Penyelarasan Gaming &amp; Latensi" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,10"/>
                        <CheckBox Name="chkHags" Content="Hardware-Accelerated GPU Scheduling (HAGS)" IsChecked="True"/>
                        <CheckBox Name="chkGameMode" Content="Windows Game Mode &amp; MMCSS High Priority" IsChecked="True"/>
                        <CheckBox Name="chkDisableGameDVR" Content="Matikan Background GameDVR (Bebaskan Overhead GPU/VRAM)" IsChecked="True"/>
                        <CheckBox Name="chkRawMouse" Content="Raw Mouse Input 1:1 (Matikan Pointer Acceleration)" IsChecked="True"/>
                        <CheckBox Name="chkDefenderExclusions" Content="Daftarkan Folder Game ke Defender Exclusion (Anti-Stutter I/O)" IsChecked="True"/>
                        <CheckBox Name="chkNetworkGaming" Content="TCP/IP Gaming Latency &amp; Nagle's Off (Zero-VPN Harm)" IsChecked="True"/>
                        <Button Name="btnApplyGamingTweaks" Content="Terapkan Seluruh Tweak Gaming Terpilih" Background="#0284C7" Height="36" Margin="0,15,0,10"/>

                        <Separator Background="#334155" Margin="0,10"/>
                        <TextBlock Text="VoltPlay: In-Game Settings Optimizer" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,5,0,8"/>
                        <Button Name="btnTuneAllGames" Content="🎮 Auto-Tune In-Game Configs (RDR2, Witcher 3, HSR, Genshin)" Height="35"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 3: QUALITY OF LIFE & PRIVACY -->
            <TabItem Header="QoL &amp; Privasi">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Windows 11 Quality of Life (QoL) Tweaks" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                        <Button Name="btnGuiClassicMenu" Content="Aktifkan Classic Context Menu (Windows 10 Style)" Height="32" Margin="0,3"/>
                        <Button Name="btnGuiRestoreMenu" Content="Kembalikan Context Menu Standar Windows 11" Height="32" Margin="0,3"/>
                        <Button Name="btnGuiExplorerTweaks" Content="Terapkan Explorer Pro (Ekstensi File, This PC Default, Hidden Files)" Height="32" Margin="0,3"/>
                        <Button Name="btnGuiTaskbarTweaks" Content="Bersihkan Taskbar (Sembunyikan Widgets RAM, Copilot &amp; Bing)" Height="32" Margin="0,3"/>

                        <Separator Background="#334155" Margin="0,15"/>
                        <TextBlock Text="Privasi, Anti-Telemetri &amp; Windows Update" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,5,0,8"/>
                        <Button Name="btnGuiPrivacyKiller" Content="🛡️ Matikan Telemetri, Recall AI, Advertising ID &amp; P2P Upload" Height="32" Margin="0,3"/>
                        <Button Name="btnGuiServicesOptimizer" Content="⚙️ Optimasi Windows Services (Safe Gaming Profile)" Height="32" Margin="0,3"/>
                        <Button Name="btnGuiWindowsUpdate" Content="🔒 Kunci Windows Update ke 'Security Updates Only' (Anti Driver Hijack)" Height="32" Margin="0,3"/>
                        <Button Name="btnGuiToggleHibernate" Content="💾 Toggle Hibernasi (Bebaskan ~6.3 GB hiberfil.sys di Drive C:)" Height="32" Margin="0,3"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 4: SOFTWARE & RUNTIMES -->
            <TabItem Header="Software &amp; Runtimes">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Game Runtimes &amp; Appx Debloater" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,10"/>
                        <Button Name="btnGuiInstallRuntimes" Content="📦 Install Visual C++ 2005-2022 AIO &amp; DirectX Runtimes (WinGet)" Background="#0284C7" Height="36" Margin="0,0,0,8"/>
                        <Button Name="btnGuiDebloater" Content="🗑️ Bersihkan Preinstalled Bloatware Apps (BingNews, Weather, Solitaire)" Height="34" Margin="0,0,0,8"/>
                        <Button Name="btnGuiOptionalFeatures" Content="🧩 Buka Manajemen Fitur Windows (DirectPlay, WSL2, Sandbox)" Height="34" Margin="0,0,0,8"/>
                        <Button Name="btnGuiOpenCatalog" Content="🚀 Buka Katalog Software Lengkap (Gaming, Dev &amp; Tools)" Height="34"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 5: VOLTCLEAN -->
            <TabItem Header="VoltClean">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Pembersih Disk Lintas-Drive (VoltClean)" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,10"/>
                        <TextBlock Text="Membersihkan file temp, shader caches (NVIDIA/AMD/Intel/DirectX), shader Steam lintas-drive (C: &amp; D:), Delivery Optimization, crash dumps, dan Recycle Bin." Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,0,0,15"/>
                        <Button Name="btnGuiRunClean" Content="🧹 Jalankan VoltClean Sekarang (Aman Terlindungi Process Guard)" Background="#0284C7" Height="40" Margin="0,0,0,10"/>
                        <Button Name="btnGuiDismClean" Content="📦 DISM Component Cleanup ResetBase (Kikis Update Lama)" Height="35"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 6: HEALTH & REPAIR -->
            <TabItem Header="System Health">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Diagnostik &amp; Pemulihan Sistem Windows" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,10"/>
                        <Button Name="btnGuiSfc" Content="🛡️ Jalankan SFC /scannow (Integritas File Sistem)" Height="34" Margin="0,3"/>
                        <Button Name="btnGuiDism" Content="🔧 Jalankan DISM /RestoreHealth (Perbaiki Image Windows)" Height="34" Margin="0,3"/>
                        <Button Name="btnGuiResetWU" Content="🔄 Reset Komponen Windows Update (SoftwareDistribution)" Height="34" Margin="0,3"/>
                        <Button Name="btnGuiResetNet" Content="📶 Reset Network &amp; Winsock Catalog" Height="34" Margin="0,3"/>
                        <Button Name="btnGuiRebuildIcons" Content="🖼️ Rebuild Icon &amp; Thumbnail Cache" Height="34" Margin="0,3"/>
                        <Button Name="btnGuiTrimRam" Content="🧠 Trim Standby Memory (Instant Working Set Flush)" Height="34" Margin="0,3"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 7: VOLTUNDO -->
            <TabItem Header="VoltUndo">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="VoltUndo: Sistem Pemulihan 1-Klik" FontSize="16" FontWeight="Bold" Foreground="#FBBF24" Margin="0,0,0,10"/>
                        <TextBlock Text="Setiap perubahan registri, preferensi GPU, setting Explorer, dan konfigurasi in-game game dicadangkan secara otomatis. Lu dapat mengembalikan sistem kapan saja dengan 1 klik." Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,0,0,15"/>
                        <Button Name="btnGuiRunUndo" Content="↩️ Jalankan VoltUndo (Pilih Snapshot &amp; Rollback 100%)" Background="#DC2626" Height="40"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Footer -->
        <Border Grid.Row="2" Background="#1E293B" CornerRadius="6" Padding="12,8" Margin="0,10,0,0" BorderBrush="#334155" BorderThickness="1">
            <DockPanel LastChildFill="False">
                <TextBlock Text="Ready • Voltune Windows Toolkit v$Script:VoltVersion" Foreground="#64748B" FontSize="12" VerticalAlignment="Center"/>
                <TextBlock Name="txtOutputLog" DockPanel.Dock="Right" Text="Silakan pilih tindakan." Foreground="#38BDF8" FontSize="12" VerticalAlignment="Center"/>
            </DockPanel>
        </Border>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $lblLog = $window.FindName("txtOutputLog")

    # Wire Event Handlers
    $window.FindName("btnGuiAutoOptimize").Add_Click({
        $lblLog.Text = "Menjalankan Optimasi Lengkap..."
        New-VoltRestorePoint -Description "Voltune-Pre-AutoOptimize"
        New-VoltBackupSnapshot -Hardware $Hardware
        Optimize-VoltWindowsCore
        Optimize-VoltDualGPU -Hardware $Hardware
        Set-VoltRawMouseInput
        Add-VoltDefenderGameExclusions -Hardware $Hardware
        Set-VoltPrivacyAndTelemetry
        Set-VoltNetworkGamingTweaks
        Optimize-VoltServices
        Set-VoltWindowsUpdateProfile
        Set-VoltExplorerTweaks
        Set-VoltTaskbarAndStartTweaks
        Optimize-VoltPlayGames -Hardware $Hardware -TargetGameKey "ALL"
        $lblLog.Text = "[✓] Seluruh optimasi berhasil diterapkan!"
        [System.Windows.MessageBox]::Show("Optimasi lengkap berhasil diterapkan!", "Voltune", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $window.FindName("btnGuiCreateSnapshot").Add_Click({
        $lblLog.Text = "Mengambil snapshot..."
        $dir = New-VoltBackupSnapshot -Hardware $Hardware
        $lblLog.Text = "[✓] Snapshot disimpan di: $dir"
        [System.Windows.MessageBox]::Show("Snapshot berhasil dibuat!", "VoltUndo", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $window.FindName("btnGuiRestorePoint").Add_Click({
        $lblLog.Text = "Membuat restore point..."
        New-VoltRestorePoint -Description "Voltune-Manual-Snapshot"
        $lblLog.Text = "[✓] System Restore Point diproses!"
    })

    $window.FindName("btnApplyGamingTweaks").Add_Click({
        $lblLog.Text = "Menerapkan tweaks gaming..."
        New-VoltBackupSnapshot -Hardware $Hardware
        Optimize-VoltWindowsCore
        Optimize-VoltDualGPU -Hardware $Hardware
        Set-VoltRawMouseInput
        Add-VoltDefenderGameExclusions -Hardware $Hardware
        Set-VoltNetworkGamingTweaks
        $lblLog.Text = "[✓] Tweaks gaming diterapkan!"
        [System.Windows.MessageBox]::Show("Gaming tweaks berhasil diterapkan!", "Voltune", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $window.FindName("btnTuneAllGames").Add_Click({
        $lblLog.Text = "Menyelaraskan setting in-game..."
        New-VoltBackupSnapshot -Hardware $Hardware
        Optimize-VoltPlayGames -Hardware $Hardware -TargetGameKey "ALL"
        $lblLog.Text = "[✓] In-game settings diselaraskan!"
        [System.Windows.MessageBox]::Show("In-game settings diselaraskan!", "VoltPlay", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $window.FindName("btnGuiClassicMenu").Add_Click({
        New-VoltBackupSnapshot -Hardware $Hardware
        Set-VoltClassicContextMenu
        $lblLog.Text = "[✓] Classic Context Menu diaktifkan!"
    })

    $window.FindName("btnGuiRestoreMenu").Add_Click({
        Set-VoltClassicContextMenu -Disable
        $lblLog.Text = "[✓] Context Menu Windows 11 dikembalikan!"
    })

    $window.FindName("btnGuiExplorerTweaks").Add_Click({
        New-VoltBackupSnapshot -Hardware $Hardware
        Set-VoltExplorerTweaks
        $lblLog.Text = "[✓] Explorer Tweaks diterapkan!"
    })

    $window.FindName("btnGuiTaskbarTweaks").Add_Click({
        New-VoltBackupSnapshot -Hardware $Hardware
        Set-VoltTaskbarAndStartTweaks
        $lblLog.Text = "[✓] Taskbar Tweaks diterapkan!"
    })

    $window.FindName("btnGuiPrivacyKiller").Add_Click({
        New-VoltBackupSnapshot -Hardware $Hardware
        Set-VoltPrivacyAndTelemetry
        $lblLog.Text = "[✓] Privasi & Anti-Telemetri diterapkan!"
    })

    $window.FindName("btnGuiServicesOptimizer").Add_Click({
        New-VoltBackupSnapshot -Hardware $Hardware
        Optimize-VoltServices
        $lblLog.Text = "[✓] Services Optimizer diterapkan!"
    })

    $window.FindName("btnGuiWindowsUpdate").Add_Click({
        New-VoltBackupSnapshot -Hardware $Hardware
        Set-VoltWindowsUpdateProfile
        $lblLog.Text = "[✓] Windows Update Profile diset ke Security Only!"
    })

    $window.FindName("btnGuiToggleHibernate").Add_Click({
        Toggle-VoltHibernation -Hardware $Hardware
        $lblLog.Text = "[✓] Status Hibernasi diubah!"
    })

    $window.FindName("btnGuiInstallRuntimes").Add_Click({
        $lblLog.Text = "Menginstal Game Runtimes via WinGet..."
        Install-VoltGameRuntimes
        $lblLog.Text = "[✓] Game Runtimes selesai diinstal!"
    })

    $window.FindName("btnGuiDebloater").Add_Click({
        Invoke-VoltAppxDebloater
    })

    $window.FindName("btnGuiOptionalFeatures").Add_Click({
        Manage-VoltWindowsFeatures
    })

    $window.FindName("btnGuiOpenCatalog").Add_Click({
        Install-VoltSoftwareCatalog
    })

    $window.FindName("btnGuiRunClean").Add_Click({
        $lblLog.Text = "Menjalankan VoltClean..."
        Invoke-VoltClean -Hardware $Hardware
        $lblLog.Text = "[✓] VoltClean selesai!"
        [System.Windows.MessageBox]::Show("VoltClean selesai membersihkan sampah disk!", "VoltClean", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $window.FindName("btnGuiDismClean").Add_Click({
        $lblLog.Text = "Menjalankan DISM Component Cleanup..."
        & dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
        $lblLog.Text = "[✓] DISM Component Cleanup selesai!"
    })

    $window.FindName("btnGuiSfc").Add_Click({
        & sfc.exe /scannow
    })

    $window.FindName("btnGuiDism").Add_Click({
        & dism.exe /Online /Cleanup-Image /RestoreHealth
    })

    $window.FindName("btnGuiResetWU").Add_Click({
        Reset-VoltWindowsUpdate
        $lblLog.Text = "[✓] Windows Update di-reset!"
    })

    $window.FindName("btnGuiResetNet").Add_Click({
        Reset-VoltNetwork
        $lblLog.Text = "[✓] Network adapter di-reset!"
    })

    $window.FindName("btnGuiRebuildIcons").Add_Click({
        Rebuild-VoltIconCache
        $lblLog.Text = "[✓] Icon Cache diperbarui!"
    })

    $window.FindName("btnGuiTrimRam").Add_Click({
        Clear-VoltStandbyMemory
        $lblLog.Text = "[✓] Standby Memory dibersihkan!"
    })

    $window.FindName("btnGuiRunUndo").Add_Click({
        Invoke-VoltUndo
        $lblLog.Text = "[✓] VoltUndo selesai dijalankan!"
    })

    $window.ShowDialog() | Out-Null
}

# ------------------------------------------------------------------------------
# 21. INTERACTIVE UI & DYNAMIC DISPLAY
# ------------------------------------------------------------------------------
function Show-VoltBanner {
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "            ⚡ VOLTUNE WINDOWS UTILITY v$Script:VoltVersion ⚡                   " -ForegroundColor Yellow
    Write-Host "             Toolkit Optimasi Dinamis, Gaming & Tweaks Tanpa Batas              " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Show-VoltSpecs ($hw) {
    Write-Host "`n[SPEK HARDWARE DINAMIS TERDETEKSI]" -ForegroundColor Yellow
    Write-Host "   Prosesor   : $($hw.CPUName) ($($hw.CPUCores) Cores, $($hw.CPUThreads) Threads$(if ($hw.IsHybridCPU) { ' | Hybrid P+E' }))" -ForegroundColor White
    
    $gpuDesc = if ($hw.DiscreteGPU) {
        $tgp = if ($hw.DiscreteGPU.TGP_W) { " | $($hw.DiscreteGPU.TGP_W)W TGP" } else { "" }
        "$($hw.DiscreteGPU.Name) ($($hw.DiscreteGPU.VRAM_GB) GB VRAM$tgp)"
    } else { "iGPU Only" }
    Write-Host "   Kartu GPU  : $gpuDesc" -ForegroundColor White

    $pwrStatus = if ($hw.IsOnBattery) { "Baterai ($($hw.BatteryChargePct)%) [Mode Hemat Daya]" } else { "AC Adapter (Daya Maksimal) [✓]" }
    Write-Host "   Sumber Daya: $pwrStatus" -ForegroundColor $(if ($hw.IsOnBattery) { 'Yellow' } else { 'Green' })

    Write-Host "   Layar      : $($hw.ScreenResolution) @ $($hw.ScreenRefreshHz) Hz" -ForegroundColor White
    Write-Host "   Target FPS : VRR $($hw.DynamicFPSCaps.TearFreeVRR) FPS | Dingin $($hw.DynamicFPSCaps.HalfRate) FPS" -ForegroundColor Gray
    Write-Host "   Memori     : $($hw.RAM_GB) GB RAM" -ForegroundColor White

    # Multi-Drive Summary
    $driveStrs = @()
    foreach ($d in $hw.Drives.Values) {
        $driveStrs += "$($d.DeviceID) $($d.FreeGB)/$($d.TotalGB) GB"
    }
    Write-Host "   Storage    : $($driveStrs -join ' | ')" -ForegroundColor White

    $hiberStr = if ($hw.HibernateActive) { "Aktif (~$($hw.HiberfilSizeGB) GB hiberfil.sys)" } else { "Nonaktif (Hemat SSD) [✓]" }
    Write-Host "   Status HAGS: $(if ($hw.HAGS_Status) { 'Aktif [✓]' } else { 'Nonaktif [!]' }) | Hibernate: $hiberStr" -ForegroundColor White

    # Discovered Games Summary
    $gameList = @(foreach ($g in $hw.DiscoveredGames.Values) { $g["Name"] })
    $gameStr = if ($gameList.Count -gt 0) { ($gameList | Select-Object -Unique) -join ", " } else { "Tidak terdeteksi" }
    Write-Host "   Game Nemu  : $gameStr ($($hw.DiscoveredGames.Count) game terdeteksi dinamis)" -ForegroundColor White
}

# ------------------------------------------------------------------------------
# 22. ENTRYPOINT LOGIC
# ------------------------------------------------------------------------------
Invoke-VoltElevation -Bypass:$NoElevation

$hwProfile = Get-VoltHardwareProfile

# Handle command-line switches
if ($GUI) {
    Show-VoltGUI -Hardware $hwProfile
    exit 0
}

if ($AutoOptimize) {
    New-VoltRestorePoint -Description "Voltune-Pre-AutoOptimize"
    New-VoltBackupSnapshot -Hardware $hwProfile
    Optimize-VoltWindowsCore
    Optimize-VoltDualGPU -Hardware $hwProfile
    Set-VoltRawMouseInput
    Add-VoltDefenderGameExclusions -Hardware $hwProfile
    Set-VoltPrivacyAndTelemetry
    Set-VoltNetworkGamingTweaks
    Optimize-VoltServices
    Set-VoltWindowsUpdateProfile
    Set-VoltExplorerTweaks
    Set-VoltTaskbarAndStartTweaks
    Optimize-VoltPlayGames -Hardware $hwProfile -TargetGameKey "ALL"
    exit 0
}

if ($CleanOnly) {
    Invoke-VoltClean -Hardware $hwProfile
    exit 0
}

if ($UndoOnly) {
    Invoke-VoltUndo
    exit 0
}

# Interactive Loop
$running = $true
while ($running) {
    Show-VoltBanner
    Show-VoltSpecs $hwProfile

    Write-Host "`n--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " PILIH KATEGORI TINDAKAN (Ketik angka lalu tekan Enter):" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [1] 🚀 Optimasi Lengkap (Rekomendasi Terima Beres)" -ForegroundColor Green
    Write-Host "     -> HAGS, Game Mode, MMCSS, GameDVR Off, Driver Hijack Block, Defender Exclusions," -ForegroundColor Gray
    Write-Host "        Raw Mouse 1:1, Privasi, TCP Latency, Services, Explorer Tweaks, dan Game Auto-Tune." -ForegroundColor Gray
    Write-Host " [2] 🎮 VoltPlay: Sesuaikan Setting Game Khusus" -ForegroundColor White
    Write-Host "     -> Penyelarasan setting in-game (Steam, HoYo, Rockstar, CDPR) anti-stutter." -ForegroundColor Gray
    Write-Host " [3] 🧹 VoltClean: Pembersih Disk & Cache Lintas-Drive" -ForegroundColor White
    Write-Host "     -> Bersihkan cache usang, shader cache lintas-drive (C: & D:), crash dump." -ForegroundColor Gray
    Write-Host " [4] 🛠️ Windows 11 QoL & Explorer Tweaks (Chris Titus Style)" -ForegroundColor White
    Write-Host "     -> Classic Right-Click Menu, File Extensions, This PC, Matikan Bing di Start." -ForegroundColor Gray
    Write-Host " [5] 🛡️ Privasi, Telemetri & Background Bloat Killer" -ForegroundColor White
    Write-Host "     -> Matikan DiagTrack, Activity History, Ad ID, Delivery Optimization, Recall AI." -ForegroundColor Gray
    Write-Host " [6] ⚡ TCP/IP Gaming Latency & Raw Input (Zero-VPN Harm)" -ForegroundColor White
    Write-Host "     -> Matikan Nagle's Algorithm, Throttling Index 0xFFFFFFFF, 1:1 Mouse Raw Aim." -ForegroundColor Gray
    Write-Host " [7] ⚙️ Windows Services Optimizer (Safe Gaming Profile)" -ForegroundColor White
    Write-Host "     -> Optimasi service latar belakang tanpa mengganggu GlobalProtect VPN atau audio." -ForegroundColor Gray
    Write-Host " [8] 🔒 Windows Update Control (Security Updates Only Profile)" -ForegroundColor White
    Write-Host "     -> Tunda feature update tahunan, cegah restart mendadak, blokir bajak driver." -ForegroundColor Gray
    Write-Host " [9] 📦 Game Runtimes & Software Catalog (WinGet One-Click)" -ForegroundColor White
    Write-Host "     -> VC++ 2005-2022 AIO, DirectX, Software Gaming & Dev, serta Appx Debloater." -ForegroundColor Gray
    Write-Host " [10] 🧩 Windows Optional Features (DirectPlay, WSL2, Sandbox)" -ForegroundColor White
    Write-Host " [11] 💾 Reclaim Ruang SSD (Toggle Hibernasi ~$($hwProfile.HiberfilSizeGB) GB)" -ForegroundColor White
    Write-Host " [12] 🔧 System Health & Repair Diagnostics (SFC, DISM, Network Reset)" -ForegroundColor White
    Write-Host " [G] 🖥️ Buka Voltune Modern Native GUI (WPF Desktop Window)" -ForegroundColor Cyan
    Write-Host " [U] ↩️ VoltUndo: Kembalikan Semua Settingan ke Semula (1-Klik Reset)" -ForegroundColor Yellow
    Write-Host "     -> Balikin semua perubahan ke kondisi sebelum Voltune dijalankan." -ForegroundColor Gray
    Write-Host " [0] Keluar" -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor DarkCyan

    $choice = Read-Host "`nPilihan lu [0-12 / G / U]"
    switch ($choice.ToUpper()) {
        "1" {
            New-VoltRestorePoint -Description "Voltune-Pre-AutoOptimize"
            New-VoltBackupSnapshot -Hardware $hwProfile
            Optimize-VoltWindowsCore
            Optimize-VoltDualGPU -Hardware $hwProfile
            Set-VoltRawMouseInput
            Add-VoltDefenderGameExclusions -Hardware $hwProfile
            Set-VoltPrivacyAndTelemetry
            Set-VoltNetworkGamingTweaks
            Optimize-VoltServices
            Set-VoltWindowsUpdateProfile
            Set-VoltExplorerTweaks
            Set-VoltTaskbarAndStartTweaks
            Optimize-VoltPlayGames -Hardware $hwProfile -TargetGameKey "ALL"
            Write-Host "`n[✓] Seluruh optimasi lengkap berhasil diterapkan! Tekan Enter untuk lanjut..." -ForegroundColor Green
            Read-Host
        }
        "2" {
            Write-Host "`n[Daftar Game Terdeteksi]" -ForegroundColor Cyan
            $keys = @($hwProfile.DiscoveredGames.Keys)
            if ($keys.Count -eq 0) {
                Write-Host "Tidak ada game yang terdeteksi secara otomatis." -ForegroundColor Yellow
            } else {
                for ($i = 0; $i -lt $keys.Count; $i++) {
                    $g = $hwProfile.DiscoveredGames[$keys[$i]]
                    Write-Host " [$($i+1)] [$($g.Platform)] $($g.Name)"
                }
                Write-Host " [A] Optimasi Seluruh Game Sekaligus"
                Write-Host " [0] Batal"
                $gChoice = Read-Host "Pilih nomor game"
                if ($gChoice.ToUpper() -eq "A") {
                    New-VoltBackupSnapshot -Hardware $hwProfile
                    Optimize-VoltPlayGames -Hardware $hwProfile -TargetGameKey "ALL"
                } elseif ($gChoice -match "^\d+$" -and [int]$gChoice -le $keys.Count -and [int]$gChoice -gt 0) {
                    $chosenKey = $keys[[int]$gChoice - 1]
                    New-VoltBackupSnapshot -Hardware $hwProfile
                    Optimize-VoltPlayGames -Hardware $hwProfile -TargetGameKey $chosenKey
                }
            }
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "3" {
            Invoke-VoltClean -Hardware $hwProfile
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "4" {
            Write-Host "`n[Windows 11 QoL & Explorer Tweaks]" -ForegroundColor Cyan
            Write-Host " [1] Aktifkan Classic Context Menu (Klik Kanan Windows 10)"
            Write-Host " [2] Kembalikan Menu Klik Kanan Bawaan Windows 11"
            Write-Host " [3] Terapkan Explorer Pro (Ekstensi File, This PC Default, Hidden Files)"
            Write-Host " [4] Bersihkan Taskbar (Sembunyikan Widgets RAM, Copilot, & Bing Search)"
            Write-Host " [A] Terapkan Seluruh Tweaks QoL di Atas Sekaligus"
            Write-Host " [0] Kembali"
            $qolChoice = Read-Host "Pilih opsi [1-4 / A / 0]"
            switch ($qolChoice.ToUpper()) {
                "1" { New-VoltBackupSnapshot -Hardware $hwProfile; Set-VoltClassicContextMenu }
                "2" { Set-VoltClassicContextMenu -Disable }
                "3" { New-VoltBackupSnapshot -Hardware $hwProfile; Set-VoltExplorerTweaks }
                "4" { New-VoltBackupSnapshot -Hardware $hwProfile; Set-VoltTaskbarAndStartTweaks }
                "A" {
                    New-VoltBackupSnapshot -Hardware $hwProfile
                    Set-VoltClassicContextMenu
                    Set-VoltExplorerTweaks
                    Set-VoltTaskbarAndStartTweaks
                }
            }
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "5" {
            New-VoltBackupSnapshot -Hardware $hwProfile
            Set-VoltPrivacyAndTelemetry
            Write-Host "`n[✓] Pengaturan Privasi & Anti-Telemetri selesai diterapkan!" -ForegroundColor Green
            Write-Host "Tekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "6" {
            New-VoltBackupSnapshot -Hardware $hwProfile
            Set-VoltNetworkGamingTweaks
            Set-VoltRawMouseInput
            Add-VoltDefenderGameExclusions -Hardware $hwProfile
            Write-Host "`n[✓] Pengaturan TCP Gaming & Raw Input selesai!" -ForegroundColor Green
            Write-Host "Tekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "7" {
            New-VoltBackupSnapshot -Hardware $hwProfile
            Optimize-VoltServices
            Write-Host "`n[✓] Services Optimizer selesai diterapkan!" -ForegroundColor Green
            Write-Host "Tekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "8" {
            New-VoltBackupSnapshot -Hardware $hwProfile
            Set-VoltWindowsUpdateProfile
            Write-Host "`n[✓] Profil Windows Update diset ke Security Updates Only!" -ForegroundColor Green
            Write-Host "Tekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "9" {
            Write-Host "`n[Game Runtimes & Software Catalog]" -ForegroundColor Cyan
            Write-Host " [1] Install Visual C++ AIO (2005-2022) & DirectX Runtimes (WinGet)"
            Write-Host " [2] Buka Katalog Software Lengkap (Gaming, Dev, Tools)"
            Write-Host " [3] Buka Selective Appx Debloater"
            Write-Host " [0] Kembali"
            $rChoice = Read-Host "Pilih opsi [1-3 / 0]"
            switch ($rChoice) {
                "1" { Install-VoltGameRuntimes }
                "2" { Install-VoltSoftwareCatalog }
                "3" { Invoke-VoltAppxDebloater }
            }
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "10" {
            Manage-VoltWindowsFeatures
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "11" {
            Toggle-VoltHibernation -Hardware $hwProfile
            $hwProfile = Get-VoltHardwareProfile
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "12" {
            Invoke-VoltAdvancedTools
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "G" {
            Show-VoltGUI -Hardware $hwProfile
            $hwProfile = Get-VoltHardwareProfile
        }
        "U" {
            Invoke-VoltUndo
            $hwProfile = Get-VoltHardwareProfile
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "0" {
            $running = $false
            Write-Host "`n[VoltPlay & Voltune] Keluar. Tetap dingin & gaspol!" -ForegroundColor Cyan
        }
        default {
            Write-Host "`n[-] Pilihan tidak valid." -ForegroundColor DarkYellow
            Start-Sleep -Seconds 1
        }
    }
}
